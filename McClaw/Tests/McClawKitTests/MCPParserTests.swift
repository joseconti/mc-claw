import Testing
import Foundation
@testable import McClawKit

@Suite("MCPParser - Claude CLI Args")
struct MCPParserClaudeArgsTests {

    @Test("Build add args for stdio server")
    func buildStdioArgs() {
        let args = MCPParser.buildClaudeAddArgs(
            name: "myserver",
            transport: "stdio",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
            url: nil,
            envVars: [:],
            scope: "user"
        )
        #expect(args == [
            "mcp", "add", "myserver", "-s", "user",
            "--", "npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"
        ])
    }

    @Test("Build add args for SSE server")
    func buildSSEArgs() {
        let args = MCPParser.buildClaudeAddArgs(
            name: "remote",
            transport: "sse",
            command: nil,
            args: [],
            url: "https://example.com/mcp",
            envVars: [:],
            scope: "project"
        )
        #expect(args == [
            "mcp", "add", "remote", "-s", "project",
            "--url", "https://example.com/mcp"
        ])
    }

    @Test("Build add args with env vars")
    func buildArgsWithEnvVars() {
        let args = MCPParser.buildClaudeAddArgs(
            name: "db",
            transport: "stdio",
            command: "uvx",
            args: ["mcp-server-sqlite"],
            url: nil,
            envVars: ["DB_PATH": "/data/app.db"],
            scope: "user"
        )
        #expect(args.contains("-e"))
        #expect(args.contains("DB_PATH=/data/app.db"))
        #expect(args.first == "mcp")
        #expect(args.last == "mcp-server-sqlite")
    }

    @Test("Build add args with multiple env vars sorted by key")
    func buildArgsMultipleEnvVars() {
        let args = MCPParser.buildClaudeAddArgs(
            name: "test",
            transport: "stdio",
            command: "node",
            args: ["server.js"],
            url: nil,
            envVars: ["Z_VAR": "last", "A_VAR": "first"],
            scope: "user"
        )
        // Env vars should be sorted: A_VAR before Z_VAR
        let eIndex1 = args.firstIndex(of: "A_VAR=first")!
        let eIndex2 = args.firstIndex(of: "Z_VAR=last")!
        #expect(eIndex1 < eIndex2)
    }

    @Test("Build remove args")
    func buildRemoveArgs() {
        let args = MCPParser.buildClaudeRemoveArgs(name: "myserver", scope: "user")
        #expect(args == ["mcp", "remove", "myserver", "-s", "user"])
    }

    @Test("Build list args")
    func buildListArgs() {
        let args = MCPParser.buildClaudeListArgs()
        #expect(args == ["mcp", "list"])
    }

    @Test("Build streamable-http args")
    func buildStreamableHTTPArgs() {
        let args = MCPParser.buildClaudeAddArgs(
            name: "api",
            transport: "streamable-http",
            command: nil,
            args: [],
            url: "https://api.example.com/mcp/stream",
            envVars: [:],
            scope: "user"
        )
        #expect(args.contains("--url"))
        #expect(args.contains("https://api.example.com/mcp/stream"))
    }
}

@Suite("MCPParser - Claude List Output Parsing")
struct MCPParserClaudeListTests {

    @Test("Parse empty output returns empty array")
    func parseEmpty() {
        #expect(MCPParser.parseClaudeListOutput("").isEmpty)
        #expect(MCPParser.parseClaudeListOutput("not json").isEmpty)
    }

    @Test("Parse user-scoped servers")
    func parseUserServers() {
        let json = """
        {
          "user": {
            "filesystem": {
              "type": "stdio",
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
            }
          }
        }
        """
        let servers = MCPParser.parseClaudeListOutput(json)
        #expect(servers.count == 1)
        #expect(servers[0].name == "filesystem")
        #expect(servers[0].transport == "stdio")
        #expect(servers[0].command == "npx")
        #expect(servers[0].args == ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])
        #expect(servers[0].scope == "user")
    }

