import Testing
@testable import McClawKit
import McClawProtocol

@Suite("Channel Status Parsing")
struct ChannelStatusTests {
    @Test("Parse WhatsApp channel status")
    func parseWhatsApp() {
        let value: AnyCodableValue = .dictionary([
            "configured": .bool(true),
            "linked": .bool(true),
            "running": .bool(true),
            "connected": .bool(true),
            "reconnectAttempts": .int(0),
        ])
        let status = parseChannelStatus(channelId: "whatsapp", from: value)
        #expect(status != nil)
        #expect(status?.channelId == "whatsapp")
        #expect(status?.configured == true)
        #expect(status?.running == true)
        #expect(status?.connected == true)
        #expect(status?.lastError == nil)
    }

    @Test("Parse Telegram channel - not configured")
    func parseTelegramNotConfigured() {
        let value: AnyCodableValue = .dictionary([
            "configured": .bool(false),
            "running": .bool(false),
        ])
        let status = parseChannelStatus(channelId: "telegram", from: value)
        #expect(status != nil)
        #expect(status?.configured == false)
        #expect(status?.running == false)
        #expect(status?.connected == false)
    }

    @Test("Parse channel with error")
    func parseChannelWithError() {
        let value: AnyCodableValue = .dictionary([
            "configured": .bool(true),
            "running": .bool(false),
            "lastError": .string("Connection refused"),
        ])
        let status = parseChannelStatus(channelId: "discord", from: value)
        #expect(status?.lastError == "Connection refused")
    }

    @Test("Parse non-dict returns nil")
    func parseInvalidInput() {
        let status = parseChannelStatus(channelId: "x", from: .string("bad"))
        #expect(status == nil)
    }

    @Test("Channel status summary")
    func statusSummary() {
        let connected = ParsedChannelStatus(
            channelId: "wa", configured: true, running: true, connected: true, lastError: nil)
        #expect(channelStatusSummary(connected) == "Connected")

        let running = ParsedChannelStatus(
            channelId: "tg", configured: true, running: true, connected: false, lastError: nil)
        #expect(channelStatusSummary(running) == "Running")

        let configured = ParsedChannelStatus(
            channelId: "dc", configured: true, running: false, connected: false, lastError: nil)
        #expect(channelStatusSummary(configured) == "Configured")

        let none = ParsedChannelStatus(
            channelId: "x", configured: false, running: false, connected: false, lastError: nil)
        #expect(channelStatusSummary(none) == "Not configured")
    }
}

@Suite("Plugin List Parsing")
struct PluginListTests {
    @Test("Parse plugins from array")
    func parsePluginsArray() {
        let value: AnyCodableValue = .array([
            .dictionary([
                "name": .string("mcclaw-plugin-memory-sqlite"),
                "version": .string("1.2.0"),
                "kind": .string("memory"),
                "description": .string("SQLite-based memory plugin"),
                "isEnabled": .bool(true),
            ]),
            .dictionary([
                "name": .string("mcclaw-plugin-web-search"),
                "version": .string("0.5.1"),
                "kind": .string("tool"),
                "description": .string("Web search tool"),
                "isEnabled": .bool(false),
            ]),
        ])
        let plugins = parsePluginsList(from: value)
        #expect(plugins.count == 2)
        #expect(plugins[0].name == "mcclaw-plugin-memory-sqlite")
        #expect(plugins[0].kind == "memory")
        #expect(plugins[0].isEnabled == true)
        #expect(plugins[1].name == "mcclaw-plugin-web-search")
        #expect(plugins[1].isEnabled == false)
    }

    @Test("Parse plugins from wrapper object")
    func parsePluginsWrapper() {
        let value: AnyCodableValue = .dictionary([
            "plugins": .array([
                .dictionary([
                    "name": .string("test-plugin"),
                    "version": .string("1.0.0"),
                    "kind": .string("general"),
                ]),
            ]),
        ])
        let plugins = parsePluginsList(from: value)
        #expect(plugins.count == 1)
        #expect(plugins[0].name == "test-plugin")
        #expect(plugins[0].isEnabled == true) // default
        #expect(plugins[0].description == nil)
    }

    @Test("Parse empty plugins")
    func parseEmptyPlugins() {
        #expect(parsePluginsList(from: .array([])).isEmpty)
        #expect(parsePluginsList(from: .string("bad")).isEmpty)
        #expect(parsePluginsList(from: .null).isEmpty)
    }

    @Test("Parse skips malformed entries")
    func parseMalformedEntries() {
        let value: AnyCodableValue = .array([
            .dictionary(["name": .string("good"), "version": .string("1.0")]),
            .dictionary(["version": .string("2.0")]), // missing name
            .string("not a dict"),
        ])
        let plugins = parsePluginsList(from: value)
        #expect(plugins.count == 1)
        #expect(plugins[0].name == "good")
    }
}


@Suite("Config Path Sensitivity")
struct ConfigSensitivityTests {
    @Test("Sensitive paths detected")
    func sensitivePaths() {
        #expect(isConfigPathSensitive("channels.telegram.token") == true)
        #expect(isConfigPathSensitive("discord.botPassword") == true)
        #expect(isConfigPathSensitive("some.secret.value") == true)
        #expect(isConfigPathSensitive("apiKey") == true)
        #expect(isConfigPathSensitive("webhook.key") == true)
    }

    @Test("Non-sensitive paths")
    func nonSensitivePaths() {
        #expect(isConfigPathSensitive("channels.telegram.mode") == false)
        #expect(isConfigPathSensitive("discord.enabled") == false)
        #expect(isConfigPathSensitive("name") == false)
    }
}
