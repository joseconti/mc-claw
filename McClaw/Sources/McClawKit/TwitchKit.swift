import Foundation

/// Pure logic for Twitch EventSub API: parsing, URL building, formatting.
/// No network calls, no side effects — fully testable.
public enum TwitchKit {

    // MARK: - Models

    /// A Twitch EventSub WebSocket message.
    public struct WebSocketMessage: Codable, Sendable, Equatable {
        public let metadata: Metadata
        public let payload: WSPayload

        public init(metadata: Metadata, payload: WSPayload) {
            self.metadata = metadata
            self.payload = payload
        }
    }

    /// Metadata for a WebSocket message.
    public struct Metadata: Codable, Sendable, Equatable {
        public let messageId: String
        public let messageType: String
        public let messageTimestamp: String
        public let subscriptionType: String?
        public let subscriptionVersion: String?

        enum CodingKeys: String, CodingKey {
            case messageId = "message_id"
            case messageType = "message_type"
            case messageTimestamp = "message_timestamp"
            case subscriptionType = "subscription_type"
            case subscriptionVersion = "subscription_version"
        }

        public init(messageId: String, messageType: String, messageTimestamp: String, subscriptionType: String? = nil, subscriptionVersion: String? = nil) {
            self.messageId = messageId
            self.messageType = messageType
            self.messageTimestamp = messageTimestamp
            self.subscriptionType = subscriptionType
            self.subscriptionVersion = subscriptionVersion
        }
    }

    /// Payload of a WebSocket message.
    public struct WSPayload: Codable, Sendable, Equatable {
        public let session: Session?
        public let subscription: Subscription?
        public let event: ChatEvent?

        public init(session: Session? = nil, subscription: Subscription? = nil, event: ChatEvent? = nil) {
            self.session = session
            self.subscription = subscription
            self.event = event
        }
    }

    /// EventSub WebSocket session info (from session_welcome).
    public struct Session: Codable, Sendable, Equatable {
        public let id: String
        public let status: String
        public let connectedAt: String
        public let keepaliveTimeoutSeconds: Int?
        public let reconnectUrl: String?

        enum CodingKeys: String, CodingKey {
            case id, status
            case connectedAt = "connected_at"
            case keepaliveTimeoutSeconds = "keepalive_timeout_seconds"
            case reconnectUrl = "reconnect_url"
        }

        public init(id: String, status: String, connectedAt: String, keepaliveTimeoutSeconds: Int? = nil, reconnectUrl: String? = nil) {
            self.id = id
            self.status = status
            self.connectedAt = connectedAt
            self.keepaliveTimeoutSeconds = keepaliveTimeoutSeconds
            self.reconnectUrl = reconnectUrl
        }
    }

    /// An EventSub subscription.
    public struct Subscription: Codable, Sendable, Equatable {
        public let id: String
        public let type: String
        public let version: String
        public let status: String
        public let condition: [String: String]
        public let transport: Transport

        public init(id: String, type: String, version: String, status: String, condition: [String: String], transport: Transport) {
            self.id = id
            self.type = type
            self.version = version
            self.status = status
            self.condition = condition
            self.transport = transport
        }
    }

    /// Transport info for a subscription.
    public struct Transport: Codable, Sendable, Equatable {
        public let method: String
        public let sessionId: String?

        enum CodingKeys: String, CodingKey {
            case method
            case sessionId = "session_id"
        }

        public init(method: String, sessionId: String? = nil) {
            self.method = method
            self.sessionId = sessionId
        }
    }

    /// A channel.chat.message event.
    public struct ChatEvent: Codable, Sendable, Equatable {
        public let broadcasterUserId: String
        public let broadcasterUserLogin: String
        public let broadcasterUserName: String
        public let chatterUserId: String
        public let chatterUserLogin: String
        public let chatterUserName: String
        public let messageId: String
        public let message: ChatMessage

        enum CodingKeys: String, CodingKey {
            case broadcasterUserId = "broadcaster_user_id"
            case broadcasterUserLogin = "broadcaster_user_login"
            case broadcasterUserName = "broadcaster_user_name"
            case chatterUserId = "chatter_user_id"
            case chatterUserLogin = "chatter_user_login"
            case chatterUserName = "chatter_user_name"
            case messageId = "message_id"
            case message
        }

