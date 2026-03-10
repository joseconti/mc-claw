import Foundation

/// Pure logic for Slack Socket Mode and Web API: parsing, URL building, formatting.
/// No network calls, no side effects — fully testable.
public enum SlackKit {

    // MARK: - Socket Mode Models

    /// A Socket Mode envelope received via WebSocket.
    /// Slack wraps all events in an envelope that must be acknowledged.
    public struct SocketEnvelope: Codable, Sendable {
        public let envelopeId: String?
        public let type: String
        public let payload: Payload?
        public let acceptsResponsePayload: Bool?
        public let retryAttempt: Int?
        public let retryReason: String?

        enum CodingKeys: String, CodingKey {
            case envelopeId = "envelope_id"
            case type, payload
            case acceptsResponsePayload = "accepts_response_payload"
            case retryAttempt = "retry_attempt"
            case retryReason = "retry_reason"
        }

        public init(
            envelopeId: String? = nil,
            type: String,
            payload: Payload? = nil,
            acceptsResponsePayload: Bool? = nil,
            retryAttempt: Int? = nil,
            retryReason: String? = nil
        ) {
            self.envelopeId = envelopeId
            self.type = type
            self.payload = payload
            self.acceptsResponsePayload = acceptsResponsePayload
            self.retryAttempt = retryAttempt
            self.retryReason = retryReason
        }
    }

    /// The payload inside a Socket Mode envelope.
    public struct Payload: Codable, Sendable {
        public let event: SlackEvent?
        public let type: String?

        public init(event: SlackEvent? = nil, type: String? = nil) {
            self.event = event
            self.type = type
        }
    }

    /// A Slack event (message, app_mention, etc.).
    public struct SlackEvent: Codable, Sendable, Equatable {
        public let type: String
        public let subtype: String?
        public let channel: String?
        public let user: String?
        public let text: String?
        public let ts: String?
        public let threadTs: String?
        public let botId: String?
        public let channelType: String?

        enum CodingKeys: String, CodingKey {
            case type, subtype, channel, user, text, ts
            case threadTs = "thread_ts"
            case botId = "bot_id"
            case channelType = "channel_type"
        }

        public init(
            type: String,
            subtype: String? = nil,
            channel: String? = nil,
            user: String? = nil,
            text: String? = nil,
            ts: String? = nil,
            threadTs: String? = nil,
            botId: String? = nil,
            channelType: String? = nil
        ) {
            self.type = type
            self.subtype = subtype
            self.channel = channel
            self.user = user
            self.text = text
            self.ts = ts
            self.threadTs = threadTs
            self.botId = botId
            self.channelType = channelType
        }

        /// Whether this is a user message (not from a bot, not a subtype).
        public var isUserMessage: Bool {
            type == "message" && subtype == nil && botId == nil && user != nil
        }

        /// Whether this is a direct message.
        public var isDirectMessage: Bool {
            channelType == "im"
        }

        /// Whether this is an app_mention event.
        public var isAppMention: Bool {
            type == "app_mention"
        }
    }

    /// Bot identity from auth.test response.
    public struct BotIdentity: Sendable, Equatable {
        public let userId: String
        public let botId: String?
        public let teamId: String
        public let team: String?
        public let user: String?

        public init(userId: String, botId: String? = nil, teamId: String, team: String? = nil, user: String? = nil) {
            self.userId = userId
            self.botId = botId
            self.teamId = teamId
            self.team = team
            self.user = user
        }

        public var displayName: String {
            if let user { return user }
            return "Bot \(userId)"
        }
    }

    // MARK: - Socket Mode Envelope Types

    /// Known Socket Mode envelope types.
    public static let typeHello = "hello"
    public static let typeEventsApi = "events_api"
    public static let typeSlashCommands = "slash_commands"
    public static let typeInteractive = "interactive"
    public static let typeDisconnect = "disconnect"

    // MARK: - Parsing

    /// Parse a Socket Mode envelope from WebSocket text.
    public static func parseEnvelope(data: Data) -> SocketEnvelope? {
        try? JSONDecoder().decode(SocketEnvelope.self, from: data)
    }

    /// Parse auth.test response to extract bot identity.
    public static func parseBotIdentity(data: Data) -> BotIdentity? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ok"] as? Bool == true else { return nil }

        guard let userId = json["user_id"] as? String,
              let teamId = json["team_id"] as? String else { return nil }

        return BotIdentity(
            userId: userId,
            botId: json["bot_id"] as? String,
            teamId: teamId,
            team: json["team"] as? String,
            user: json["user"] as? String
        )
    }

    // MARK: - Acknowledge

    /// Build the acknowledge JSON for a Socket Mode envelope.
    /// Slack requires an ack within 3 seconds of receiving an envelope.
    public static func acknowledgeBody(envelopeId: String) -> Data? {
        let body: [String: Any] = ["envelope_id": envelopeId]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Web API URL Building

    private static let webAPIBase = "https://slack.com/api"

    /// Build URL for Slack Web API method.
    public static func webAPIURL(method: String) -> URL? {
        URL(string: "\(webAPIBase)/\(method)")
    }

    /// Build Socket Mode connect URL.
    /// Uses apps.connections.open to get the WebSocket URL.
    public static func connectURL() -> URL? {
        URL(string: "\(webAPIBase)/apps.connections.open")
    }

    // MARK: - Request Body Building

    /// Build JSON body for chat.postMessage.
    public static func postMessageBody(channel: String, text: String, threadTs: String? = nil) -> Data? {
        var body: [String: Any] = [
            "channel": channel,
            "text": text,
        ]
        if let threadTs {
            body["thread_ts"] = threadTs
        }
        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Socket Mode WebSocket URL Parsing

    /// Parse the WebSocket URL from apps.connections.open response.
    public static func parseWebSocketURL(data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ok"] as? Bool == true,
              let urlString = json["url"] as? String else { return nil }
        return URL(string: urlString)
    }

    // MARK: - Event Filtering

    /// Check if an event should be processed (user message or app_mention, not bot).
    public static func shouldProcess(event: SlackEvent) -> Bool {
        if event.isUserMessage { return true }
        if event.isAppMention { return true }
        return false
    }

    /// Extract the text from an event, stripping bot mentions.
    /// Slack mentions look like `<@U1234567> hello` — we strip the mention prefix.
    public static func extractText(from event: SlackEvent, botUserId: String?) -> String? {
        guard var text = event.text, !text.isEmpty else { return nil }

        // Strip bot mention if present: <@U1234567>
        if let botId = botUserId {
            let mentionPattern = "<@\(botId)>"
            text = text.replacingOccurrences(of: mentionPattern, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text.isEmpty ? nil : text
    }

    // MARK: - Formatting

    /// Truncate text for Slack (max 40000 chars for messages).
    public static func truncateForSlack(_ text: String, maxLength: Int = 4000) -> String {
        guard text.count > maxLength else { return text }
        let suffix = "\n\n… (truncated)"
        return String(text.prefix(maxLength - suffix.count)) + suffix
    }

    /// Escape special mrkdwn characters for Slack.
    public static func escapeSlackMrkdwn(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Token Validation

    /// Validate that a string looks like a Slack bot token (xoxb-).
    public static func isValidBotToken(_ token: String) -> Bool {
        token.hasPrefix("xoxb-") && token.count > 20
    }

    /// Validate that a string looks like a Slack app-level token (xapp-).
    public static func isValidAppToken(_ token: String) -> Bool {
        token.hasPrefix("xapp-") && token.count > 20
    }
}
