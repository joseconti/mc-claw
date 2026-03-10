import Foundation
import McClawProtocol

/// Full status snapshot from the Gateway channels.status RPC.
struct ChannelsStatusSnapshot: Codable, Sendable {
    // MARK: - Per-channel status types

    struct WhatsAppSelf: Codable, Sendable {
        let e164: String?
        let jid: String?
    }

    struct WhatsAppDisconnect: Codable, Sendable {
        let at: Double
        let status: Int?
        let error: String?
        let loggedOut: Bool?
    }

    struct WhatsAppStatus: Codable, Sendable {
        let configured: Bool
        let linked: Bool
        let authAgeMs: Double?
        let `self`: WhatsAppSelf?
        let running: Bool
        let connected: Bool
        let lastConnectedAt: Double?
        let lastDisconnect: WhatsAppDisconnect?
        let reconnectAttempts: Int
        let lastMessageAt: Double?
        let lastEventAt: Double?
        let lastError: String?
    }

    struct TelegramBot: Codable, Sendable {
        let id: Int?
        let username: String?
    }

    struct TelegramWebhook: Codable, Sendable {
        let url: String?
        let hasCustomCert: Bool?
    }

    struct TelegramProbe: Codable, Sendable {
        let ok: Bool
        let status: Int?
        let error: String?
        let elapsedMs: Double?
        let bot: TelegramBot?
        let webhook: TelegramWebhook?
    }

    struct TelegramStatus: Codable, Sendable {
        let configured: Bool
        let tokenSource: String?
        let running: Bool
        let mode: String?
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastError: String?
        let probe: TelegramProbe?
        let lastProbeAt: Double?
    }

    struct DiscordBot: Codable, Sendable {
        let id: String?
        let username: String?
    }

    struct DiscordProbe: Codable, Sendable {
        let ok: Bool
        let status: Int?
        let error: String?
        let elapsedMs: Double?
        let bot: DiscordBot?
    }

    struct DiscordStatus: Codable, Sendable {
        let configured: Bool
        let tokenSource: String?
        let running: Bool
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastError: String?
        let probe: DiscordProbe?
        let lastProbeAt: Double?
    }

    struct GoogleChatProbe: Codable, Sendable {
        let ok: Bool
        let status: Int?
        let error: String?
        let elapsedMs: Double?
    }

    struct GoogleChatStatus: Codable, Sendable {
        let configured: Bool
        let credentialSource: String?
        let audienceType: String?
        let audience: String?
        let webhookPath: String?
        let webhookUrl: String?
        let running: Bool
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastError: String?
        let probe: GoogleChatProbe?
        let lastProbeAt: Double?
    }

    struct SignalProbe: Codable, Sendable {
        let ok: Bool
        let status: Int?
        let error: String?
        let elapsedMs: Double?
        let version: String?
    }

    struct SignalStatus: Codable, Sendable {
        let configured: Bool
        let baseUrl: String
        let running: Bool
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastError: String?
        let probe: SignalProbe?
        let lastProbeAt: Double?
    }

    struct IMessageProbe: Codable, Sendable {
        let ok: Bool
        let error: String?
    }

    struct IMessageStatus: Codable, Sendable {
        let configured: Bool
        let running: Bool
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastError: String?
        let cliPath: String?
        let dbPath: String?
        let probe: IMessageProbe?
        let lastProbeAt: Double?
    }

    struct ChannelAccountSnapshot: Codable, Sendable {
        let accountId: String
        let name: String?
        let enabled: Bool?
        let configured: Bool?
        let linked: Bool?
        let running: Bool?
        let connected: Bool?
        let reconnectAttempts: Int?
        let lastConnectedAt: Double?
        let lastError: String?
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastInboundAt: Double?
        let lastOutboundAt: Double?
        let lastProbeAt: Double?
        let mode: String?
        let dmPolicy: String?
        let allowFrom: [String]?
        let tokenSource: String?
        let botTokenSource: String?
        let appTokenSource: String?
        let baseUrl: String?
        let allowUnmentionedGroups: Bool?
        let cliPath: String?
        let dbPath: String?
        let port: Int?
    }

    struct ChannelUiMetaEntry: Codable, Sendable {
        let id: String
        let label: String
        let detailLabel: String
        let systemImage: String?
    }

    // MARK: - Snapshot fields

    let ts: Double
    let channelOrder: [String]
    let channelLabels: [String: String]
    let channelDetailLabels: [String: String]?
    let channelSystemImages: [String: String]?
    let channelMeta: [ChannelUiMetaEntry]?
    let channels: [String: AnyCodableValue]
    let channelAccounts: [String: [ChannelAccountSnapshot]]?
    let channelDefaultAccountId: [String: String]?

    /// Decode a specific channel's status to a typed struct.
    func decodeChannel<T: Decodable>(_ id: String, as type: T.Type) -> T? {
        guard let value = self.channels[id] else { return nil }
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}

/// Result of a WhatsApp login start request.
struct WhatsAppLoginStartResult: Codable, Sendable {
    let qrDataUrl: String?
    let message: String
}

/// Result of a WhatsApp login wait request.
struct WhatsAppLoginWaitResult: Codable, Sendable {
    let connected: Bool
    let message: String
}

/// Result of a channel logout request.
struct ChannelLogoutResult: Codable, Sendable {
    let channel: String?
    let accountId: String?
    let cleared: Bool
    let envToken: Bool?
}

/// Configuration snapshot from Gateway.
struct ConfigSnapshot: Codable, Sendable {
    struct Issue: Codable, Sendable {
        let path: String
        let message: String
    }

    let path: String?
    let exists: Bool?
    let raw: String?
    let hash: String?
    let parsed: AnyCodableValue?
    let valid: Bool?
    let config: [String: AnyCodableValue]?
    let issues: [Issue]?
}
