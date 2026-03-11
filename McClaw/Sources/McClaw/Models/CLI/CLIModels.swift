import Foundation

/// Information about a detected CLI provider on the system.
struct CLIProviderInfo: Identifiable, Codable, Sendable {
    let id: String              // e.g. "claude", "chatgpt", "gemini", "ollama"
    let displayName: String     // e.g. "Claude CLI"
    let binaryPath: String?     // e.g. "/usr/local/bin/claude"
    let version: String?        // e.g. "1.2.3"
    let isInstalled: Bool
    let isAuthenticated: Bool
    let installMethod: CLIInstallMethod
    let supportedModels: [ModelInfo]
    let capabilities: CLICapabilities
    /// True for optional tool CLIs (e.g. agent-browser), not AI providers.
    let isToolCLI: Bool

    init(
        id: String,
        displayName: String,
        binaryPath: String?,
        version: String?,
        isInstalled: Bool,
        isAuthenticated: Bool,
        installMethod: CLIInstallMethod,
        supportedModels: [ModelInfo],
        capabilities: CLICapabilities,
        isToolCLI: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.binaryPath = binaryPath
        self.version = version
        self.isInstalled = isInstalled
        self.isAuthenticated = isAuthenticated
        self.installMethod = installMethod
        self.supportedModels = supportedModels
        self.capabilities = capabilities
        self.isToolCLI = isToolCLI
    }
}

/// How a CLI can be installed.
enum CLIInstallMethod: String, Codable, Sendable {
    case homebrew
    case npm
    case curl
    case appStore
    case manual
}

/// Capabilities of a specific CLI provider.
struct CLICapabilities: Codable, Sendable {
    let supportsStreaming: Bool
    let supportsToolUse: Bool
    let supportsVision: Bool
    let supportsThinking: Bool
    let supportsConversation: Bool
    let maxContextTokens: Int?
}

/// Information about an AI model available through a CLI.
struct ModelInfo: Identifiable, Codable, Sendable {
    var id: String { modelId }
    let modelId: String         // e.g. "claude-sonnet-4-20250514"
    let displayName: String     // e.g. "Claude Sonnet 4"
    let provider: String        // e.g. "anthropic"
    let contextWindow: Int?
    let pricing: ModelPricing?
}

/// Pricing information for a model.
struct ModelPricing: Codable, Sendable {
    let inputPerMillion: Double?
    let outputPerMillion: Double?
    let currency: String
}

/// Events emitted during CLI streaming execution.
enum CLIStreamEvent: Sendable {
    case text(String)
    case toolStart(name: String, id: String)
    case toolResult(id: String, result: String)
    case thinking(String)
    case error(String)
    case usage(inputTokens: Int, outputTokens: Int)
    case done
}