        public init(broadcasterUserId: String, broadcasterUserLogin: String, broadcasterUserName: String, chatterUserId: String, chatterUserLogin: String, chatterUserName: String, messageId: String, message: ChatMessage) {
            self.broadcasterUserId = broadcasterUserId
            self.broadcasterUserLogin = broadcasterUserLogin
            self.broadcasterUserName = broadcasterUserName
            self.chatterUserId = chatterUserId
            self.chatterUserLogin = chatterUserLogin
            self.chatterUserName = chatterUserName
            self.messageId = messageId
            self.message = message
        }
    }

    /// A chat message with text and optional fragments.
    public struct ChatMessage: Codable, Sendable, Equatable {
        public let text: String
        public let fragments: [Fragment]?

        public init(text: String, fragments: [Fragment]? = nil) {
            self.text = text
            self.fragments = fragments
        }
    }

    /// A message fragment (text, emote, cheermote, mention).
    public struct Fragment: Codable, Sendable, Equatable {
        public let type: String
        public let text: String
        public let cheermote: FragmentDetail?
        public let emote: FragmentDetail?
        public let mention: FragmentDetail?

        public init(type: String, text: String, cheermote: FragmentDetail? = nil, emote: FragmentDetail? = nil, mention: FragmentDetail? = nil) {
            self.type = type
            self.text = text
            self.cheermote = cheermote
            self.emote = emote
            self.mention = mention
        }
    }

    /// Detail for a fragment (cheermote, emote, or mention).
    public struct FragmentDetail: Codable, Sendable, Equatable {
        public let userId: String?
        public let userLogin: String?
        public let userName: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case userLogin = "user_login"
            case userName = "user_name"
        }

