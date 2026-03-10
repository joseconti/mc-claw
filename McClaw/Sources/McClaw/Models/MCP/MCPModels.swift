import Foundation

// MARK: - Transport

/// MCP server transport type.
enum MCPTransport: String, Codable, Sendable, CaseIterable, Identifiable {
    case stdio
    case sse
    case streamableHTTP = "streamable-http"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stdio: "stdio"
        case .sse: "SSE"
        case .streamableHTTP: "Streamable HTTP"
        }
    }
}

// MARK: - Scope

/// MCP configuration scope (Claude-specific).
enum MCPScope: String, Codable, Sendable, CaseIterable, Identifiable {
    case user
    case project

    var id: String { rawValue }
}

// MARK: - Server Config

/// A configured MCP server.
struct MCPServerConfig: Identifiable, Codable, Sendable, Equatable {
    var id: String { "\(provider):\(name)" }
    let name: String
    let transport: MCPTransport
    let command: String?
    let args: [String]
    let url: String?
    let envVars: [String: String]
    let scope: MCPScope
    let provider: String

    init(
        name: String,
        transport: MCPTransport = .stdio,
        command: String? = nil,
        args: [String] = [],
        url: String? = nil,
        envVars: [String: String] = [:],
        scope: MCPScope = .user,
        provider: String
    ) {
        self.name = name
        self.transport = transport
        self.command = command
        self.args = args
        self.url = url
        self.envVars = envVars
        self.scope = scope
        self.provider = provider
    }
}

// MARK: - Form Data

/// Mutable form state for the MCP server editor.
struct MCPServerFormData: Sendable {
    var name: String = ""
    var transport: MCPTransport = .stdio
    var command: String = ""
    var argsText: String = ""
    var url: String = ""
    var envVars: [EnvVarEntry] = []
    var scope: MCPScope = .user

    /// Parse argsText (one arg per line or space-separated) into array.
    var parsedArgs: [String] {
        argsText
            .split(separator: "\n")
            .flatMap { $0.split(separator: " ") }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Validate the form data.
    var validationError: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return "Name is required." }
        if trimmedName.contains(" ") { return "Name cannot contain spaces." }

        switch transport {
        case .stdio:
            if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Command is required for stdio transport."
            }
        case .sse, .streamableHTTP:
            if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "URL is required for \(transport.displayName) transport."
            }
        }

        for entry in envVars where !entry.key.isEmpty {
            if entry.key.contains(" ") { return "Environment variable keys cannot contain spaces." }
        }

        return nil
    }

    /// Create form data from an existing server config (for editing).
    static func from(_ config: MCPServerConfig) -> MCPServerFormData {
        MCPServerFormData(
            name: config.name,
            transport: config.transport,
            command: config.command ?? "",
            argsText: config.args.joined(separator: "\n"),
            url: config.url ?? "",
            envVars: config.envVars.map { EnvVarEntry(key: $0.key, value: $0.value) },
            scope: config.scope
        )
    }
}

/// A single environment variable key-value pair.
struct EnvVarEntry: Identifiable, Sendable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

// MARK: - Provider Support

/// Which providers support MCP configuration.
enum MCPProviderSupport {
    /// Transports supported by a provider.
    static func supportedTransports(for provider: String) -> [MCPTransport] {
        switch provider {
        case "claude": MCPTransport.allCases
        case "gemini": [.stdio]
        default: []
        }
    }

    /// Whether a provider supports MCP.
    static func isSupported(_ provider: String) -> Bool {
        !supportedTransports(for: provider).isEmpty
    }

    /// Whether a provider supports scope selection.
    static func supportsScope(_ provider: String) -> Bool {
        provider == "claude"
    }

    /// Reason why MCP is not supported for a provider.
    static func unsupportedReason(_ provider: String) -> String? {
        switch provider {
        case "claude", "gemini": nil
        case "chatgpt": "ChatGPT CLI does not support MCP servers yet."
        case "ollama": "Ollama does not support MCP servers."
        default: "This provider does not support MCP configuration."
        }
    }
}

// MARK: - Errors

enum MCPError: Error, LocalizedError {
    case noCLI
    case unsupportedProvider(String)
    case invalidConfig(String)
    case fileIOError(String)
    case cliError(String)

    var errorDescription: String? {
        switch self {
        case .noCLI: "No CLI provider available."
        case .unsupportedProvider(let p): "\(p) does not support MCP."
        case .invalidConfig(let msg): "Invalid configuration: \(msg)"
        case .fileIOError(let msg): "File error: \(msg)"
        case .cliError(let msg): "CLI error: \(msg)"
        }
    }
}
