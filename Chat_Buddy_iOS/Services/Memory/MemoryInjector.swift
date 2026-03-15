import Foundation

/// Formats memory data for injection into AI system prompts.
enum MemoryInjector {

    static let maxInjectCount = 10

    // MARK: - Memory Block

    /// Returns a formatted memory block for the system prompt, or `""` if there are no memories.
    ///
    /// EN: "\nWHAT YOU REMEMBER ABOUT THE USER:\n• fact\n"
    /// ZH: "\n你对用户的记忆：\n• fact\n"
    static func memoryBlock(for personaId: String, service: MemoryService, isZh: Bool) -> String {
        let memories = service.relevantMemories(for: personaId, limit: maxInjectCount)
        guard !memories.isEmpty else { return "" }

        let header = isZh ? "\n你对用户的记忆：" : "\nWHAT YOU REMEMBER ABOUT THE USER:"
        let bullets = memories.map { "• \($0.fact)" }.joined(separator: "\n")
        return "\(header)\n\(bullets)\n"
    }

    // MARK: - Memory Save Hint

    /// Returns the system-prompt instruction telling the AI how to emit `[MEMORY_SAVE:]` markers.
    static func memorySaveHint(isZh: Bool) -> String {
        if isZh {
            return """

            若用户在对话中透露了关于自己的重要信息（偏好、事实、事件），请使用以下格式记录：
            [MEMORY_SAVE: category=preference importance=7]用户喜欢…[/MEMORY_SAVE]
            category 可为 preference / fact / event，importance 为 1-10 的整数。
            仅记录重要且具体的信息。不要在每条回复中都添加记忆标记。
            """
        } else {
            return """

            If the user reveals important information about themselves (preferences, facts, events), record it using:
            [MEMORY_SAVE: category=preference importance=7]User likes...[/MEMORY_SAVE]
            category must be preference / fact / event, importance is an integer 1-10.
            Only save important, specific information. Do not add memory tags to every reply.
            """
        }
    }
}
