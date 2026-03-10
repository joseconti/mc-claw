import Foundation

/// Pure logic helpers for Alibaba Cloud DashScope provider, extracted for testability.
/// Handles endpoint building, API key validation, SSE streaming parsing, and model catalog.
public enum DashScopeKit {

    // MARK: - Region

    /// DashScope API regions with their base URLs.
    public enum Region: String, Sendable, CaseIterable, Codable {
        case international
        case usVirginia

        /// Base URL for the OpenAI-compatible endpoint.
        public var baseURL: String {
            switch self {
            case .international:
                return "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
            case .usVirginia:
                return "https://dashscope-us.aliyuncs.com/compatible-mode/v1"
            }
        }

        /// Display name for the region.
        public var displayName: String {
            switch self {
            case .international: return "International (Singapore)"
            case .usVirginia: return "US (Virginia)"
            }
        }
    }

    // MARK: - URLs

    /// Chat completions endpoint URL for a given region.
    public static func chatCompletionsURL(for region: Region) -> URL? {
        URL(string: "\(region.baseURL)/chat/completions")
    }

    /// Models list endpoint URL for a given region.
    public static func modelsURL(for region: Region) -> URL? {
        URL(string: "\(region.baseURL)/models")
    }

    // MARK: - API Key Validation

    /// Basic validation of a DashScope API key format.
    /// Keys are typically `sk-` prefixed strings of 32+ characters.
    public static func validateAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return false }
        // DashScope keys are typically sk- prefixed
        return trimmed.hasPrefix("sk-")
    }

    // MARK: - Keychain Service

    /// Keychain service identifier for DashScope API key.
    public static let keychainService = "com.mcclaw.dashscope"

    /// Keychain account identifier.
    public static let keychainAccount = "api-key"

    // MARK: - SSE Streaming

    /// Result of parsing a single SSE chunk line.
    public enum StreamChunkResult: Sendable, Equatable {
        /// Text content delta.
        case text(String)
        /// Stream finished (received [DONE]).
        case done
        /// Non-content line (comment, empty, etc.) — skip.
        case skip
        /// Error from the API.
        case error(String)
    }

    /// Parse a single line from an SSE stream (OpenAI-compatible format).
    /// Lines arrive as `data: {...}` or `data: [DONE]`.
    public static func parseStreamLine(_ line: String) -> StreamChunkResult {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip empty lines and SSE comments
        if trimmed.isEmpty || trimmed.hasPrefix(":") {
            return .skip
        }

        // SSE data prefix
        guard trimmed.hasPrefix("data: ") else {
            return .skip
        }

        let payload = String(trimmed.dropFirst(6))

        // End of stream marker
        if payload == "[DONE]" {
            return .done
        }

        // Parse JSON payload
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .skip
        }

        // Check for error
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return .error(message)
        }

        // Extract delta content from choices[0].delta.content
        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return .text(content)
        }

        // Check for finish_reason
        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let finishReason = first["finish_reason"] as? String,
           finishReason == "stop" {
            return .done
        }

        return .skip
    }

    // MARK: - Request Building

    /// Message role for chat completions.
    public enum MessageRole: String, Sendable {
        case system
        case user
        case assistant
    }

    /// A chat message for the request body.
    public struct ChatMessage: Sendable {
        public let role: MessageRole
        public let content: String

        public init(role: MessageRole, content: String) {
            self.role = role
            self.content = content
        }
    }

    /// Build the JSON request body for chat completions.
    public static func buildRequestBody(
        model: String,
        messages: [ChatMessage],
        stream: Bool = true
    ) -> Data? {
        var messagesArray: [[String: String]] = []
        for msg in messages {
            messagesArray.append([
                "role": msg.role.rawValue,
                "content": msg.content,
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": messagesArray,
            "stream": stream,
        ]

        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// Build a URLRequest for chat completions with streaming.
    public static func buildStreamRequest(
        region: Region,
        apiKey: String,
        model: String,
        messages: [ChatMessage]
    ) -> URLRequest? {
        guard let url = chatCompletionsURL(for: region),
              let body = buildRequestBody(model: model, messages: messages, stream: true) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    // MARK: - Model Catalog

    /// Information about a DashScope model available via the Coding Plan.
    public struct DashScopeModelInfo: Sendable, Equatable, Identifiable {
        public var id: String { modelId }
        public let modelId: String
        public let displayName: String
        /// Original provider of the model (e.g. "Alibaba", "Moonshot", "Zhipu").
        public let originalProvider: String
        /// Primary use case.
        public let category: ModelCategory
        /// Context window size in tokens (if known).
        public let contextWindow: Int?

        public init(
            modelId: String,
            displayName: String,
            originalProvider: String,
            category: ModelCategory,
            contextWindow: Int? = nil
        ) {
            self.modelId = modelId
            self.displayName = displayName
            self.originalProvider = originalProvider
            self.category = category
            self.contextWindow = contextWindow
        }
    }

    /// Model category for grouping in UI.
    public enum ModelCategory: String, Sendable, CaseIterable {
        case coding
        case general
        case thirdParty
    }

    /// Curated catalog of models available with the DashScope Coding Plan.
    public static let modelCatalog: [DashScopeModelInfo] = [
        // Qwen series — Coding
        DashScopeModelInfo(
            modelId: "qwen3-coder-plus",
            displayName: "Qwen 3 Coder Plus",
            originalProvider: "Alibaba",
            category: .coding,
            contextWindow: 131_072
        ),
        DashScopeModelInfo(
            modelId: "qwen3-coder-next",
            displayName: "Qwen 3 Coder Next",
            originalProvider: "Alibaba",
            category: .coding,
            contextWindow: 131_072
        ),

        // Qwen series — General
        DashScopeModelInfo(
            modelId: "qwen3.5-plus",
            displayName: "Qwen 3.5 Plus",
            originalProvider: "Alibaba",
            category: .general,
            contextWindow: 131_072
        ),
        DashScopeModelInfo(
            modelId: "qwen3-max",
            displayName: "Qwen 3 Max",
            originalProvider: "Alibaba",
            category: .general,
            contextWindow: 131_072
        ),

        // Third-party models
        DashScopeModelInfo(
            modelId: "kimi-k2.5",
            displayName: "Kimi K2.5",
            originalProvider: "Moonshot",
            category: .thirdParty,
            contextWindow: 131_072
        ),
        DashScopeModelInfo(
            modelId: "glm-5",
            displayName: "GLM-5",
            originalProvider: "Zhipu",
            category: .thirdParty,
            contextWindow: 131_072
        ),
        DashScopeModelInfo(
            modelId: "MiniMax-M2.5",
            displayName: "MiniMax M2.5",
            originalProvider: "MiniMax",
            category: .thirdParty,
            contextWindow: 131_072
        ),
    ]

    /// Default model ID for new installations.
    public static let defaultModelId = "qwen3-coder-plus"

    /// Find a model in the catalog by ID.
    public static func model(for modelId: String) -> DashScopeModelInfo? {
        modelCatalog.first { $0.modelId == modelId }
    }
}
