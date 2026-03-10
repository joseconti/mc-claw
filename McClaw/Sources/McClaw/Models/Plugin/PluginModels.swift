import Foundation

/// Information about an installed plugin (from plugin ecosystem).
struct PluginInfo: Identifiable, Codable, Sendable {
    var id: String { name }
    let name: String            // npm package name
    let version: String
    let kind: PluginKind
    let description: String?
    let isEnabled: Bool
    let configSchema: [String: AnyCodableValue]?
}

/// Type of plugin in the plugin ecosystem.
enum PluginKind: String, Codable, Sendable {
    case tool           // Adds new tools to the agent
    case memory         // Provides memory/context storage
    case contextEngine  // Custom context assembly
    case channel        // Adds messaging channels
    case hook           // Event hooks (fire-and-forget or transform)
    case general        // General purpose
}
