import SwiftUI

/// ViewModel for a single chat conversation
@Observable final class ChatViewModel {
    var inputText = ""
    var isTyping = false
    var errorMessage: String?
    var quotedMessageId: String? = nil

    // MARK: - Send Message

    /// Sends the current inputText and triggers an AI response via `AIPipeline`.
    func sendMessage(
        sessionId: String,
        chatStore: ChatStore,
        persona: Persona,
        apiConfigStore: APIConfigStore,
        localization: LocalizationManager,
        affinityService: AffinityService,
        draftService: DraftService,
        socialService: SocialService? = nil,
        memoryService: MemoryService? = nil,
        toolExecutor: ToolExecutorService? = nil
    ) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping else { return }

        inputText = ""
        let quotedId = quotedMessageId
        quotedMessageId = nil
        errorMessage = nil

        let userMsg = ChatMessage(role: .user, content: text, quotedMessageId: quotedId)
        chatStore.appendMessage(userMsg, to: sessionId)
        draftService.clear(for: sessionId)

        // Increment affinity for this persona (5-minute cooldown enforced inside)
        affinityService.addChatIntimacy(for: persona.id)
        let intimacyLevel = affinityService.level(for: persona.id).rawValue

        // Social: achievement + daily task tracking
        socialService?.onMessageSent(personaId: persona.id, chatStore: chatStore)

        isTyping = true
        Task {
            await fetchResponse(
                sessionId: sessionId,
                chatStore: chatStore,
                persona: persona,
                apiConfigStore: apiConfigStore,
                aiLanguageCode: localization.resolvedAILanguage,
                intimacyLevel: intimacyLevel,
                memoryService: memoryService,
                toolExecutor: toolExecutor
            )
        }
    }

    // MARK: - AI Response

    private func fetchResponse(
        sessionId: String,
        chatStore: ChatStore,
        persona: Persona,
        apiConfigStore: APIConfigStore,
        aiLanguageCode: String,
        intimacyLevel: Int,
        memoryService: MemoryService? = nil,
        toolExecutor: ToolExecutorService? = nil
    ) async {
        guard apiConfigStore.activeConfig.isValid else {
            errorMessage = "API not configured — please go to Settings → API."
            isTyping = false
            return
        }

        guard let currentSession = chatStore.session(id: sessionId) else {
            isTyping = false
            return
        }

        let config = apiConfigStore.activeConfig
        do {
            let result = try await AIPipeline.run(
                session: currentSession,
                persona: persona,
                config: config,
                aiLanguageCode: aiLanguageCode,
                intimacyLevel: intimacyLevel,
                memoryService: memoryService,
                toolExecutor: toolExecutor
            )

            // Persist any new memories extracted from the response
            for extracted in result.newMemories {
                memoryService?.addMemory(
                    personaId: persona.id,
                    fact: extracted.fact,
                    category: extracted.category,
                    importance: extracted.importance
                )
            }

            if !result.wasSilent {
                for (index, content) in result.messages.enumerated() {
                    if index > 0 {
                        // Brief pause between consecutive messages in a multi-message response
                        try await Task.sleep(nanoseconds: 800_000_000)
                    }
                    let aiMsg = ChatMessage(role: .assistant, content: content)
                    chatStore.appendMessage(aiMsg, to: sessionId)
                }
            }
        } catch is CancellationError {
            // View dismissed — discard silently
        } catch {
            errorMessage = error.localizedDescription
        }

        isTyping = false
    }
}

// MARK: - Group Chat Extension

extension ChatViewModel {

    /// Sends a message in a group chat context.
    /// After the user message is stored, 1–3 randomly selected personas from the group
    /// each respond independently with their own `AIPipeline.run` call.
    func sendGroupMessage(
        sessionId: String,
        groupPersonaIds: [String],
        chatStore: ChatStore,
        primaryPersona: Persona,
        apiConfigStore: APIConfigStore,
        localization: LocalizationManager,
        affinityService: AffinityService,
        draftService: DraftService,
        socialService: SocialService? = nil,
        memoryService: MemoryService? = nil
    ) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping else { return }

        inputText = ""
        let quotedId = quotedMessageId
        quotedMessageId = nil
        errorMessage = nil

        let userMsg = ChatMessage(role: .user, content: text, quotedMessageId: quotedId)
        chatStore.appendMessage(userMsg, to: sessionId)
        draftService.clear(for: sessionId)
        socialService?.onMessageSent(personaId: primaryPersona.id, chatStore: chatStore)

        // Pick 1–3 responders at random
        let responderIds = groupPersonaIds.shuffled().prefix(Int.random(in: 1...min(3, groupPersonaIds.count)))
        let responders = responderIds.compactMap { PersonaStore.persona(byId: $0) }

        isTyping = true
        Task {
            await fetchGroupResponses(
                sessionId: sessionId,
                responders: responders,
                chatStore: chatStore,
                apiConfigStore: apiConfigStore,
                aiLanguageCode: localization.resolvedAILanguage,
                affinityService: affinityService,
                memoryService: memoryService
            )
        }
    }

    private func fetchGroupResponses(
        sessionId: String,
        responders: [Persona],
        chatStore: ChatStore,
        apiConfigStore: APIConfigStore,
        aiLanguageCode: String,
        affinityService: AffinityService,
        memoryService: MemoryService? = nil
    ) async {
        guard apiConfigStore.activeConfig.isValid else {
            errorMessage = "API not configured — please go to Settings → API."
            isTyping = false
            return
        }

        let config = apiConfigStore.activeConfig

        for (index, persona) in responders.enumerated() {
            guard !Task.isCancelled else { break }

            // Brief inter-persona pause for naturalness
            if index > 0 {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.8...2.0) * 1_000_000_000))
            }

            guard let currentSession = chatStore.session(id: sessionId) else { break }
            let intimacyLevel = affinityService.level(for: persona.id).rawValue

            do {
                let result = try await AIPipeline.run(
                    session: currentSession,
                    persona: persona,
                    config: config,
                    aiLanguageCode: aiLanguageCode,
                    intimacyLevel: intimacyLevel,
                    memoryService: memoryService
                )

                for extracted in result.newMemories {
                    memoryService?.addMemory(
                        personaId: persona.id, fact: extracted.fact,
                        category: extracted.category, importance: extracted.importance
                    )
                }

                if !result.wasSilent {
                    for (msgIndex, content) in result.messages.enumerated() {
                        if msgIndex > 0 {
                            try? await Task.sleep(nanoseconds: 800_000_000)
                        }
                        // Tag message with which persona is speaking
                        var msg = ChatMessage(role: .assistant, content: content)
                        msg.speakingPersonaId = persona.id
                        chatStore.appendMessage(msg, to: sessionId)
                    }
                }
            } catch is CancellationError {
                break
            } catch {
                // Non-fatal: one persona failing doesn't block others
                print("[GroupChat] \(persona.name) response failed: \(error)")
            }
        }

        isTyping = false
    }
}
