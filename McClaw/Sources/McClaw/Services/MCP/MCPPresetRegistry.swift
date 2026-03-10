import Foundation

/// Registry of pre-configured MCP server presets.
/// Users can browse and install these with a single click instead of
/// manually configuring command, args, and options.
enum MCPPresetRegistry {

    /// All available presets.
    static var all: [MCPPreset] {
        [chromeDevTools, chromeDevToolsSlim]
    }

    /// Presets grouped by category.
    static var byCategory: [(MCPPreset.Category, [MCPPreset])] {
        MCPPreset.Category.allCases.compactMap { category in
            let presets = all.filter { $0.category == category }
            return presets.isEmpty ? nil : (category, presets)
        }
    }

    // MARK: - Chrome DevTools

    static var chromeDevTools: MCPPreset {
        MCPPreset(
            id: "chrome-devtools",
            name: "Chrome DevTools",
            description: String(localized: "preset.chrome_devtools.description", bundle: .module),
            icon: "globe.badge.chevron.backward",
            category: .browser,
            command: "npx",
            baseArgs: ["-y", "chrome-devtools-mcp@latest", "--no-usage-statistics"],
            options: [
                MCPPresetOption(
                    id: "headless",
                    label: String(localized: "preset.option.headless", bundle: .module),
                    help: String(localized: "preset.option.headless.help", bundle: .module),
                    kind: .toggle,
                    value: "false"
                ),
                MCPPresetOption(
                    id: "isolated",
                    label: String(localized: "preset.option.isolated", bundle: .module),
                    help: String(localized: "preset.option.isolated.help", bundle: .module),
                    kind: .toggle,
                    value: "false"
                ),
                MCPPresetOption(
                    id: "channel",
                    label: String(localized: "preset.option.channel", bundle: .module),
                    help: String(localized: "preset.option.channel.help", bundle: .module),
                    kind: .picker(["stable", "canary", "beta", "dev"]),
                    value: ""
                ),
                MCPPresetOption(
                    id: "viewport",
                    label: String(localized: "preset.option.viewport", bundle: .module),
                    help: String(localized: "preset.option.viewport.help", bundle: .module),
                    kind: .text,
                    value: ""
                ),
                MCPPresetOption(
                    id: "browser-url",
                    label: String(localized: "preset.option.browser_url", bundle: .module),
                    help: String(localized: "preset.option.browser_url.help", bundle: .module),
                    kind: .text,
                    value: ""
                ),
            ],
            requiresNode: true,
            requiresChrome: true
        )
    }

    static var chromeDevToolsSlim: MCPPreset {
        MCPPreset(
            id: "chrome-devtools-slim",
            name: "Chrome DevTools (Slim)",
            description: String(localized: "preset.chrome_devtools_slim.description", bundle: .module),
            icon: "globe",
            category: .browser,
            command: "npx",
            baseArgs: ["-y", "chrome-devtools-mcp@latest", "--slim", "--no-usage-statistics"],
            options: [
                MCPPresetOption(
                    id: "headless",
                    label: String(localized: "preset.option.headless", bundle: .module),
                    help: String(localized: "preset.option.headless.help", bundle: .module),
                    kind: .toggle,
                    value: "true"
                ),
                MCPPresetOption(
                    id: "isolated",
                    label: String(localized: "preset.option.isolated", bundle: .module),
                    help: String(localized: "preset.option.isolated.help", bundle: .module),
                    kind: .toggle,
                    value: "false"
                ),
                MCPPresetOption(
                    id: "viewport",
                    label: String(localized: "preset.option.viewport", bundle: .module),
                    help: String(localized: "preset.option.viewport.help", bundle: .module),
                    kind: .text,
                    value: ""
                ),
            ],
            requiresNode: true,
            requiresChrome: true
        )
    }
}
