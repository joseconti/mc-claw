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

    private var claudePluginsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("plugins")
    }

    private func refreshClaudeServers(cli: CLIProviderInfo) async -> [MCPServerConfig] {
        var allParsed: [MCPParser.ParsedMCPServer] = []

        // 1. Read from `claude mcp list` (user-configured servers via CLI/web/app)
        if let binaryPath = cli.binaryPath {
            do {
                let args = MCPParser.buildClaudeListArgs()
                let output = try await runProcess(binaryPath: binaryPath, args: args)
                let parsed = MCPParser.parseClaudeListTextOutput(output)
                logger.info("claude mcp list: \(parsed.count) servers parsed from \(output.count) bytes")
                allParsed += parsed
            } catch {
                logger.warning("claude mcp list failed: \(error.localizedDescription)")
                lastError = "Claude MCP: \(error.localizedDescription)"
            }
        }

        // 2. Read from plugin .mcp.json files (marketplace plugins)
        let pluginServers = MCPParser.scanClaudePluginDirectory(claudePluginsURL)
        allParsed += pluginServers

        // Deduplicate by name (CLI takes priority)
        var seen = Set<String>()
        let deduped = allParsed.filter { seen.insert($0.name).inserted }
        return deduped.map { $0.toConfig(provider: "claude") }
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

        let headerDict = form.parsedHeaders

        let args = MCPParser.buildClaudeAddArgs(
            name: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
            transport: form.transport.rawValue,
            command: form.transport == .stdio ? form.command.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            args: form.transport == .stdio ? form.parsedArgs : [],
            url: form.transport != .stdio ? form.url.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            envVars: envDict,
            headers: form.authType == .headers ? headerDict : [:],
            oauthClientId: form.authType == .oauth ? form.oauthClientId.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            oauthClientSecret: form.authType == .oauth ? form.oauthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            oauthCallbackPort: form.authType == .oauth ? Int(form.oauthCallbackPort) : nil,
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

        let headerDict = form.authType == .headers ? form.parsedHeaders : [:]

        guard let updated = MCPParser.updateGeminiSettings(
            existing: existing,
            serverName: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
            transport: form.transport.rawValue,
            command: form.command.trimmingCharacters(in: .whitespacesAndNewlines),
            args: form.parsedArgs,
            url: form.url.trimmingCharacters(in: .whitespacesAndNewlines),
            envVars: envDict,
            headers: headerDict,
            authType: form.authType.rawValue,
            oauthClientId: form.authType == .oauth ? form.oauthClientId.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            oauthClientSecret: form.authType == .oauth ? form.oauthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            oauthCallbackPort: form.authType == .oauth ? Int(form.oauthCallbackPort) : nil
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

    /// Run a CLI process off the MainActor to avoid blocking the UI.
    /// Reads stdout before waitUntilExit to prevent pipe buffer deadlocks.
    /// Uses HostEnvSanitizer + binary dir in PATH (same as CLIBridge) so
    /// tools like node/npx are found even when launched from a GUI app.
    private func runProcess(binaryPath: String, args: [String]) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = args

            // Use the same sanitized environment as CLIBridge so that
            // nvm/homebrew paths are available to child processes.
            var env = HostEnvSanitizer.sanitize(isShellWrapper: false)
            let binaryDir = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
            let currentPath = env["PATH"] ?? "/usr/bin:/bin"
            if !currentPath.contains(binaryDir) {
                env["PATH"] = "\(binaryDir):\(currentPath)"
            }
            env["NO_COLOR"] = "1"
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()

            // Read stdout BEFORE waitUntilExit to avoid pipe buffer deadlock.
            // If the process writes more than 64KB, the pipe buffer fills up and
            // the process blocks waiting for the reader — causing a deadlock.
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()

            process.waitUntilExit()

            let output = String(data: outData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                let errText = String(data: errData, encoding: .utf8) ?? "Unknown error"
                throw MCPError.cliError(errText.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            return output
        }.value
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
            headers: headers,
            oauthClientId: oauthClientId,
            oauthClientSecret: oauthClientSecret,
            oauthCallbackPort: oauthCallbackPort,
            scope: MCPScope(rawValue: scope) ?? .user,
            provider: provider
        )
    }
}
