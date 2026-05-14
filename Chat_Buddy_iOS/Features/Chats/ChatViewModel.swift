import SwiftUI

struct ChatContext {
    let sessionId: String
    let chatStore: ChatStore
    let persona: Persona
    let apiConfigStore: APIConfigStore
    let aiLanguageCode: String
    let intimacyLevel: Int
    let affinityService: AffinityService
    let socialService: SocialService?
    let memoryService: MemoryService?
    let toolExecutor: ToolExecutorService?
}

extension ChatContext {
    static func build(
        sessionId: String,
        chatStore: ChatStore,
        persona: Persona,
        apiConfigStore: APIConfigStore,
        localization: LocalizationManager,
        affinityService: AffinityService,
        socialService: SocialService? = nil,
        memoryService: MemoryService? = nil,
        toolExecutor: ToolExecutorService? = nil
    ) -> ChatContext {
        ChatContext(
            sessionId: sessionId,
            chatStore: chatStore,
            persona: persona,
            apiConfigStore: apiConfigStore,
            aiLanguageCode: localization.resolvedAILanguage,
            intimacyLevel: affinityService.level(for: persona.id).rawValue,
            affinityService: affinityService,
            socialService: socialService,
            memoryService: memoryService,
            toolExecutor: toolExecutor
        )
    }
}

enum ChatViewModelConstants {
    static let interMessageDelayNanoseconds: UInt64 = 800_000_000
    static let groupResponseMinDelay: Double = 0.8
    static let groupResponseMaxDelay: Double = 2.0
}

enum ChatViewModelError: LocalizedError {
    case apiNotConfigured
    case sessionNotFound

    var errorDescription: String? {
        switch self {
        case .apiNotConfigured:
            return "API not configured — please go to Settings → API."
        case .sessionNotFound:
            return "Session not found."
        }
    }

    func localizedDescription(localization: LocalizationManager) -> String {
        switch self {
        case .apiNotConfigured:
            return localization.t("error_api_not_configured")
        case .sessionNotFound:
            return localization.t("error_session_not_found")
        }
    }
}

@Observable final class ChatViewModel {
    var inputText = ""
    var isTyping = false
    var errorMessage: String?
    var quotedMessageId: String? = nil

    private var currentTask: Task<Void, Never>?
    private var groupTask: Task<Void, Never>?

    func onDisappear() {
        currentTask?.cancel()
        groupTask?.cancel()
        currentTask = nil
        groupTask = nil
    }

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

        affinityService.addChatIntimacy(for: persona.id)
        if affinityService.score(for: persona.id) >= 100 {
            socialService?.onIntimacyMaxed()
        }
        socialService?.onMessageSent(personaId: persona.id, chatStore: chatStore)

        isTyping = true
        currentTask?.cancel()
        currentTask = Task {
            let context = ChatContext.build(
                sessionId: sessionId,
                chatStore: chatStore,
                persona: persona,
                apiConfigStore: apiConfigStore,
                localization: localization,
                affinityService: affinityService,
                socialService: socialService,
                memoryService: memoryService,
                toolExecutor: toolExecutor
            )
            await fetchResponse(context: context, localization: localization)
        }
    }

    private func fetchResponse(context: ChatContext, localization: LocalizationManager) async {
        guard context.apiConfigStore.activeConfig.isValid else {
            errorMessage = ChatViewModelError.apiNotConfigured.localizedDescription(localization: localization)
            isTyping = false
            return
        }

        guard let currentSession = context.chatStore.session(id: context.sessionId) else {
            isTyping = false
            return
        }

        let config = context.apiConfigStore.activeConfig
        let ragEnabled = StorageService.shared.get("knowledgeBase", default: KnowledgeBaseSettings(ragEnabled: false)).ragEnabled

        do {
            let result = try await AIPipeline.run(
                session: currentSession,
                persona: context.persona,
                config: config,
                aiLanguageCode: context.aiLanguageCode,
                intimacyLevel: context.intimacyLevel,
                memoryService: context.memoryService,
                toolExecutor: context.toolExecutor,
                ragEnabled: ragEnabled
            )

            saveNewMemories(result.newMemories, for: context.persona.id, service: context.memoryService)

            if !result.wasSilent {
                await appendMessages(result.messages, to: context.sessionId, in: context.chatStore)
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }

        isTyping = false
    }

    private func saveNewMemories(_ memories: [ExtractedMemory], for personaId: String, service: MemoryService?) {
        for extracted in memories {
            service?.addMemory(
                personaId: personaId,
                fact: extracted.fact,
                category: extracted.category,
                importance: extracted.importance
            )
        }
    }

    private func appendMessages(_ contents: [String], to sessionId: String, in chatStore: ChatStore) async {
        for (index, content) in contents.enumerated() {
            if index > 0 {
                try? await Task.sleep(nanoseconds: ChatViewModelConstants.interMessageDelayNanoseconds)
            }
            let aiMsg = ChatMessage(role: .assistant, content: content)
            chatStore.appendMessage(aiMsg, to: sessionId)
        }
    }
}

