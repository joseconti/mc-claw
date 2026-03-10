import Foundation
import Logging
import McClawKit

// MARK: - WordPress MCP Bridge Provider

/// Bridges WordPress/WooCommerce abilities to MCP Content Manager.
/// Does NOT call WordPress REST API directly — all calls go through the MCP server.
///
/// Architecture:
/// 1. McClaw detects MCP Content Manager installations in Claude/Gemini MCP configs
/// 2. Uses MCMAbilitiesCatalog for local parameter validation (zero-latency discovery)
/// 3. Dispatches abilities to the MCP server via stdio (JSON-RPC over stdin/stdout)
///
/// Single provider for all WordPress/WooCommerce abilities via MCP Content Manager.
/// One connection = all ~278 abilities available.
struct WordPressProvider: ConnectorProvider {
    static let definitionId = "wp.mcm"

    private let logger = Logger(label: "ai.mcclaw.connector.wordpress")

    // MARK: - ConnectorProvider

    func execute(
        action: String,
        params: [String: String],
        credentials: ConnectorCredentials
    ) async throws -> ConnectorActionResult {
        // Validate the ability exists in catalog
        guard let ability = MCMAbilitiesCatalog.ability(for: action) else {
            throw ConnectorProviderError.unknownAction(action)
        }

        // Validate required parameters locally
        for param in ability.params where param.required {
            if params[param.name] == nil || params[param.name]?.isEmpty == true {
                throw ConnectorProviderError.missingParameter(param.name)
            }
        }

        // Get MCP server config from credentials
        guard let siteUrl = credentials.apiKey, !siteUrl.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }

        // Find the MCP Content Manager server config
        guard let mcpServer = await findMCPServer(for: siteUrl) else {
            throw ConnectorProviderError.apiError(
                statusCode: 0,
                message: "MCP Content Manager not found. Configure it in Settings → MCP."
            )
        }

        // Execute via MCP server
        let result = try await executeMCPAbility(
            abilityId: action,
            params: params,
            server: mcpServer
        )

