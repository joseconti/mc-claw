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
        headers: [String: String] = [:],
        oauthClientId: String? = nil,
        oauthClientSecret: String? = nil,
        oauthCallbackPort: Int? = nil,
        scope: String
    ) -> [String] {
        var cliArgs = ["mcp", "add", name, "-s", scope]

        for (key, value) in envVars.sorted(by: { $0.key < $1.key }) {
            cliArgs += ["-e", "\(key)=\(value)"]
        }

        // Auth: headers (--header "Key: Value")
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            cliArgs += ["--header", "\(key): \(value)"]
        }

        // Auth: OAuth (--client-id, --client-secret, --callback-port)
        if let oauthClientId, !oauthClientId.isEmpty {
            cliArgs += ["--client-id", oauthClientId]
        }
        if let oauthClientSecret, !oauthClientSecret.isEmpty {
            cliArgs += ["--client-secret", oauthClientSecret]
        }
        if let oauthCallbackPort {
            cliArgs += ["--callback-port", String(oauthCallbackPort)]
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
        ["mcp", "list"]
    }

    /// Parse `claude mcp list` text output.
    /// Each line looks like: `claude.ai Name: https://url - ✓ Connected`
    /// or: `Name: /path/to/command args... - ✓ Connected`
    public static func parseClaudeListTextOutput(_ output: String) -> [ParsedMCPServer] {
        var servers: [ParsedMCPServer] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip header/status lines
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("Checking"),
                  trimmed.contains(": ") else { continue }

            // Format: "claude.ai Name: URL - Status" or "Name: URL - Status"
            // Split on first ": " to get name and rest
            guard let colonRange = trimmed.range(of: ": ") else { continue }

            var name = String(trimmed[trimmed.startIndex..<colonRange.lowerBound])
            let rest = String(trimmed[colonRange.upperBound...])

            // Remove "claude.ai " prefix if present
            if name.hasPrefix("claude.ai ") {
                name = String(name.dropFirst("claude.ai ".count))
            }

            // Extract URL (everything before " - ")
            let url: String
            if let dashRange = rest.range(of: " - ") {
                url = String(rest[rest.startIndex..<dashRange.lowerBound])
            } else {
                url = rest
            }

            guard !name.isEmpty, !url.isEmpty else { continue }

            // Determine transport from URL
            let transport: String
            if url.hasPrefix("http://") || url.hasPrefix("https://") {
                transport = "streamable-http"
            } else {
                transport = "stdio"
            }

            servers.append(ParsedMCPServer(
                name: name,
                transport: transport,
                command: transport == "stdio" ? url : nil,
                url: transport != "stdio" ? url : nil,
                scope: "user"
            ))
        }

        return servers.sorted { $0.name < $1.name }
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
        public let headers: [String: String]
        public let oauthClientId: String?
        public let oauthClientSecret: String?
        public let oauthCallbackPort: Int?
        public let scope: String

        public init(
            name: String, transport: String, command: String? = nil,
            args: [String] = [], url: String? = nil,
            envVars: [String: String] = [:], headers: [String: String] = [:],
            oauthClientId: String? = nil, oauthClientSecret: String? = nil,
            oauthCallbackPort: Int? = nil, scope: String = "user"
        ) {
            self.name = name
            self.transport = transport
            self.command = command
            self.args = args
            self.url = url
            self.envVars = envVars
            self.headers = headers
            self.oauthClientId = oauthClientId
            self.oauthClientSecret = oauthClientSecret
            self.oauthCallbackPort = oauthCallbackPort
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
                let headers = config["headers"] as? [String: String] ?? [:]
                let oauth = config["oauth"] as? [String: Any]
                let oauthClientId = oauth?["clientId"] as? String
                let oauthClientSecret = oauth?["clientSecret"] as? String
                let oauthCallbackPort = oauth?["callbackPort"] as? Int

                servers.append(ParsedMCPServer(
                    name: name,
                    transport: transport,
                    command: command,
                    args: args,
                    url: url,
                    envVars: envVars,
                    headers: headers,
                    oauthClientId: oauthClientId,
                    oauthClientSecret: oauthClientSecret,
                    oauthCallbackPort: oauthCallbackPort,
                    scope: scope
                ))
            }
        }

        return servers.sorted { $0.name < $1.name }
    }

    // MARK: - Claude Plugin .mcp.json Files

    /// Parse a single `.mcp.json` plugin file into MCP servers.
    /// Supports both flat format `{"name": {...}}` and wrapped `{"mcpServers": {"name": {...}}}`.
    public static func parseClaudePluginFile(_ data: Data) -> [ParsedMCPServer] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        // Some plugins wrap in "mcpServers" (e.g. stripe)
        let serversDict: [String: Any]
        if let wrapped = root["mcpServers"] as? [String: Any] {
            serversDict = wrapped
        } else {
            serversDict = root
        }

        var servers: [ParsedMCPServer] = []

        for (name, value) in serversDict {
            guard let config = value as? [String: Any] else { continue }

            let typeStr = config["type"] as? String
            let command = config["command"] as? String
            let args = config["args"] as? [String] ?? []
            let url = config["url"] as? String
            let envVars = config["env"] as? [String: String] ?? [:]
            let headers = config["headers"] as? [String: String] ?? [:]
            let oauth = config["oauth"] as? [String: Any]
            let oauthClientId = oauth?["clientId"] as? String
            let oauthClientSecret = oauth?["clientSecret"] as? String
            let oauthCallbackPort = oauth?["callbackPort"] as? Int

            // Determine transport: explicit "type" field, or infer from presence of "command"
            let transport: String
            if let typeStr {
                switch typeStr {
                case "http", "streamable-http": transport = "streamable-http"
                case "sse": transport = "sse"
                default: transport = typeStr
                }
            } else if command != nil {
                transport = "stdio"
            } else if url != nil {
                transport = "streamable-http"
            } else {
                transport = "stdio"
            }

            servers.append(ParsedMCPServer(
                name: name,
                transport: transport,
                command: command,
                args: args,
                url: url,
                envVars: envVars,
                headers: headers,
                oauthClientId: oauthClientId,
                oauthClientSecret: oauthClientSecret,
                oauthCallbackPort: oauthCallbackPort,
                scope: "user"
            ))
        }

        return servers
    }

    /// Scan a directory recursively for `.mcp.json` files and parse all servers.
    public static func scanClaudePluginDirectory(_ directoryURL: URL) -> [ParsedMCPServer] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var allServers: [ParsedMCPServer] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == ".mcp.json" else { continue }
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            allServers += parseClaudePluginFile(data)
        }

        // Deduplicate by name (keep first occurrence)
        var seen = Set<String>()
        return allServers.filter { seen.insert($0.name).inserted }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Gemini Settings JSON

    /// Parse Gemini `~/.gemini/settings.json` data into MCP servers.
    public static func parseGeminiSettings(_ data: Data) -> [ParsedMCPServer] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = root["mcpServers"] as? [String: Any] else {
            return []
        }

        // Read global auth setting: security.auth.selectedType
        let globalAuthType: String?
        if let security = root["security"] as? [String: Any],
           let auth = security["auth"] as? [String: Any] {
            globalAuthType = auth["selectedType"] as? String
        } else {
            globalAuthType = nil
        }

        var servers: [ParsedMCPServer] = []

        for (name, value) in mcpServers {
            guard let config = value as? [String: Any] else { continue }

            let command = config["command"] as? String
            let args = config["args"] as? [String] ?? []
            let envVars = config["env"] as? [String: String] ?? [:]
            let headers = config["headers"] as? [String: String] ?? [:]
            let httpUrl = config["httpUrl"] as? String

            // Per-server auth (oauth config inside server block)
            let serverAuth = config["auth"] as? [String: Any]
            let serverAuthType = serverAuth?["type"] as? String
                ?? config["authType"] as? String

            // Gemini uses "httpUrl" key for HTTP-based MCP servers
            let transport: String
            let url: String?
            if let httpUrl {
                transport = "streamable-http"
                url = httpUrl
            } else {
                transport = "stdio"
                url = nil
            }

            // Determine OAuth: per-server auth, or global auth for HTTP servers
            let effectiveAuthType = serverAuthType ?? (transport != "stdio" ? globalAuthType : nil)
            let isOAuth = effectiveAuthType?.contains("oauth") == true

            // Read per-server OAuth fields if present
            let oauthClientId = serverAuth?["clientId"] as? String
            let oauthClientSecret = serverAuth?["clientSecret"] as? String
            let oauthCallbackPort = serverAuth?["callbackPort"] as? Int

            servers.append(ParsedMCPServer(
                name: name,
                transport: transport,
                command: command,
                args: args,
                url: url,
                envVars: envVars,
                headers: headers,
                oauthClientId: isOAuth ? (oauthClientId ?? "") : nil,
                oauthClientSecret: oauthClientSecret,
                oauthCallbackPort: oauthCallbackPort,
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
        transport: String = "stdio",
        command: String? = nil,
        args: [String] = [],
        url: String? = nil,
        envVars: [String: String] = [:],
        headers: [String: String] = [:],
        authType: String = "none",
        oauthClientId: String? = nil,
        oauthClientSecret: String? = nil,
        oauthCallbackPort: Int? = nil
    ) -> Data? {
        var root: [String: Any]
        if let existing,
           let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
            root = parsed
        } else {
            root = [:]
        }

        var mcpServers = root["mcpServers"] as? [String: Any] ?? [:]

        var serverConfig: [String: Any] = [:]

        if transport == "stdio" {
            if let command {
                serverConfig["command"] = command
            }
            if !args.isEmpty {
                serverConfig["args"] = args
            }
        } else if let url {
            // Gemini uses "httpUrl" for HTTP-based servers
            serverConfig["httpUrl"] = url
        }

        if !envVars.isEmpty {
            serverConfig["env"] = envVars
        }

        if !headers.isEmpty {
            serverConfig["headers"] = headers
        }

        // OAuth: write per-server auth block and update global security.auth
        if authType == "oauth" {
            var authBlock: [String: Any] = ["type": "oauth-personal"]
            if let oauthClientId, !oauthClientId.isEmpty {
                authBlock["clientId"] = oauthClientId
            }
            if let oauthClientSecret, !oauthClientSecret.isEmpty {
                authBlock["clientSecret"] = oauthClientSecret
            }
            if let oauthCallbackPort {
                authBlock["callbackPort"] = oauthCallbackPort
            }
            serverConfig["auth"] = authBlock

            // Also set global security.auth.selectedType for Gemini CLI
            var security = root["security"] as? [String: Any] ?? [:]
            var securityAuth = security["auth"] as? [String: Any] ?? [:]
            securityAuth["selectedType"] = "oauth-personal"
            security["auth"] = securityAuth
            root["security"] = security
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
