/// McClawKit - Core library for McClaw.
/// Contains shared business logic, protocols, and utilities
/// used across the app and its extensions.

import Foundation

/// Protocol for types that can provide AI responses via CLI execution.
public protocol CLIProviderProtocol: Sendable {
    /// Unique identifier for this provider (e.g. "claude", "chatgpt")
    var identifier: String { get }

    /// Human-readable display name
    var displayName: String { get }

    /// Path to the CLI binary on disk
    var binaryPath: String? { get }

    /// Whether the CLI is installed and available
    var isAvailable: Bool { get }

    /// Execute a prompt and return a streaming response
    func execute(prompt: String, model: String?, options: CLIExecutionOptions) async throws -> AsyncStream<String>
}

/// Options for CLI execution.
public struct CLIExecutionOptions: Sendable {
    public let sessionId: String?
    public let maxTokens: Int?
    public let temperature: Double?
    public let systemPrompt: String?
    public let timeout: TimeInterval

    public init(
        sessionId: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        systemPrompt: String? = nil,
        timeout: TimeInterval = 300
    ) {
        self.sessionId = sessionId
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.systemPrompt = systemPrompt
        self.timeout = timeout
    }
}