        public init(userId: String? = nil, userLogin: String? = nil, userName: String? = nil) {
            self.userId = userId
            self.userLogin = userLogin
            self.userName = userName
        }
    }

    /// Token validation response from Twitch OAuth.
    public struct TokenValidation: Codable, Sendable, Equatable {
        public let clientId: String
        public let login: String
        public let userId: String
        public let scopes: [String]
        public let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case login
            case userId = "user_id"
            case scopes
            case expiresIn = "expires_in"
        }

        public init(clientId: String, login: String, userId: String, scopes: [String], expiresIn: Int) {
            self.clientId = clientId
            self.login = login
            self.userId = userId
            self.scopes = scopes
            self.expiresIn = expiresIn
        }
    }

    /// A Twitch user from the Helix /users endpoint.
    public struct TwitchUser: Codable, Sendable, Equatable {
        public let id: String
        public let login: String
        public let displayName: String
        public let broadcasterType: String

        enum CodingKeys: String, CodingKey {
            case id, login
            case displayName = "display_name"
            case broadcasterType = "broadcaster_type"
        }

        public init(id: String, login: String, displayName: String, broadcasterType: String) {
            self.id = id
            self.login = login
            self.displayName = displayName
            self.broadcasterType = broadcasterType
        }
    }

    // MARK: - Message Types

    /// WebSocket message type: session_welcome.
    public static let sessionWelcome = "session_welcome"
    /// WebSocket message type: session_keepalive.
    public static let sessionKeepalive = "session_keepalive"
    /// WebSocket message type: notification.
    public static let notification = "notification"
    /// WebSocket message type: session_reconnect.
    public static let sessionReconnect = "session_reconnect"
    /// WebSocket message type: revocation.
    public static let revocation = "revocation"

    // MARK: - Subscription Types

    /// EventSub subscription type for chat messages.
    public static let channelChatMessage = "channel.chat.message"

    // MARK: - URL Building

    private static let eventSubWSBase = "wss://eventsub.wss.twitch.tv/ws"
    private static let helixBase = "https://api.twitch.tv/helix"
    private static let oauthBase = "https://id.twitch.tv/oauth2"

    /// EventSub WebSocket URL.
    public static func eventSubWSURL() -> URL {
        URL(string: eventSubWSBase)!
    }

    /// Build a Helix API URL with path and optional query params.
    public static func helixURL(path: String, params: [String: String] = [:]) -> URL? {
        var components = URLComponents(string: "\(helixBase)\(path)")
        if !params.isEmpty {
            components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components?.url
    }

    /// URL for EventSub subscriptions endpoint.
    public static func subscriptionsURL() -> URL? {
        helixURL(path: "/eventsub/subscriptions")
    }

    /// URL for sending chat messages.
    public static func chatMessagesURL() -> URL? {
        helixURL(path: "/chat/messages")
    }

    /// URL for getting user info by login.
    public static func usersURL(login: String? = nil) -> URL? {
        if let login {
            return helixURL(path: "/users", params: ["login": login])
        }
        return helixURL(path: "/users")
    }

    /// URL for validating an OAuth token.
    public static func validateTokenURL() -> URL? {
        URL(string: "\(oauthBase)/validate")
    }

    // MARK: - Request Body Building

    /// Build JSON body for creating an EventSub subscription.
    public static func subscribeBody(type: String, version: String, condition: [String: String], sessionId: String) -> Data? {
        let body: [String: Any] = [
            "type": type,
            "version": version,
            "condition": condition,
            "transport": [
                "method": "websocket",
                "session_id": sessionId,
            ],
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// Build JSON body for subscribing to channel.chat.message events.
    public static func chatMessageSubscribeBody(broadcasterUserId: String, userId: String, sessionId: String) -> Data? {
        let condition: [String: String] = [
            "broadcaster_user_id": broadcasterUserId,
            "user_id": userId,
        ]
        return subscribeBody(type: channelChatMessage, version: "1", condition: condition, sessionId: sessionId)
    }

    /// Build JSON body for sending a chat message.
    public static func sendChatBody(broadcasterId: String, senderId: String, message: String) -> Data? {
        let body: [String: Any] = [
            "broadcaster_id": broadcasterId,
            "sender_id": senderId,
            "message": message,
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Auth Header Building

    /// Build authorization headers for Twitch API requests.
    /// Includes Bearer token and Client-Id.
    public static func authHeaders(token: String, clientId: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Client-Id": clientId,
            "Content-Type": "application/json",
        ]
    }

    // MARK: - Parsing

    /// Parse a WebSocket message from raw data.
    public static func parseWebSocketMessage(data: Data) -> WebSocketMessage? {
        let decoder = JSONDecoder()
        return try? decoder.decode(WebSocketMessage.self, from: data)
    }

    /// Extract the session ID from a session_welcome message.
    public static func parseSessionId(from message: WebSocketMessage) -> String? {
        guard message.metadata.messageType == sessionWelcome else { return nil }
        return message.payload.session?.id
    }

    /// Extract the chat event from a notification message.
    public static func parseChatEvent(from message: WebSocketMessage) -> ChatEvent? {
        guard message.metadata.messageType == notification else { return nil }
        return message.payload.event
    }

    /// Parse a token validation response.
    public static func parseTokenValidation(data: Data) -> TokenValidation? {
        let decoder = JSONDecoder()
        return try? decoder.decode(TokenValidation.self, from: data)
    }

    /// Parse a user from the Helix /users endpoint (data array wrapper).
    public static func parseUser(data: Data) -> TwitchUser? {
        struct UsersResponse: Codable {
            let data: [TwitchUser]
        }
        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(UsersResponse.self, from: data),
              let user = response.data.first else {
            return nil
        }
        return user
    }

    // MARK: - Event Filtering

    /// Check if a chat event should be processed (not from the bot itself).
    public static func shouldProcess(event: ChatEvent, botUserId: String) -> Bool {
        event.chatterUserId != botUserId
    }

    /// Extract text content from a chat event.
    public static func extractText(from event: ChatEvent) -> String? {
        let text = event.message.text
        guard !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Formatting

    /// Truncate a message for Twitch chat (max 500 chars by default).
    public static func truncateForTwitch(_ text: String, maxLength: Int = 500) -> String {
        guard text.count > maxLength else { return text }
        let suffix = "... (truncated)"
        return String(text.prefix(maxLength - suffix.count)) + suffix
    }

    // MARK: - Validation

    /// Basic validation that a string looks like a Twitch OAuth token.
    /// Non-empty with reasonable length.
    public static func isValidToken(_ token: String) -> Bool {
        !token.isEmpty && token.count >= 10 && token.count <= 200
    }

    /// Basic validation that a string looks like a Twitch Client-ID.
    /// Typically 30 alphanumeric characters.
    public static func isValidClientId(_ clientId: String) -> Bool {
        guard !clientId.isEmpty else { return false }
        guard clientId.count >= 10 && clientId.count <= 50 else { return false }
        return clientId.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
