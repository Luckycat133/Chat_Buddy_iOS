import Foundation

// MARK: - ToolCall / ToolResult

/// A tool invocation requested by the AI inside a message.
/// Used by Task Agent personas (Coder, Scholar, etc.) when ReAct
/// tool-calling is active.
struct ToolCall: Codable, Equatable {
    /// Unique per-invocation identifier (matches the corresponding ToolResult).
    let id: String
    /// Tool name, e.g. "web_search", "run_code".
    let name: String
    /// JSON-encoded arguments string as returned by the model.
    let arguments: String
}

/// The result returned after executing a ToolCall.
struct ToolResult: Codable, Equatable {
    /// Must match the originating `ToolCall.id`.
    let toolCallId: String
    /// Human-readable output displayed in the chat bubble.
    let output: String
    /// True when the tool execution produced an error.
    let isError: Bool
}

// MARK: - ChatMessage

/// OpenAI-compatible chat message format, extended with:
/// - `speakingPersonaId` for group-chat attribution
/// - `toolCall` / `toolResult` for ReAct tool execution
struct ChatMessage: Codable, Identifiable, Equatable {
    var id: String
    var role: Role
    var content: String
    var timestamp: Date
    var quotedMessageId: String?

    /// In group chats, the persona ID of the AI who sent this message.
    /// Nil for user messages and 1v1 assistant messages.
    var speakingPersonaId: String?

    /// Non-nil when this message encodes a tool invocation from the model.
    var toolCall: ToolCall?
    /// Non-nil when this message carries the result of a previous tool call.
    var toolResult: ToolResult?

    // MARK: Role

    enum Role: String, Codable {
        case system
        case user
        case assistant
        /// Synthetic role used internally to inject tool results back into the API.
        case tool
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, quotedMessageId
        case speakingPersonaId, toolCall, toolResult
    }

    // MARK: Initializers

    init(role: Role,
         content: String,
         quotedMessageId: String? = nil,
         speakingPersonaId: String? = nil,
         toolCall: ToolCall? = nil,
         toolResult: ToolResult? = nil) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.quotedMessageId = quotedMessageId
        self.speakingPersonaId = speakingPersonaId
        self.toolCall = toolCall
        self.toolResult = toolResult
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = (try? container.decode(Date.self, forKey: .timestamp)) ?? Date()
        quotedMessageId = try? container.decode(String.self, forKey: .quotedMessageId)
        speakingPersonaId = try? container.decode(String.self, forKey: .speakingPersonaId)
        toolCall = try? container.decode(ToolCall.self, forKey: .toolCall)
        toolResult = try? container.decode(ToolResult.self, forKey: .toolResult)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(quotedMessageId, forKey: .quotedMessageId)
        try container.encodeIfPresent(speakingPersonaId, forKey: .speakingPersonaId)
        try container.encodeIfPresent(toolCall, forKey: .toolCall)
        try container.encodeIfPresent(toolResult, forKey: .toolResult)
    }
}

// MARK: - OpenAI API Payloads (unchanged)

/// OpenAI-compatible chat completion request
struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

/// OpenAI-compatible chat completion response
struct ChatCompletionResponse: Codable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable {
        let index: Int
        let message: ResponseMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Codable {
        let role: String
        let content: String?
    }

    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}
