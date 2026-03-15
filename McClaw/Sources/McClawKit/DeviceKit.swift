import Foundation

/// Pure logic for device pairing and management: QR encoding, permission handling, validation.
/// No network calls, no side effects — fully testable.
public enum DeviceKit {

    // MARK: - Models

    /// QR code payload for device pairing.
    public struct QRPayload: Codable, Sendable, Equatable {
        public let v: Int
        public let gateway: String
        public let gatewayRemote: String?
        public let code: String
        public let expires: Int

        enum CodingKeys: String, CodingKey {
            case v, gateway, code, expires
            case gatewayRemote = "gateway_remote"
        }

        public init(v: Int = 1, gateway: String, gatewayRemote: String? = nil, code: String, expires: Int) {
            self.v = v
            self.gateway = gateway
            self.gatewayRemote = gatewayRemote
            self.code = code
            self.expires = expires
        }
    }

    /// Device platform.
    public enum Platform: String, Codable, Sendable, Equatable {
        case ios
        case android
    }

    // MARK: - QR Encoding

    /// Encode a QR payload to JSON Data suitable for CIFilter.qrCodeGenerator.
    public static func encodeQRPayload(_ payload: QRPayload) -> Data? {
        try? JSONEncoder().encode(payload)
    }

    /// Decode a QR payload from JSON Data.
    public static func decodeQRPayload(_ data: Data) -> QRPayload? {
        try? JSONDecoder().decode(QRPayload.self, from: data)
    }

    // MARK: - Pairing Code Validation

    /// Validate a pairing code format (XXXX-XXXX-XXXX, hex uppercase).
    public static func isValidPairingCode(_ code: String) -> Bool {
        let pattern = #"^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$"#
        return code.range(of: pattern, options: .regularExpression) != nil
    }

    /// Check if a timestamp (seconds since epoch) is expired.
    public static func isExpired(timestamp: Int) -> Bool {
        Date().timeIntervalSince1970 > Double(timestamp)
    }

    // MARK: - Permissions

    /// All permission keys in display order.
    public static func permissionKeys() -> [String] {
        [
            "chat",
            "cron.read",
            "cron.write",
            "channels.read",
            "channels.write",
            "plugins.read",
            "plugins.write",
            "exec.approve",
            "config.read",
            "config.write",
            "node.invoke",
        ]
    }

    /// Default permissions for a newly paired device.
    public static func defaultPermissions() -> [String: Bool] {
        [
            "chat": true,
            "cron.read": true,
            "cron.write": true,
            "channels.read": true,
            "channels.write": true,
            "plugins.read": true,
            "plugins.write": true,
            "exec.approve": true,
            "config.read": true,
            "config.write": false,
            "node.invoke": false,
        ]
    }

    /// Human-readable label for a permission key.
    public static func permissionLabel(for key: String) -> String {
        switch key {
        case "chat": "Chat"
        case "cron.read": "View Cron Jobs"
        case "cron.write": "Manage Cron Jobs"
        case "channels.read": "View Channels"
        case "channels.write": "Manage Channels"
        case "plugins.read": "View Plugins"
        case "plugins.write": "Manage Plugins"
        case "exec.approve": "Approve Exec Requests"
        case "config.read": "View Configuration"
        case "config.write": "Edit Configuration"
        case "node.invoke": "Invoke Nodes"
        default: key
        }
    }

    /// Human-readable description for a permission key.
    public static func permissionDescription(for key: String) -> String {
        switch key {
        case "chat": "Send and receive chat messages"
        case "cron.read": "View scheduled jobs and run logs"
        case "cron.write": "Create, update, and delete scheduled jobs"
        case "channels.read": "View channel status and configuration"
        case "channels.write": "Connect, disconnect, and configure channels"
        case "plugins.read": "View installed plugins"
        case "plugins.write": "Install, uninstall, and toggle plugins"
        case "exec.approve": "Approve or deny command execution requests"
        case "config.read": "View McClaw configuration"
        case "config.write": "Modify McClaw configuration"
        case "node.invoke": "Invoke node mode actions (screen, camera, location)"
        default: key
        }
    }

    // MARK: - Formatting

    /// Format a platform for display.
    public static func platformDisplayName(_ platform: Platform) -> String {
        switch platform {
        case .ios: "iOS"
        case .android: "Android"
        }
    }

    /// Format a relative time for "last seen" display.
    public static func lastSeenText(from date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let days = Int(interval / 86400)
        if days == 1 { return "Yesterday" }
        return "\(days)d ago"
    }
}