extension ChatViewModel {

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
        socialService?.onMessageSent(personaId: primaryPersona.id, chatStore: chatStore)

        let responderIds = groupPersonaIds.shuffled().prefix(Int.random(in: 1...min(3, groupPersonaIds.count)))
        let responders = responderIds.compactMap { PersonaStore.persona(byId: $0) }

        isTyping = true
        groupTask?.cancel()
        groupTask = Task {
            await fetchGroupResponses(
                sessionId: sessionId,
                responders: responders,
                chatStore: chatStore,
                apiConfigStore: apiConfigStore,
                aiLanguageCode: localization.resolvedAILanguage,
                affinityService: affinityService,
                memoryService: memoryService,
                toolExecutor: toolExecutor,
                localization: localization
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
        memoryService: MemoryService? = nil,
        toolExecutor: ToolExecutorService? = nil,
        localization: LocalizationManager
    ) async {
        guard apiConfigStore.activeConfig.isValid else {
            errorMessage = ChatViewModelError.apiNotConfigured.localizedDescription(localization: localization)
            isTyping = false
            return
        }

        let config = apiConfigStore.activeConfig

        await withTaskGroup(of: (personaId: String, messages: [(content: String, speakingPersonaId: String)]).self) { group in
            for (index, persona) in responders.enumerated() {
                guard !Task.isCancelled else { break }

                if index > 0 {
                    let delay = UInt64(Double.random(in: ChatViewModelConstants.groupResponseMinDelay...ChatViewModelConstants.groupResponseMaxDelay) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                }

                guard let currentSession = chatStore.session(id: sessionId) else { break }
                let intimacyLevel = affinityService.level(for: persona.id).rawValue

                group.addTask {
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

                        for extracted in result.newMemories {
                            memoryService?.addMemory(
                                personaId: persona.id, fact: extracted.fact,
                                category: extracted.category, importance: extracted.importance
                            )
                        }

                        return (persona.id, result.messages.map { ($0, persona.id) })
                    } catch is CancellationError {
                        return (persona.id, [])
                    } catch {
                        let personaName = persona.localizedName(language: localization.uiLanguage)
                        let errorMsg = localization.t("error_persona_unavailable")
                        let failContent = "⚠️ \(personaName) \(errorMsg)"
                        return (persona.id, [(failContent, persona.id)])
                    }
                }
            }

            var allResponses: [(personaId: String, messages: [(content: String, speakingPersonaId: String)])] = []
            for await response in group {
                allResponses.append(response)
            }

            let responderOrder = Dictionary(uniqueKeysWithValues: responders.enumerated().map { ($1.id, $0) })
            allResponses.sort { (responderOrder[$0.personaId] ?? 0) < (responderOrder[$1.personaId] ?? 0) }

            for response in allResponses {
                for (msgIndex, (content, speakingPersonaId)) in response.messages.enumerated() {
                    if msgIndex > 0 {
                        try? await Task.sleep(nanoseconds: ChatViewModelConstants.interMessageDelayNanoseconds)
                    }
                    let msg = ChatMessage(role: .assistant, content: content, speakingPersonaId: speakingPersonaId)
                    chatStore.appendMessage(msg, to: sessionId)
                }
            }
        }

        isTyping = false
    }
}

private struct KnowledgeBaseSettings: Codable {
    var ragEnabled: Bool
}
