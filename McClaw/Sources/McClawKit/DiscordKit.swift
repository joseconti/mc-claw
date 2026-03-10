import Foundation

/// Pure logic for Discord Gateway and REST API v10: parsing, URL building, formatting.
/// No network calls, no side effects — fully testable.
public enum DiscordKit {

    // MARK: - Gateway Models

    /// A Discord Gateway payload (sent and received over WebSocket).
    public struct GatewayPayload: Codable, Sendable {
        public let op: Int
        public let d: AnyCodableValue?
        public let s: Int?
        public let t: String?

        public init(op: Int, d: AnyCodableValue? = nil, s: Int? = nil, t: String? = nil) {
            self.op = op
            self.d = d
            self.s = s
            self.t = t
        }
    }

    /// Type-erased JSON value for Gateway payload `d` field.
    public enum AnyCodableValue: Codable, Sendable, Equatable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case dictionary([String: AnyCodableValue])
        case array([AnyCodableValue])
        case null

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let v = try? container.decode(Bool.self) {
                self = .bool(v)
            } else if let v = try? container.decode(Int.self) {
                self = .int(v)
            } else if let v = try? container.decode(Double.self) {
                self = .double(v)
            } else if let v = try? container.decode(String.self) {
                self = .string(v)
            } else if let v = try? container.decode([String: AnyCodableValue].self) {
                self = .dictionary(v)
            } else if let v = try? container.decode([AnyCodableValue].self) {
                self = .array(v)
            } else {
                self = .null
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let v): try container.encode(v)
            case .int(let v): try container.encode(v)
            case .double(let v): try container.encode(v)
            case .bool(let v): try container.encode(v)
            case .dictionary(let v): try container.encode(v)
            case .array(let v): try container.encode(v)
            case .null: try container.encodeNil()
            }
        }

        /// Access a dictionary value by key.
        public subscript(key: String) -> AnyCodableValue? {
            guard case .dictionary(let dict) = self else { return nil }
            return dict[key]
        }

        /// Extract as String.
        public var stringValue: String? {
            guard case .string(let v) = self else { return nil }
            return v
        }

        /// Extract as Int.
        public var intValue: Int? {
            switch self {
            case .int(let v): return v
            case .double(let v): return Int(v)
            default: return nil
            }
        }

        /// Extract as Bool.
        public var boolValue: Bool? {
            guard case .bool(let v) = self else { return nil }
            return v
        }
    }

    /// Known Gateway event types.
    public enum GatewayEvent {
        case hello(heartbeatInterval: Int)
        case ready(ReadyData)
        case resumed
        case messageCreate(Message)
        case heartbeatRequest
        case heartbeatAck
        case reconnect
        case invalidSession(resumable: Bool)
        case unknown(op: Int, t: String?)
    }

    /// Data received with the Hello (op 10) event.
    public struct HelloData: Codable, Sendable, Equatable {
        public let heartbeatInterval: Int

        enum CodingKeys: String, CodingKey {
            case heartbeatInterval = "heartbeat_interval"
        }

        public init(heartbeatInterval: Int) {
            self.heartbeatInterval = heartbeatInterval
        }
    }

    /// Data sent with the Identify (op 2) event.
    public struct IdentifyData: Codable, Sendable, Equatable {
        public let token: String
        public let intents: Int
        public let properties: IdentifyProperties

        public init(token: String, intents: Int, properties: IdentifyProperties = .default) {
            self.token = token
            self.intents = intents
            self.properties = properties
        }
    }

    /// Connection properties for the Identify payload.
    public struct IdentifyProperties: Codable, Sendable, Equatable {
        public let os: String
        public let browser: String
        public let device: String

        enum CodingKeys: String, CodingKey {
            case os = "os"
            case browser = "browser"
            case device = "device"
        }

        public init(os: String = "macos", browser: String = "McClaw", device: String = "McClaw") {
            self.os = os
            self.browser = browser
            self.device = device
        }

        public static let `default` = IdentifyProperties()
    }

    /// Data received with the Ready (op 0, t: READY) event.
    public struct ReadyData: Codable, Sendable, Equatable {
        public let v: Int
        public let sessionId: String
        public let user: User
        public let guilds: [UnavailableGuild]
        public let resumeGatewayUrl: String?

        enum CodingKeys: String, CodingKey {
            case v
            case sessionId = "session_id"
            case user, guilds
            case resumeGatewayUrl = "resume_gateway_url"
        }

        public init(v: Int, sessionId: String, user: User, guilds: [UnavailableGuild] = [], resumeGatewayUrl: String? = nil) {
            self.v = v
            self.sessionId = sessionId
            self.user = user
            self.guilds = guilds
            self.resumeGatewayUrl = resumeGatewayUrl
        }
    }

    /// An unavailable guild received in the Ready event.
    public struct UnavailableGuild: Codable, Sendable, Equatable {
        public let id: String
        public let unavailable: Bool?

        public init(id: String, unavailable: Bool? = true) {
            self.id = id
            self.unavailable = unavailable
        }
    }

    // MARK: - REST Models

    /// A Discord user.
    public struct User: Codable, Sendable, Equatable {
        public let id: String
        public let username: String
        public let discriminator: String?
        public let bot: Bool?
        public let globalName: String?

        enum CodingKeys: String, CodingKey {
            case id, username, discriminator, bot
            case globalName = "global_name"
        }

        public init(id: String, username: String, discriminator: String? = nil, bot: Bool? = nil, globalName: String? = nil) {
            self.id = id
            self.username = username
            self.discriminator = discriminator
            self.bot = bot
            self.globalName = globalName
        }

        /// Display name: global name, username, or fallback.
        public var displayName: String {
            if let globalName, !globalName.isEmpty { return globalName }
            return username
        }

        /// Whether this user is a bot.
        public var isBot: Bool {
            bot ?? false
        }
    }

    /// A Discord channel.
    public struct Channel: Codable, Sendable, Equatable {
        public let id: String
        public let type: Int
        public let guildId: String?
        public let name: String?

        enum CodingKeys: String, CodingKey {
            case id, type, name
            case guildId = "guild_id"
        }

        public init(id: String, type: Int, guildId: String? = nil, name: String? = nil) {
            self.id = id
            self.type = type
            self.guildId = guildId
            self.name = name
        }

        /// Channel type constants.
        public static let typeGuildText = 0
        public static let typeDM = 1
        public static let typeGuildVoice = 2
        public static let typeGroupDM = 3
        public static let typeGuildCategory = 4

        /// Whether this is a direct message channel.
        public var isDM: Bool {
            type == Channel.typeDM || type == Channel.typeGroupDM
        }

        /// Display name for the channel.
        public var displayName: String {
            if let name, !name.isEmpty { return "#\(name)" }
            return "Channel \(id)"
        }
    }

    /// A Discord message.
    public struct Message: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let channelId: String
        public let author: User
        public let content: String
        public let timestamp: String
        public let guildId: String?
        public let mentionEveryone: Bool?
        public let mentions: [User]?

        enum CodingKeys: String, CodingKey {
            case id, author, content, timestamp, mentions
            case channelId = "channel_id"
            case guildId = "guild_id"
            case mentionEveryone = "mention_everyone"
        }

        public init(
            id: String,
            channelId: String,
            author: User,
            content: String,
            timestamp: String,
            guildId: String? = nil,
            mentionEveryone: Bool? = nil,
            mentions: [User]? = nil
        ) {
            self.id = id
            self.channelId = channelId
            self.author = author
            self.content = content
            self.timestamp = timestamp
            self.guildId = guildId
            self.mentionEveryone = mentionEveryone
            self.mentions = mentions
        }

        /// Whether the message author is a bot.
        public var isFromBot: Bool {
            author.isBot
        }
    }

    /// A Discord guild (server).
    public struct Guild: Codable, Sendable, Equatable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    // MARK: - Gateway Opcodes

    /// Gateway opcode: Dispatch (receive).
    public static let opcodeDispatch = 0
    /// Gateway opcode: Heartbeat (send/receive).
    public static let opcodeHeartbeat = 1
    /// Gateway opcode: Identify (send).
    public static let opcodeIdentify = 2
    /// Gateway opcode: Resume (send).
    public static let opcodeResume = 6
    /// Gateway opcode: Reconnect (receive).
    public static let opcodeReconnect = 7
    /// Gateway opcode: Invalid Session (receive).
    public static let opcodeInvalidSession = 9
    /// Gateway opcode: Hello (receive).
    public static let opcodeHello = 10
    /// Gateway opcode: Heartbeat ACK (receive).
    public static let opcodeHeartbeatAck = 11

    // MARK: - Gateway Event Names

    /// Event name for READY dispatch.
    public static let eventReady = "READY"
    /// Event name for RESUMED dispatch.
    public static let eventResumed = "RESUMED"
    /// Event name for MESSAGE_CREATE dispatch.
    public static let eventMessageCreate = "MESSAGE_CREATE"

    // MARK: - Gateway Intents

    /// Default intents: GUILDS (1<<0) | GUILD_MESSAGES (1<<9) | DIRECT_MESSAGES (1<<12) | MESSAGE_CONTENT (1<<15).
    public static let defaultIntents: Int = 33281

    /// Individual intent flags.
    public static let intentGuilds = 1 << 0
    public static let intentGuildMessages = 1 << 9
    public static let intentDirectMessages = 1 << 12
    public static let intentMessageContent = 1 << 15

    // MARK: - URL Building

    private static let gatewayBase = "wss://gateway.discord.gg"
    private static let restBase = "https://discord.com/api/v10"

    /// Build the Gateway WebSocket URL.
    public static func gatewayURL() -> URL? {
        URL(string: "\(gatewayBase)/?v=10&encoding=json")
    }

    /// Build a REST API URL for a given path.
    public static func restURL(path: String) -> URL? {
        URL(string: "\(restBase)\(path)")
    }

    /// Build the URL to send/get messages in a channel.
    public static func channelMessagesURL(channelId: String) -> URL? {
        restURL(path: "/channels/\(channelId)/messages")
    }

    /// Build the URL to get the current bot user.
    public static func currentUserURL() -> URL? {
        restURL(path: "/users/@me")
    }

    // MARK: - Request Body Building

    /// Build the Identify payload (op 2) as JSON data.
    public static func identifyPayload(token: String, intents: Int = defaultIntents) -> Data? {
        let identify = IdentifyData(token: token, intents: intents)
        let payload: [String: Any] = [
            "op": opcodeIdentify,
            "d": [
                "token": identify.token,
                "intents": identify.intents,
                "properties": [
                    "os": identify.properties.os,
                    "browser": identify.properties.browser,
                    "device": identify.properties.device,
                ],
            ] as [String: Any],
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    /// Build a Heartbeat payload (op 1) as JSON data.
    public static func heartbeatPayload(sequence: Int?) -> Data? {
        var payload: [String: Any] = ["op": opcodeHeartbeat]
        if let seq = sequence {
            payload["d"] = seq
        } else {
            payload["d"] = NSNull()
        }
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    /// Build JSON body for sending a message via REST POST /channels/{id}/messages.
    public static func sendMessageBody(content: String) -> Data? {
        let body: [String: Any] = ["content": content]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Parsing

    /// Parse a raw Gateway payload from WebSocket data.
    public static func parseGatewayPayload(data: Data) -> GatewayPayload? {
        try? JSONDecoder().decode(GatewayPayload.self, from: data)
    }

    /// Parse Hello data from a Gateway payload, returning the heartbeat interval in milliseconds.
    public static func parseHello(payload: GatewayPayload) -> HelloData? {
        guard payload.op == opcodeHello,
              let d = payload.d,
              let interval = d["heartbeat_interval"]?.intValue else { return nil }
        return HelloData(heartbeatInterval: interval)
    }

    /// Parse Ready data from a Gateway payload.
    public static func parseReady(payload: GatewayPayload) -> ReadyData? {
        guard payload.op == opcodeDispatch, payload.t == eventReady,
              let d = payload.d else { return nil }

        // Re-encode d and decode as ReadyData
        guard let encoded = try? JSONEncoder().encode(d),
              let ready = try? JSONDecoder().decode(ReadyData.self, from: encoded) else { return nil }
        return ready
    }

    /// Parse a MESSAGE_CREATE event from a Gateway payload.
    public static func parseMessageCreate(payload: GatewayPayload) -> Message? {
        guard payload.op == opcodeDispatch, payload.t == eventMessageCreate,
              let d = payload.d else { return nil }

        // Re-encode d and decode as Message
        guard let encoded = try? JSONEncoder().encode(d),
              let message = try? JSONDecoder().decode(Message.self, from: encoded) else { return nil }
        return message
    }

    /// Parse a User from REST API response data.
    public static func parseUser(data: Data) -> User? {
        try? JSONDecoder().decode(User.self, from: data)
    }

    /// Classify a raw Gateway payload into a typed event.
    public static func classifyPayload(_ payload: GatewayPayload) -> GatewayEvent {
        switch payload.op {
        case opcodeHello:
            if let hello = parseHello(payload: payload) {
                return .hello(heartbeatInterval: hello.heartbeatInterval)
            }
            return .unknown(op: payload.op, t: payload.t)

        case opcodeHeartbeat:
            return .heartbeatRequest

        case opcodeHeartbeatAck:
            return .heartbeatAck

        case opcodeReconnect:
            return .reconnect

        case opcodeInvalidSession:
            let resumable = payload.d?.boolValue ?? false
            return .invalidSession(resumable: resumable)

        case opcodeDispatch:
            switch payload.t {
            case eventReady:
                if let ready = parseReady(payload: payload) {
                    return .ready(ready)
                }
            case eventResumed:
                return .resumed
            case eventMessageCreate:
                if let msg = parseMessageCreate(payload: payload) {
                    return .messageCreate(msg)
                }
            default:
                break
            }
            return .unknown(op: payload.op, t: payload.t)

        default:
            return .unknown(op: payload.op, t: payload.t)
        }
    }

    // MARK: - Event Filtering

    /// Check if a message should be processed (not from a bot).
    public static func shouldProcess(message: Message, botUserId: String?) -> Bool {
        // Ignore messages from bots
        guard !message.isFromBot else { return false }
        // Ignore empty messages
        guard !message.content.isEmpty else { return false }
        // If we know our bot user ID, ignore messages from ourselves
        if let botId = botUserId, message.author.id == botId { return false }
        return true
    }

    /// Extract text from a message, stripping bot mention prefix.
    /// Discord bot mentions look like `<@BOT_ID>` in message content.
    public static func extractText(from message: Message, botUserId: String?) -> String? {
        var text = message.content

        // Strip bot mention if present: <@BOT_ID>
        if let botId = botUserId {
            let mentionPattern = "<@\(botId)>"
            text = text.replacingOccurrences(of: mentionPattern, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Also handle nickname mention: <@!BOT_ID>
            let nickMentionPattern = "<@!\(botId)>"
            text = text.replacingOccurrences(of: nickMentionPattern, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text.isEmpty ? nil : text
    }

    /// Check if a message mentions the bot.
    public static func isMentioned(in message: Message, botUserId: String) -> Bool {
        // Check mentions array
        if let mentions = message.mentions, mentions.contains(where: { $0.id == botUserId }) {
            return true
        }
        // Fallback: check content for mention pattern
        return message.content.contains("<@\(botUserId)>") || message.content.contains("<@!\(botUserId)>")
    }

    // MARK: - Formatting

    /// Truncate text for Discord (max 2000 chars for messages).
    public static func truncateForDiscord(_ text: String, maxLength: Int = 2000) -> String {
        guard text.count > maxLength else { return text }
        let suffix = "\n\n… (truncated)"
        return String(text.prefix(maxLength - suffix.count)) + suffix
    }

    /// Escape special Discord markdown characters.
    public static func escapeDiscordMarkdown(_ text: String) -> String {
        let specialChars: Set<Character> = ["*", "_", "~", "`", "|", ">", "[", "]", "(", ")"]
        return String(text.flatMap { char -> [Character] in
            if specialChars.contains(char) {
                return ["\\", char]
            }
            return [char]
        })
    }

    /// Format a user mention string.
    public static func formatUserMention(_ userId: String) -> String {
        "<@\(userId)>"
    }

    /// Format a channel mention string.
    public static func formatChannelMention(_ channelId: String) -> String {
        "<#\(channelId)>"
    }

    // MARK: - Token Validation

    /// Basic validation that a string looks like a Discord bot token.
    /// Discord tokens are base64-like strings, typically 59+ characters with dots separating segments.
    public static func isValidBotToken(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }
        guard token.count >= 50 else { return false }
        // Each part should be non-empty and contain base64-like characters
        for part in parts {
            guard !part.isEmpty else { return false }
        }
        return true
    }
}