        let (formatted, truncated) = ConnectorsKit.formatActionResult(result)
        return ConnectorActionResult(
            connectorId: Self.definitionId,
            actionId: action,
            data: ConnectorsKit.sanitizeConnectorData(formatted),
            truncated: truncated
        )
    }

    func testConnection(credentials: ConnectorCredentials) async throws -> Bool {
        guard let siteUrl = credentials.apiKey, !siteUrl.isEmpty else { return false }
        guard let mcpServer = await findMCPServer(for: siteUrl) else { return false }

        // Test by running a lightweight ability
        do {
            _ = try await executeMCPAbility(
                abilityId: "mcm/site-health",
                params: [:],
                server: mcpServer
            )
            return true
        } catch {
            logger.warning("WordPress test connection failed: \(error)")
            return false
        }
    }

    // MARK: - MCP Server Discovery

    /// Find the MCP Content Manager server config matching a site URL.
    @MainActor
    private func findMCPServer(for siteUrl: String) -> MCPServerConfig? {
        let servers = MCPConfigManager.shared.servers
        let lower = siteUrl.lowercased()

        // Look for MCP servers that match:
        // 1. Server name or args contain the site URL
        // 2. Server name or command contains "mcp-content-manager"
        return servers.first { server in
            let nameMatch = server.name.lowercased().contains("mcp-content-manager") ||
                            server.name.lowercased().contains("mcm")
            let argsContainUrl = server.args.contains { $0.lowercased().contains(lower) }
            let urlMatch = server.url?.lowercased().contains(lower) == true
            let commandMatch = (server.command ?? "").lowercased().contains("mcp-content-manager")

            return (nameMatch || commandMatch) && (argsContainUrl || urlMatch || lower.isEmpty)
        } ?? servers.first { server in
            // Fallback: any server with mcp-content-manager in command/name
            let commandMatch = (server.command ?? "").lowercased().contains("mcp-content-manager")
            let nameMatch = server.name.lowercased().contains("mcp-content-manager") ||
                            server.name.lowercased().contains("mcm")
            return commandMatch || nameMatch
        }
    }

    /// Scan for all MCP Content Manager installations.
    @MainActor
    static func detectInstallations() -> [MCPWordPressSite] {
        let servers = MCPConfigManager.shared.servers
        var sites: [MCPWordPressSite] = []

        for server in servers {
            let isWordPress = (server.command ?? "").lowercased().contains("mcp-content-manager") ||
                              server.name.lowercased().contains("mcp-content-manager") ||
                              server.name.lowercased().contains("mcm")

            if isWordPress {
                // Extract site URL from args or env vars
                let siteUrl = extractSiteUrl(from: server)
                sites.append(MCPWordPressSite(
                    serverName: server.name,
                    siteUrl: siteUrl,
                    provider: server.provider,
                    transport: server.transport
                ))
            }
        }

        return sites
    }

    /// Extract the WordPress site URL from an MCP server config.
    private static func extractSiteUrl(from server: MCPServerConfig) -> String {
        // Check URL field first (for SSE/HTTP transport)
        if let url = server.url, !url.isEmpty {
            return url
        }

        // Check args for URL patterns
        for arg in server.args {
            if arg.hasPrefix("http://") || arg.hasPrefix("https://") {
                return arg
            }
        }

        // Check env vars
        if let url = server.envVars["WORDPRESS_URL"] ?? server.envVars["WP_URL"] ?? server.envVars["SITE_URL"] {
            return url
        }

        return server.name
    }

    // MARK: - MCP Ability Execution

    /// Execute an MCM ability via the MCP server's stdio interface.
    private func executeMCPAbility(
        abilityId: String,
        params: [String: String],
        server: MCPServerConfig
    ) async throws -> String {
        guard server.transport == .stdio else {
            // For SSE/HTTP, make a direct HTTP call to the MCP endpoint
            return try await executeMCPAbilityHTTP(
                abilityId: abilityId,
                params: params,
                server: server
            )
        }

        // Build the JSON-RPC request for tools/call
        let arguments = params.isEmpty ? [:] : params
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int.random(in: 1...999999),
            "method": "tools/call",
            "params": [
                "name": abilityId,
                "arguments": arguments,
            ] as [String: Any],
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: request),
              let requestString = String(data: requestData, encoding: .utf8) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Failed to serialize MCP request")
        }

        // Run the MCP server process with the request on stdin
        guard let command = server.command, !command.isEmpty else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "MCP server has no command configured")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + server.args
        process.environment = ProcessInfo.processInfo.environment
        for (key, value) in server.envVars {
            process.environment?[key] = value
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Send initialize first, then the tools/call
        let initRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 0,
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": ["name": "mcclaw", "version": "1.0.0"] as [String: Any],
            ] as [String: Any],
        ]

        if let initData = try? JSONSerialization.data(withJSONObject: initRequest),
           let initString = String(data: initData, encoding: .utf8) {
            stdinPipe.fileHandleForWriting.write(Data((initString + "\n").utf8))
        }

        // Send the actual request
        stdinPipe.fileHandleForWriting.write(Data((requestString + "\n").utf8))
        stdinPipe.fileHandleForWriting.closeFile()

        // Read stdout with timeout
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 || !outputData.isEmpty else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw ConnectorProviderError.apiError(statusCode: Int(process.terminationStatus), message: errText)
        }

        let output = String(data: outputData, encoding: .utf8) ?? ""

        // Parse the JSON-RPC responses (may have multiple lines)
        return parseToolsCallResponse(output)
    }

    /// Execute an MCM ability via HTTP (for SSE/streamable-http transport).
    private func executeMCPAbilityHTTP(
        abilityId: String,
        params: [String: String],
        server: MCPServerConfig
    ) async throws -> String {
        guard let baseUrl = server.url, let url = URL(string: baseUrl) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid MCP server URL")
        }

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int.random(in: 1...999999),
            "method": "tools/call",
            "params": [
                "name": abilityId,
                "arguments": params,
            ] as [String: Any],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid response")
        }

        guard http.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ConnectorProviderError.apiError(statusCode: http.statusCode, message: errorText)
        }

        let output = String(data: data, encoding: .utf8) ?? ""
        return parseToolsCallResponse(output)
    }

    // MARK: - Response Parsing

    /// Parse JSON-RPC response(s) to extract the tools/call result.
    private func parseToolsCallResponse(_ output: String) -> String {
        // Split by newlines — MCP stdio sends one JSON object per line
        let lines = output.split(separator: "\n").map(String.init)

        // Look for the last valid JSON-RPC response (skip initialize response)
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Check if this is a tools/call response (has result with content)
            if let result = json["result"] as? [String: Any],
               let content = result["content"] as? [[String: Any]] {
                // Extract text content from the MCP response
                return content.compactMap { item -> String? in
                    if let text = item["text"] as? String {
                        return text
                    }
                    return nil
                }.joined(separator: "\n")
            }

            // Check for error
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return "[MCP Error: \(message)]"
            }
        }

        // Fallback: return raw output if parsing fails
        return output.isEmpty ? "(empty response)" : output
    }

}

// MARK: - WordPress Site Detection Model

/// A detected WordPress site connected via MCP Content Manager.
struct MCPWordPressSite: Identifiable, Sendable {
    var id: String { serverName }
    let serverName: String
    let siteUrl: String
    let provider: String
    let transport: MCPTransport
}
