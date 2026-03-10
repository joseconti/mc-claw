import Foundation
import Logging
import McClawKit

/// Manages MCP server configuration with hybrid backend:
/// - Claude CLI: executes `claude mcp add/remove/list` via Process
/// - Gemini: reads/writes `~/.gemini/settings.json` directly
/// - ChatGPT/Ollama: unsupported (shows message in UI)
@MainActor
@Observable
final class MCPConfigManager {
    static let shared = MCPConfigManager()

    var servers: [MCPServerConfig] = []
    var isLoading = false
    var lastError: String?

    private let logger = Logger(label: "ai.mcclaw.mcp")
    private init() {}

    // MARK: - Public API

    /// Refresh MCP servers from all supported providers.
    func refreshServers() async {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        var allServers: [MCPServerConfig] = []

        for cli in AppState.shared.availableCLIs where MCPProviderSupport.isSupported(cli.id) {
            switch cli.id {
            case "claude":
                allServers += await refreshClaudeServers(cli: cli)
            case "gemini":
                allServers += refreshGeminiServers()
            default:
                break
            }
        }

        servers = allServers
    }

    /// Add a new MCP server for the specified provider.
    func addServer(_ form: MCPServerFormData, provider: String) async throws {
        guard MCPProviderSupport.isSupported(provider) else {
            throw MCPError.unsupportedProvider(provider)
        }

        if let error = form.validationError {
            throw MCPError.invalidConfig(error)
        }

        switch provider {
        case "claude":
            try await addClaudeServer(form)
        case "gemini":
            try addGeminiServer(form)
        default:
            throw MCPError.unsupportedProvider(provider)
        }

        await refreshServers()
    }

    /// Remove an MCP server.
    func removeServer(_ server: MCPServerConfig) async throws {
        switch server.provider {
        case "claude":
            try await removeClaudeServer(name: server.name, scope: server.scope)
        case "gemini":
            try removeGeminiServer(name: server.name)
        default:
            throw MCPError.unsupportedProvider(server.provider)
        }

        await refreshServers()
    }

    // MARK: - Claude CLI

    private func refreshClaudeServers(cli: CLIProviderInfo) async -> [MCPServerConfig] {
        guard let binaryPath = cli.binaryPath else { return [] }

        do {
            let args = MCPParser.buildClaudeListArgs()
            let output = try await runProcess(binaryPath: binaryPath, args: args)
            let parsed = MCPParser.parseClaudeListOutput(output)
            return parsed.map { $0.toConfig(provider: "claude") }
        } catch {
            logger.error("claude mcp list failed: \(error.localizedDescription)")
            return []
        }
    }

    private func addClaudeServer(_ form: MCPServerFormData) async throws {
        guard let cli = findCLI("claude"), let binaryPath = cli.binaryPath else {
            throw MCPError.noCLI
        }

        let envDict = Dictionary(
            uniqueKeysWithValues: form.envVars
                .filter { !$0.key.isEmpty }
                .map { ($0.key, $0.value) }
        )

        let args = MCPParser.buildClaudeAddArgs(
            name: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
            transport: form.transport.rawValue,
            command: form.transport == .stdio ? form.command.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            args: form.transport == .stdio ? form.parsedArgs : [],
            url: form.transport != .stdio ? form.url.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            envVars: envDict,
            scope: form.scope.rawValue
        )

        let output = try await runProcess(binaryPath: binaryPath, args: args)
        logger.info("claude mcp add: \(output)")
    }

    private func removeClaudeServer(name: String, scope: MCPScope) async throws {
        guard let cli = findCLI("claude"), let binaryPath = cli.binaryPath else {
            throw MCPError.noCLI
        }

        let args = MCPParser.buildClaudeRemoveArgs(name: name, scope: scope.rawValue)
        let output = try await runProcess(binaryPath: binaryPath, args: args)
        logger.info("claude mcp remove: \(output)")
    }

    // MARK: - Gemini

    private var geminiSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini")
            .appendingPathComponent("settings.json")
    }

    private func refreshGeminiServers() -> [MCPServerConfig] {
        guard let data = try? Data(contentsOf: geminiSettingsURL) else { return [] }
        let parsed = MCPParser.parseGeminiSettings(data)
        return parsed.map { $0.toConfig(provider: "gemini") }
    }

    private func addGeminiServer(_ form: MCPServerFormData) throws {
        let existing = try? Data(contentsOf: geminiSettingsURL)

        let envDict = Dictionary(
            uniqueKeysWithValues: form.envVars
                .filter { !$0.key.isEmpty }
                .map { ($0.key, $0.value) }
        )

        guard let updated = MCPParser.updateGeminiSettings(
            existing: existing,
            serverName: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
            command: form.command.trimmingCharacters(in: .whitespacesAndNewlines),
            args: form.parsedArgs,
            envVars: envDict
        ) else {
            throw MCPError.fileIOError("Failed to build settings JSON.")
        }

        do {
            let dir = geminiSettingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try updated.write(to: geminiSettingsURL, options: .atomic)
            logger.info("Gemini MCP server added: \(form.name)")
        } catch {
            throw MCPError.fileIOError(error.localizedDescription)
        }
    }

    private func removeGeminiServer(name: String) throws {
        guard let existing = try? Data(contentsOf: geminiSettingsURL) else {
            throw MCPError.fileIOError("Cannot read Gemini settings.")
        }

        guard let updated = MCPParser.removeFromGeminiSettings(existing: existing, serverName: name) else {
            throw MCPError.fileIOError("Failed to update settings JSON.")
        }

        do {
            try updated.write(to: geminiSettingsURL, options: .atomic)
            logger.info("Gemini MCP server removed: \(name)")
        } catch {
            throw MCPError.fileIOError(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func findCLI(_ id: String) -> CLIProviderInfo? {
        AppState.shared.availableCLIs.first { $0.id == id }
    }

    private func runProcess(binaryPath: String, args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment
        process.environment?["NO_COLOR"] = "1"

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw MCPError.cliError(errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }
}

// MARK: - ParsedMCPServer → MCPServerConfig

private extension MCPParser.ParsedMCPServer {
    func toConfig(provider: String) -> MCPServerConfig {
        MCPServerConfig(
            name: name,
            transport: MCPTransport(rawValue: transport) ?? .stdio,
            command: command,
            args: args,
            url: url,
            envVars: envVars,
            scope: MCPScope(rawValue: scope) ?? .user,
            provider: provider
        )
    }
}
