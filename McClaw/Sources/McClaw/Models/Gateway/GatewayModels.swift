import Foundation
@_exported import McClawProtocol

/// Gateway connection health status.
enum GatewayStatus: String, Codable, Sendable {
    case connected
    case connecting
    case disconnected
    case error
}

/// Status of a messaging channel.
struct ChannelStatus: Identifiable, Codable, Sendable {
    var id: String { channelId }
    let channelId: String       // e.g. "whatsapp", "telegram", "slack"
    let displayName: String
    let isConnected: Bool
    let isEnabled: Bool
    let lastActivity: Date?
    let unreadCount: Int
}

/// Health snapshot from Gateway.
struct HealthSnapshot: Codable, Sendable {
    let timestamp: Date
    let gatewayUptime: TimeInterval
    let memoryUsage: Int64
    let activeConnections: Int
    let channelStatuses: [ChannelStatus]
    let pluginCount: Int
    let cronJobCount: Int
    let nodeCount: Int
}

/// A presence entry (active sessions/connections).
struct PresenceEntry: Identifiable, Codable, Sendable {
    var id: String { sessionId }
    let sessionId: String
    let platform: String
    let connectedAt: Date
    let lastActivity: Date
}
