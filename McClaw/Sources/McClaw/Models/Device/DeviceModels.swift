import Foundation

/// A paired mobile device.
struct PairedDevice: Codable, Identifiable, Sendable {
    let deviceId: String
    let name: String
    let platform: DevicePlatform
    let pairedAt: Date
    var lastSeen: Date
    var permissions: DevicePermissions

    var id: String { deviceId }
}

/// Device platform.
enum DevicePlatform: String, Codable, Sendable {
    case ios
    case android
}

/// Granular permissions for a paired device.
struct DevicePermissions: Codable, Sendable {
    var chat: Bool = true
    var cronRead: Bool = true
    var cronWrite: Bool = true
    var channelsRead: Bool = true
    var channelsWrite: Bool = true
    var pluginsRead: Bool = true
    var pluginsWrite: Bool = true
    var execApprove: Bool = true
    var configRead: Bool = true
    var configWrite: Bool = false
    var nodeInvoke: Bool = false

    enum CodingKeys: String, CodingKey {
        case chat
        case cronRead = "cron.read"
        case cronWrite = "cron.write"
        case channelsRead = "channels.read"
        case channelsWrite = "channels.write"
        case pluginsRead = "plugins.read"
        case pluginsWrite = "plugins.write"
        case execApprove = "exec.approve"
        case configRead = "config.read"
        case configWrite = "config.write"
        case nodeInvoke = "node.invoke"
    }
}

/// QR code payload for device pairing.
struct PairingQRPayload: Codable, Sendable {
    let v: Int
    let gateway: String
    let gatewayRemote: String?
    let code: String
    let expires: Int

    enum CodingKeys: String, CodingKey {
        case v, gateway, code, expires
        case gatewayRemote = "gateway_remote"
    }
}

/// A pending pairing request from a mobile device.
struct PairingRequest: Codable, Sendable {
    let code: String
    let deviceName: String
    let devicePlatform: DevicePlatform
    let deviceId: String
}

/// Event when a device connects or disconnects.
struct DeviceConnectionEvent: Codable, Sendable {
    let deviceId: String
    let connected: Bool
    let timestamp: Date?
}

/// Notification names for device events.
extension Notification.Name {
    static let devicePairingRequested = Notification.Name("devicePairingRequested")
    static let deviceConnectionChanged = Notification.Name("deviceConnectionChanged")
}
