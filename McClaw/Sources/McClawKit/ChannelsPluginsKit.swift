import Foundation
import McClawProtocol

// MARK: - Channel Status Parsing

/// Parsed channel status from Gateway JSON.
public struct ParsedChannelStatus: Sendable {
    public let channelId: String
    public let configured: Bool
    public let running: Bool
    public let connected: Bool
    public let lastError: String?

    public init(channelId: String, configured: Bool, running: Bool, connected: Bool, lastError: String?) {
        self.channelId = channelId
        self.configured = configured
        self.running = running
        self.connected = connected
        self.lastError = lastError
    }
}

/// Parse a channel's status from an AnyCodableValue.
public func parseChannelStatus(channelId: String, from value: AnyCodableValue) -> ParsedChannelStatus? {
    guard case .dictionary(let dict) = value else { return nil }
    let configured = boolValue(dict["configured"]) ?? false
    let running = boolValue(dict["running"]) ?? false
    let connected = boolValue(dict["connected"]) ?? running
    let lastError = stringValue(dict["lastError"])
    return ParsedChannelStatus(
        channelId: channelId,
        configured: configured,
        running: running,
        connected: connected,
        lastError: lastError
    )
}

/// Derive a human-readable summary for a channel status.
public func channelStatusSummary(_ status: ParsedChannelStatus) -> String {
    if status.connected { return "Connected" }
    if status.running { return "Running" }
    if status.configured { return "Configured" }
    return "Not configured"
}

// MARK: - Plugin List Parsing

/// Parsed plugin info from Gateway JSON.
public struct ParsedPluginInfo: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let version: String
    public let kind: String
    public let description: String?
    public let isEnabled: Bool

    public init(name: String, version: String, kind: String, description: String?, isEnabled: Bool) {
        self.name = name
        self.version = version
        self.kind = kind
        self.description = description
        self.isEnabled = isEnabled
    }
}

/// Parse a plugins.list response from Gateway.
public func parsePluginsList(from value: AnyCodableValue) -> [ParsedPluginInfo] {
    let array: [AnyCodableValue]

    switch value {
    case .array(let arr):
        array = arr
    case .dictionary(let dict):
        if case .array(let arr) = dict["plugins"] {
            array = arr
        } else {
            return []
        }
    default:
        return []
    }

    return array.compactMap { item -> ParsedPluginInfo? in
        guard case .dictionary(let dict) = item else { return nil }
        guard let name = stringValue(dict["name"]),
              let version = stringValue(dict["version"]) else { return nil }
        let kind = stringValue(dict["kind"]) ?? "general"
        let description = stringValue(dict["description"])
        let isEnabled = boolValue(dict["isEnabled"]) ?? true
        return ParsedPluginInfo(
            name: name, version: version, kind: kind,
            description: description, isEnabled: isEnabled
        )
    }
}

// MARK: - Config Schema Helpers

/// Detect if a key path looks like a sensitive config field.
public func isConfigPathSensitive(_ key: String) -> Bool {
    let lower = key.lowercased()
    return lower.contains("token")
        || lower.contains("password")
        || lower.contains("secret")
        || lower.contains("apikey")
        || lower.hasSuffix("key")
}

// MARK: - AnyCodableValue helpers

private func stringValue(_ value: AnyCodableValue?) -> String? {
    guard case .string(let s) = value else { return nil }
    return s
}

private func boolValue(_ value: AnyCodableValue?) -> Bool? {
    guard case .bool(let b) = value else { return nil }
    return b
}

private func stringArray(_ value: AnyCodableValue?, key: String) -> [String] {
    guard case .dictionary(let dict) = value,
          case .array(let arr) = dict[key] else { return [] }
    return arr.compactMap { stringValue($0) }
}
