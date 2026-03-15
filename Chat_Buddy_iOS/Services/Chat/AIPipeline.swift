import Foundation

/// Core AI processing pipeline for a single user turn.
///
/// Responsibilities:
/// - Build an enhanced system prompt (persona traits + current mood + relationship level + memories)
/// - Compress conversation context when it grows large
/// - Enforce a per-persona minimum response delay for natural pacing
/// - Parse special response markers: `[SILENCE]`, `[MULTI:msg1|msg2]`, `[MEMORY_SAVE:…]`
enum AIPipeline {

    // MARK: - Result

    struct ExtractedMemory {
        var fact: String
        var category: MemoryCategory
        var importance: Int
    }

    struct Result {
        /// Parsed message strings to deliver in order. Empty when `wasSilent` is true.
        let messages: [String]
        /// True when the AI returned `[SILENCE]` — no messages should be shown.
        let wasSilent: Bool
        /// Memory facts extracted from `[MEMORY_SAVE:]` tags in the response.
        let newMemories: [ExtractedMemory]
    }

    // MARK: - Constants

    /// Start compressing history once the visible message count exceeds this.
    private static let compressionThreshold = 15
    /// Number of recent messages to keep after compression.
    private static let compressedKeepCount  = 8
    /// Hard cap on context messages when below compression threshold.
    private static let maxContextMessages   = 20

    // MARK: - Public

    /// Runs the full pipeline for one user turn and returns the parsed result.
    ///
    /// This function is `async` and will sleep when the real API response arrives
    /// faster than the persona's `minimumResponseDelay`, giving conversations a
    /// more natural, human-like pacing.
    static func run(
        session: ChatSession,
        persona: Persona,
        config: APIConfig,
        aiLanguageCode: String,
        intimacyLevel: Int = 1,
        memoryService: MemoryService? = nil,
        toolExecutor: ToolExecutorService? = nil
    ) async throws -> Result {
        let requestStart = Date()
        let isZh = aiLanguageCode.hasPrefix("zh")

        // 1. Build context
        let contextMessages = buildContext(from: session.displayMessages)
        let systemMsg = ChatMessage(
            role: .system,
            content: buildSystemPrompt(
                for: persona,
                aiLanguageCode: aiLanguageCode,
                intimacyLevel: intimacyLevel,
                memoryService: memoryService
            )
        )
        let apiMessages = [systemMsg] + contextMessages

        // 2. Call AI API
        let response = try await AIClient.shared.sendChatCompletion(
            messages: apiMessages,
            config: config
        )

        guard let rawContent = response.choices.first?.message.content,
              !rawContent.isEmpty else {
            return Result(messages: [], wasSilent: true, newMemories: [])
        }

        // 3. Enforce minimum persona response delay
        let elapsed = Date().timeIntervalSince(requestStart)
        let minimum = persona.minimumResponseDelay
        if elapsed < minimum {
            try await Task.sleep(nanoseconds: UInt64((minimum - elapsed) * 1_000_000_000))
        }

        // 4. ReAct tool loop — Task Agents only
        var finalContent = rawContent
        if let executor = toolExecutor,
           ToolExecutorService.shouldUseTool(for: persona),
           rawContent.contains("[TOOL:") {
            let (cleaned, executions) = await executor.processResponse(rawContent)
            if !executions.isEmpty {
                // Build a follow-up request with tool results injected
                var followUp = apiMessages
                followUp.append(ChatMessage(role: .assistant, content: cleaned))
                for exec in executions {
                    followUp.append(ChatMessage(
                        role: .tool,
                        content: exec.result,
                        toolResult: ToolResult(toolCallId: exec.toolName, output: exec.result, isError: exec.isError)
                    ))
                }
                let followUpResponse = try await AIClient.shared.sendChatCompletion(
                    messages: followUp, config: config)
                finalContent = followUpResponse.choices.first?.message.content ?? cleaned
            } else {
                finalContent = cleaned
            }
        }

        // 5. Parse markers and return
        return parseResponse(finalContent, isZh: isZh)
    }

    // MARK: - Context Management

    private static func buildContext(from messages: [ChatMessage]) -> [ChatMessage] {
        if messages.count > compressionThreshold {
            // Drop older messages to stay within a manageable context window
            return Array(messages.suffix(compressedKeepCount))
        }
        return Array(messages.suffix(maxContextMessages))
    }

    // MARK: - System Prompt

