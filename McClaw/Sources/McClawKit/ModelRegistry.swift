import Foundation

// MARK: - Registered Model

/// A model available for a CLI provider, used by the model registry.
public struct RegisteredModel: Identifiable, Codable, Sendable, Hashable {
    public var id: String { modelId }
    /// The model identifier passed to the CLI (e.g. "claude-sonnet-4-20250514").
    public let modelId: String
    /// Human-readable name (e.g. "Claude Sonnet 4").
    public let displayName: String
    /// Provider identifier (e.g. "claude", "chatgpt").
    public let provider: String
    /// Whether this is the recommended default for its provider.
    public let isDefault: Bool

    public init(modelId: String, displayName: String, provider: String, isDefault: Bool = false) {
        self.modelId = modelId
        self.displayName = displayName
        self.provider = provider
        self.isDefault = isDefault
    }
}

// MARK: - Model Registry

/// Static registry of known models per CLI provider.
/// Ollama models are primarily discovered dynamically via `ollama list`;
/// the registry provides a fallback default.
public enum ModelRegistry {

    /// Returns the known models for a given provider ID.
    public static func models(for providerId: String) -> [RegisteredModel] {
        switch providerId {
        case "claude":
            return claudeModels
        case "chatgpt":
            return chatGPTModels
        case "gemini":
            return geminiModels
        case "ollama":
            return ollamaModels
        default:
            return []
        }
    }

    /// Returns the default model for a provider, or nil if unknown.
    public static func defaultModel(for providerId: String) -> RegisteredModel? {
        models(for: providerId).first(where: \.isDefault)
    }

    /// Merges a static model list with dynamically discovered models.
    /// Dynamic entries not present in the static list are appended.
    /// Static entries are always preserved. Deduplication is by `modelId`.
    public static func merge(
        staticModels: [RegisteredModel],
        dynamicModels: [RegisteredModel]
    ) -> [RegisteredModel] {
        let staticIds = Set(staticModels.map(\.modelId))
        let newDynamic = dynamicModels.filter { !staticIds.contains($0.modelId) }
        return staticModels + newDynamic
    }

    // MARK: - Provider Model Lists

    private static let claudeModels: [RegisteredModel] = [
        RegisteredModel(
            modelId: "claude-sonnet-4-20250514",
            displayName: "Claude Sonnet 4",
            provider: "claude",
            isDefault: true
        ),
        RegisteredModel(
            modelId: "claude-opus-4-20250514",
            displayName: "Claude Opus 4",
            provider: "claude"
        ),
        RegisteredModel(
            modelId: "claude-haiku-4-5-20251001",
            displayName: "Claude Haiku 4.5",
            provider: "claude"
        ),
    ]

    private static let chatGPTModels: [RegisteredModel] = [
        RegisteredModel(
            modelId: "gpt-4o",
            displayName: "GPT-4o",
            provider: "chatgpt",
            isDefault: true
        ),
        RegisteredModel(
            modelId: "gpt-4o-mini",
            displayName: "GPT-4o Mini",
            provider: "chatgpt"
        ),
        RegisteredModel(
            modelId: "o3",
            displayName: "o3",
            provider: "chatgpt"
        ),
        RegisteredModel(
            modelId: "o4-mini",
            displayName: "o4 Mini",
            provider: "chatgpt"
        ),
    ]

    private static let geminiModels: [RegisteredModel] = [
        RegisteredModel(
            modelId: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            provider: "gemini",
            isDefault: true
        ),
        RegisteredModel(
            modelId: "gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash",
            provider: "gemini"
        ),
        RegisteredModel(
            modelId: "gemini-2.0-flash",
            displayName: "Gemini 2.0 Flash",
            provider: "gemini"
        ),
    ]

    private static let ollamaModels: [RegisteredModel] = [
        RegisteredModel(
            modelId: "llama3.2",
            displayName: "Llama 3.2",
            provider: "ollama",
            isDefault: true
        ),
    ]

    // MARK: - Ollama Output Parsing

    /// Parses the output of `ollama list` into registered models.
    /// Expected format: tabular with header line, first column is model name.
    /// Example line: `llama3.2:latest    3.2 GB    2 weeks ago`
    public static func parseOllamaList(_ output: String) -> [RegisteredModel] {
        let lines = output.components(separatedBy: .newlines)
        guard lines.count > 1 else { return [] }

        // Skip header line
        return lines.dropFirst().compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            // First whitespace-separated token is the model name (e.g. "llama3.2:latest")
            let columns = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let rawName = columns.first else { return nil }

            let modelId = String(rawName)
            // Strip ":latest" tag for display name, capitalize
            let baseName = modelId.replacingOccurrences(of: ":latest", with: "")
            let displayName = baseName
                .split(separator: ":")
                .first
                .map(String.init) ?? baseName

            return RegisteredModel(
                modelId: modelId,
                displayName: displayName.capitalized,
                provider: "ollama"
            )
        }
    }
}
