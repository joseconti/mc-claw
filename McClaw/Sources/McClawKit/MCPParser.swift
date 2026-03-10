import Foundation

/// Pure parsing and argument-building logic for MCP server configuration.
/// Extracted for testability — no side effects, no Process execution.
public enum MCPParser {

    // MARK: - Claude CLI Args

    /// Build `claude mcp add` arguments from form data.
    /// - Returns: Arguments to pass to the claude binary (e.g. `["mcp", "add", "myserver", "-s", "user", "--", "npx", "server"]`)
    public static func buildClaudeAddArgs(
        name: String,
        transport: String,
        command: String?,
        args: [String],
        url: String?,
        envVars: [String: String],
        scope: String
    ) -> [String] {
        var cliArgs = ["mcp", "add", name, "-s", scope]

        for (key, value) in envVars.sorted(by: { $0.key < $1.key }) {
            cliArgs += ["-e", "\(key)=\(value)"]
        }

        switch transport {
        case "stdio":
            if let command {
                cliArgs += ["--", command]
                cliArgs += args
            }
        case "sse", "streamable-http":
            if let url {
                cliArgs += ["--url", url]
            }
        default:
            break
        }

        return cliArgs
    }

    /// Build `claude mcp remove` arguments.
    public static func buildClaudeRemoveArgs(name: String, scope: String) -> [String] {
        ["mcp", "remove", name, "-s", scope]
    }

    /// Build `claude mcp list` arguments.
    public static func buildClaudeListArgs() -> [String] {
        ["mcp", "list", "-j"]
    }

    // MARK: - Claude CLI Output Parsing

    /// Parsed MCP server from Claude CLI output.
    public struct ParsedMCPServer: Sendable, Equatable {
        public let name: String
        public let transport: String
        public let command: String?
        public let args: [String]
        public let url: String?
        public let envVars: [String: String]
        public let scope: String

        public init(
            name: String, transport: String, command: String? = nil,
            args: [String] = [], url: String? = nil,
            envVars: [String: String] = [:], scope: String = "user"
        ) {
            self.name = name
            self.transport = transport
            self.command = command
            self.args = args
            self.url = url
            self.envVars = envVars
            self.scope = scope
        }
    }

    /// Parse `claude mcp list -j` JSON output.
    /// The output is a JSON object with scope keys ("user", "project") each containing server configs.
    public static func parseClaudeListOutput(_ output: String) -> [ParsedMCPServer] {
        guard let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var servers: [ParsedMCPServer] = []

        for (scope, scopeValue) in root {
            guard let scopeServers = scopeValue as? [String: Any] else { continue }

            for (name, serverValue) in scopeServers {
                guard let config = serverValue as? [String: Any] else { continue }

                let transport = config["type"] as? String
                    ?? config["transport"] as? String
                    ?? "stdio"
                let command = config["command"] as? String
                let args = config["args"] as? [String] ?? []
                let url = config["url"] as? String
                let envVars = config["env"] as? [String: String] ?? [:]

                servers.append(ParsedMCPServer(
                    name: name,
                    transport: transport,
                    command: command,
                    args: args,
                    url: url,
                    envVars: envVars,
                    scope: scope
                ))
            }
        }

        return servers.sorted { $0.name < $1.name }
    }

    // MARK: - Gemini Settings JSON

    /// Parse Gemini `~/.gemini/settings.json` data into MCP servers.
    public static func parseGeminiSettings(_ data: Data) -> [ParsedMCPServer] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = root["mcpServers"] as? [String: Any] else {
            return []
        }

        var servers: [ParsedMCPServer] = []

        for (name, value) in mcpServers {
            guard let config = value as? [String: Any] else { continue }

            let command = config["command"] as? String
            let args = config["args"] as? [String] ?? []
            let envVars = config["env"] as? [String: String] ?? [:]

            servers.append(ParsedMCPServer(
                name: name,
                transport: "stdio",
                command: command,
                args: args,
                envVars: envVars,
                scope: "user"
            ))
        }

        return servers.sorted { $0.name < $1.name }
    }

    /// Update Gemini settings JSON with a new/updated MCP server.
    /// Preserves all existing non-MCP settings.
    public static func updateGeminiSettings(
        existing: Data?,
        serverName: String,
        command: String,
        args: [String],
        envVars: [String: String]
    ) -> Data? {
        var root: [String: Any]
        if let existing,
           let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
            root = parsed
        } else {
            root = [:]
        }

        var mcpServers = root["mcpServers"] as? [String: Any] ?? [:]

        var serverConfig: [String: Any] = [
            "command": command,
            "args": args,
        ]
        if !envVars.isEmpty {
            serverConfig["env"] = envVars
        }

        mcpServers[serverName] = serverConfig
        root["mcpServers"] = mcpServers

        return try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    /// Remove an MCP server from Gemini settings JSON.
    public static func removeFromGeminiSettings(existing: Data, serverName: String) -> Data? {
        guard var root = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
            return nil
        }

        var mcpServers = root["mcpServers"] as? [String: Any] ?? [:]
        mcpServers.removeValue(forKey: serverName)
        root["mcpServers"] = mcpServers

        return try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}