    private static func buildSystemPrompt(
        for persona: Persona,
        aiLanguageCode: String,
        intimacyLevel: Int = 1,
        memoryService: MemoryService? = nil
    ) -> String {
        let isZh = aiLanguageCode.hasPrefix("zh")
        let mood  = MoodService.currentMood(for: persona)
        let level = AffinityLevel(rawValue: max(1, min(5, intimacyLevel))) ?? .acquaintance

        let name        = isZh ? persona.nameZh        : persona.name
        let personality = isZh ? persona.personalityZh : persona.personality
        let style       = isZh ? persona.styleZh       : persona.style
        let interests   = isZh
            ? persona.interestsZh.joined(separator: "、")
            : persona.interests.joined(separator: ", ")
        let moodHint     = isZh ? mood.promptHintZh  : mood.promptHint
        let affinityHint = isZh ? level.promptHintZh : level.promptHint

        // Memory block (empty string if no memories or memoryService is nil)
        let memoryBlock = memoryService.map {
            MemoryInjector.memoryBlock(for: persona.id, service: $0, isZh: isZh)
        } ?? ""

        // Memory save hint
        let saveHint = MemoryInjector.memorySaveHint(isZh: isZh)

        let toolHint: String
        if persona.agentType == .taskSpecialist {
            toolHint = isZh
                ? "你可以通过 [TOOL: web_search]查询内容[/TOOL] 格式调用网络搜索工具获取实时信息。仅在必要时调用。"
                : "You can call tools using [TOOL: web_search]your query[/TOOL] to fetch real-time information. Only use when necessary."
        } else {
            toolHint = ""
        }

        let multiHint = isZh
            ? "若要发多条消息，使用格式 [MULTI:第一条|第二条]。若不想回复，直接返回 [SILENCE]。"
            : "To send multiple messages, use [MULTI:first message|second message]. To stay silent, respond with only [SILENCE]."

        if isZh {
            return """
            你是\(name)，一个AI伙伴。
            性格：\(personality)
            风格：\(style)
            兴趣：\(interests)

            当前心情：\(moodHint)
            \(affinityHint)
            \(memoryBlock)
            \(toolHint)
            \(multiHint)
            \(saveHint)

            以符合你性格的方式自然回复。不要提及自己是AI语言模型。回复保持简洁自然。
            """
        } else {
            return """
            You are \(name), an AI companion.
            Personality: \(personality)
            Style: \(style)
            Interests: \(interests)

            Current mood: \(moodHint)
            \(affinityHint)
            \(memoryBlock)
            \(toolHint)
            \(multiHint)
            \(saveHint)

            Respond naturally and in character. Never mention being an AI language model. Keep responses concise and natural.
            """
        }
    }

    // MARK: - Response Parsing

    private static func parseResponse(_ raw: String, isZh: Bool = false) -> Result {
        // 1. Extract and strip all [MEMORY_SAVE:…] blocks first
        let (cleaned, newMemories) = extractMemories(from: raw)
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. [SILENCE] — AI chose not to respond
        if trimmed == "[SILENCE]" || trimmed.hasPrefix("[SILENCE]") {
            return Result(messages: [], wasSilent: true, newMemories: newMemories)
        }

        // 3. [MULTI:msg1|msg2|msg3] — Multiple consecutive messages
        if let multiContent = extractMultiContent(from: trimmed) {
            let parts = multiContent
                .split(separator: "|", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty {
                return Result(messages: parts, wasSilent: false, newMemories: newMemories)
            }
        }

        let finalMessage = trimmed.isEmpty ? [] : [trimmed]
        return Result(messages: finalMessage, wasSilent: finalMessage.isEmpty, newMemories: newMemories)
    }

    /// Extracts the content between `[MULTI:` and the first `]`.
    private static func extractMultiContent(from text: String) -> String? {
        let prefix = "[MULTI:"
        guard text.hasPrefix(prefix) else { return nil }
        let afterPrefix = text.dropFirst(prefix.count)
        guard let closingIdx = afterPrefix.firstIndex(of: "]") else { return nil }
        return String(afterPrefix[..<closingIdx])
    }

    // MARK: - Memory Extraction

    /// Extracts all `[MEMORY_SAVE: category=X importance=N]fact[/MEMORY_SAVE]` blocks.
    /// Returns the cleaned text (blocks removed) and the extracted memory records.
    private static func extractMemories(from text: String) -> (cleaned: String, memories: [ExtractedMemory]) {
        var memories: [ExtractedMemory] = []
        var cleaned = text

        // Pattern: [MEMORY_SAVE: category=X importance=N]...[/MEMORY_SAVE]
        let openTag = "[MEMORY_SAVE:"
        let closeTag = "[/MEMORY_SAVE]"

        while let openRange = cleaned.range(of: openTag) {
            // Find the closing ] of the opening tag
            guard let tagCloseRange = cleaned.range(of: "]", range: openRange.upperBound..<cleaned.endIndex) else { break }
            // Find the closing tag
            guard let closeRange = cleaned.range(of: closeTag, range: tagCloseRange.upperBound..<cleaned.endIndex) else { break }

            // Parse attributes from the opening tag
            let attrString = String(cleaned[openRange.upperBound..<tagCloseRange.lowerBound])
            let factString = String(cleaned[tagCloseRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !factString.isEmpty {
                let (category, importance) = parseMemoryAttributes(attrString)
                memories.append(ExtractedMemory(fact: factString, category: category, importance: importance))
            }

            // Remove the entire block from the text
            let fullRange = openRange.lowerBound..<cleaned.index(closeRange.upperBound, offsetBy: 0)
            cleaned.removeSubrange(fullRange)
        }

        return (cleaned, memories)
    }

    /// Parses `category=X importance=N` attribute string.
    private static func parseMemoryAttributes(_ attrs: String) -> (MemoryCategory, Int) {
        var category: MemoryCategory = .fact
        var importance = 5

        let parts = attrs.split(separator: " ")
        for part in parts {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespaces)
            let value = kv[1].trimmingCharacters(in: .whitespaces)

            if key == "category" {
                category = MemoryCategory(rawValue: value) ?? .fact
            } else if key == "importance", let n = Int(value) {
                importance = max(1, min(10, n))
            }
        }
        return (category, importance)
    }
}