    @Test("Parse multiple scopes")
    func parseMultipleScopes() {
        let json = """
        {
          "user": {
            "global-db": {
              "type": "stdio",
              "command": "uvx",
              "args": ["mcp-sqlite"]
            }
          },
          "project": {
            "local-api": {
              "type": "sse",
              "url": "http://localhost:3000/mcp"
            }
          }
        }
        """
        let servers = MCPParser.parseClaudeListOutput(json)
        #expect(servers.count == 2)

        let globalDb = servers.first { $0.name == "global-db" }
        #expect(globalDb?.scope == "user")
        #expect(globalDb?.command == "uvx")

        let localApi = servers.first { $0.name == "local-api" }
        #expect(localApi?.scope == "project")
        #expect(localApi?.transport == "sse")
        #expect(localApi?.url == "http://localhost:3000/mcp")
    }

    @Test("Parse server with env vars")
    func parseWithEnvVars() {
        let json = """
        {
          "user": {
            "mydb": {
              "type": "stdio",
              "command": "node",
              "args": ["server.js"],
              "env": {
                "DB_URL": "postgres://localhost/mydb",
                "API_KEY": "secret123"
              }
            }
          }
        }
        """
        let servers = MCPParser.parseClaudeListOutput(json)
        #expect(servers.count == 1)
        #expect(servers[0].envVars["DB_URL"] == "postgres://localhost/mydb")
        #expect(servers[0].envVars["API_KEY"] == "secret123")
    }
}

@Suite("MCPParser - Gemini Settings")
struct MCPParserGeminiTests {

    @Test("Parse Gemini settings with MCP servers")
    func parseGeminiSettings() {
        let json = """
        {
          "mcpServers": {
            "filesystem": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home"]
            },
            "sqlite": {
              "command": "uvx",
              "args": ["mcp-server-sqlite", "--db", "test.db"],
              "env": {"DB_PATH": "/data"}
            }
          },
          "otherSetting": true
        }
        """
        let data = json.data(using: .utf8)!
        let servers = MCPParser.parseGeminiSettings(data)

        #expect(servers.count == 2)

        let fs = servers.first { $0.name == "filesystem" }
        #expect(fs?.command == "npx")
        #expect(fs?.transport == "stdio")
        #expect(fs?.args == ["-y", "@modelcontextprotocol/server-filesystem", "/home"])

        let sqlite = servers.first { $0.name == "sqlite" }
        #expect(sqlite?.envVars["DB_PATH"] == "/data")
    }

    @Test("Parse empty Gemini settings")
    func parseEmptySettings() {
        let json = """
        {"otherSetting": true}
        """
        let data = json.data(using: .utf8)!
        #expect(MCPParser.parseGeminiSettings(data).isEmpty)
    }

    @Test("Update Gemini settings adds server")
    func updateGeminiSettings() throws {
        let existing = """
        {"otherSetting": true, "mcpServers": {}}
        """.data(using: .utf8)!

        let updated = MCPParser.updateGeminiSettings(
            existing: existing,
            serverName: "myserver",
            command: "node",
            args: ["index.js"],
            envVars: ["PORT": "3000"]
        )

        let data = try #require(updated)
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        // Existing settings preserved
        #expect(parsed["otherSetting"] as? Bool == true)

        // MCP server added
        let mcpServers = try #require(parsed["mcpServers"] as? [String: Any])
        let server = try #require(mcpServers["myserver"] as? [String: Any])
        #expect(server["command"] as? String == "node")
        #expect(server["args"] as? [String] == ["index.js"])
        let env = try #require(server["env"] as? [String: String])
        #expect(env["PORT"] == "3000")
    }

    @Test("Update Gemini settings creates file from scratch")
    func updateGeminiSettingsNewFile() throws {
        let updated = MCPParser.updateGeminiSettings(
            existing: nil,
            serverName: "test",
            command: "npx",
            args: ["server"],
            envVars: [:]
        )

        let data = try #require(updated)
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let mcpServers = try #require(parsed["mcpServers"] as? [String: Any])
        #expect(mcpServers["test"] != nil)
    }

    @Test("Remove from Gemini settings")
    func removeFromGeminiSettings() throws {
        let existing = """
        {
          "mcpServers": {
            "keep": {"command": "a", "args": []},
            "remove": {"command": "b", "args": []}
          }
        }
        """.data(using: .utf8)!

        let updated = MCPParser.removeFromGeminiSettings(existing: existing, serverName: "remove")
        let data = try #require(updated)
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let mcpServers = try #require(parsed["mcpServers"] as? [String: Any])
        #expect(mcpServers["keep"] != nil)
        #expect(mcpServers["remove"] == nil)
    }
}
