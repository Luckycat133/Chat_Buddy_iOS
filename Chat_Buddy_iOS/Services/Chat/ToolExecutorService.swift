import Foundation

// MARK: - Tool Protocol

/// A pluggable tool that a Task Agent AI can invoke during a conversation.
protocol AITool: Sendable {
    var name: String { get }
    var description: String { get }
    /// Execute the tool and return a result string.
    func execute(arguments: String) async throws -> String
}

// MARK: - Web Search Tool (DuckDuckGo Instant Answer API — free, no key required)

struct WebSearchTool: AITool {
    let name = "web_search"
    let description = "Search the web for up-to-date information. Use when asked about current events, facts, or anything requiring fresh data. Arguments: plain search query string."

    func execute(arguments: String) async throws -> String {
        let query = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "No query provided." }

        // DuckDuckGo Instant Answer API — free, no auth
        var components = URLComponents(string: "https://api.duckduckgo.com/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        guard let url = components.url else { return "Invalid search query." }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return "Search service temporarily unavailable."
        }

        let decoded = try JSONDecoder().decode(DDGResponse.self, from: data)
        return decoded.summary
    }

    // MARK: - DDG Response Model

    private struct DDGResponse: Decodable {
        let abstractText: String
        let abstractURL: String
        let relatedTopics: [RelatedTopic]

        enum CodingKeys: String, CodingKey {
            case abstractText = "AbstractText"
            case abstractURL = "AbstractURL"
            case relatedTopics = "RelatedTopics"
        }

        struct RelatedTopic: Decodable {
            let text: String?
            enum CodingKeys: String, CodingKey { case text = "Text" }
        }

        /// Returns a compact summary string for injection into the AI context.
        var summary: String {
            var parts: [String] = []

            if !abstractText.isEmpty {
                parts.append(abstractText)
                if !abstractURL.isEmpty { parts.append("Source: \(abstractURL)") }
            }

            // Pull up to 3 related snippets
            let snippets = relatedTopics
                .compactMap { $0.text }
                .filter { !$0.isEmpty }
                .prefix(3)
            if !snippets.isEmpty {
                parts.append("Related:")
                parts.append(contentsOf: snippets.map { "• \($0)" })
            }

            return parts.isEmpty ? "No results found for the query." : parts.joined(separator: "\n")
        }
    }
}

// MARK: - Tool Executor Service

/// Manages registered tools and drives the ReAct (Reason + Act) loop for Task Agents.
///
/// Flow:
/// 1. User sends a message to a Task Agent.
/// 2. AI responds with `[TOOL: web_search]query goes here[/TOOL]`.
/// 3. `ToolExecutorService` intercepts, executes the tool, injects the result.
/// 4. AI produces the final answer with the tool result in context.
@Observable final class ToolExecutorService {

    private var tools: [String: any AITool] = [:]

    init() {
        register(WebSearchTool())
    }

    func register(_ tool: any AITool) {
        tools[tool.name] = tool
    }

    // MARK: - ReAct Loop

    struct ToolExecution {
        let toolName: String
        let arguments: String
        let result: String
        let isError: Bool
    }

    /// Parses `[TOOL: name]args[/TOOL]` blocks from raw AI text,
    /// executes each tool, and returns both the cleaned text and execution records.
    func processResponse(_ raw: String) async -> (cleaned: String, executions: [ToolExecution]) {
        var cleaned = raw
        var executions: [ToolExecution] = []

        let openTag = "[TOOL:"
        let closeTag = "[/TOOL]"

        while let openRange = cleaned.range(of: openTag) {
            // Parse tool name from opening tag: [TOOL: tool_name]
            guard let tagClose = cleaned.range(of: "]", range: openRange.upperBound..<cleaned.endIndex),
                  let contentClose = cleaned.range(of: closeTag, range: tagClose.upperBound..<cleaned.endIndex)
            else { break }

            let toolName = String(cleaned[openRange.upperBound..<tagClose.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let arguments = String(cleaned[tagClose.upperBound..<contentClose.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Execute the tool
            var result = ""
            var isError = false
            if let tool = tools[toolName] {
                do {
                    result = try await tool.execute(arguments: arguments)
                } catch {
                    result = "Tool error: \(error.localizedDescription)"
                    isError = true
                }
            } else {
                result = "Unknown tool: \(toolName)"
                isError = true
            }

            executions.append(ToolExecution(toolName: toolName, arguments: arguments, result: result, isError: isError))

            // Replace the entire [TOOL:...][/TOOL] block with the result placeholder
            let fullRange = openRange.lowerBound..<cleaned.index(contentClose.upperBound, offsetBy: 0)
            cleaned.replaceSubrange(fullRange, with: "[Tool result: \(result)]")
        }

        return (cleaned, executions)
    }

    /// Returns true when `personaId` belongs to a Task Agent persona.
    static func shouldUseTool(for persona: Persona) -> Bool {
        persona.agentType == .taskSpecialist
    }
}
