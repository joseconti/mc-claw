import Foundation

/// Pure logic for Mattermost REST API v4 and WebSocket: parsing, URL building, formatting.
/// No network calls, no side effects — fully testable.
public enum MattermostKit {

    // MARK: - Models

    /// A Mattermost WebSocket event.
    public struct WebSocketEvent: Codable, Sendable, Equatable {
        public let event: String
        public let data: EventData?
        public let broadcast: Broadcast?
        public let seq: Int?

        public init(event: String, data: EventData? = nil, broadcast: Broadcast? = nil, seq: Int? = nil) {
            self.event = event
            self.data = data
            self.broadcast = broadcast
            self.seq = seq
        }
    }

    /// Event data payload from a WebSocket event.
    /// The `post` field is a JSON string that must be parsed separately.
    public struct EventData: Codable, Sendable, Equatable {
        public let post: String?
        public let channelId: String?
        public let channelDisplayName: String?
        public let channelType: String?
        public let senderName: String?
        public let teamId: String?
        public let userId: String?

        enum CodingKeys: String, CodingKey {
            case post
            case channelId = "channel_id"
            case channelDisplayName = "channel_display_name"
            case channelType = "channel_type"
            case senderName = "sender_name"
            case teamId = "team_id"
            case userId = "user_id"
        }

        public init(
            post: String? = nil,
            channelId: String? = nil,
            channelDisplayName: String? = nil,
            channelType: String? = nil,
            senderName: String? = nil,
            teamId: String? = nil,
            userId: String? = nil
        ) {
            self.post = post
            self.channelId = channelId
            self.channelDisplayName = channelDisplayName
            self.channelType = channelType
            self.senderName = senderName
            self.teamId = teamId
            self.userId = userId
        }
    }

    /// Broadcast information indicating which users/channels/teams should receive the event.
    public struct Broadcast: Codable, Sendable, Equatable {
        public let channelId: String?
        public let teamId: String?
        public let userId: String?
        public let omitUsers: [String: Bool]?

        enum CodingKeys: String, CodingKey {
            case channelId = "channel_id"
            case teamId = "team_id"
            case userId = "user_id"
            case omitUsers = "omit_users"
        }

        public init(channelId: String? = nil, teamId: String? = nil, userId: String? = nil, omitUsers: [String: Bool]? = nil) {
            self.channelId = channelId
            self.teamId = teamId
            self.userId = userId
            self.omitUsers = omitUsers
        }
    }

    /// A Mattermost post (message).
    public struct Post: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let channelId: String
        public let userId: String
        public let rootId: String?
        public let message: String
        public let createAt: Int64
        public let type: String?

        enum CodingKeys: String, CodingKey {
            case id
            case channelId = "channel_id"
            case userId = "user_id"
            case rootId = "root_id"
            case message
            case createAt = "create_at"
            case type
        }

        public init(
            id: String,
            channelId: String,
            userId: String,
            rootId: String? = nil,
            message: String,
            createAt: Int64,
            type: String? = nil
        ) {
            self.id = id
            self.channelId = channelId
            self.userId = userId
            self.rootId = rootId
            self.message = message
            self.createAt = createAt
            self.type = type
        }

        /// The creation date as a `Date` value.
        public var dateValue: Date {
            Date(timeIntervalSince1970: TimeInterval(createAt) / 1000.0)
        }

        /// Whether this post is a reply in a thread.
        public var isReply: Bool {
            if let rootId, !rootId.isEmpty { return true }
            return false
        }
    }

    /// A Mattermost user.
    public struct User: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let username: String
        public let firstName: String?
        public let lastName: String?
        public let nickname: String?
        public let email: String?

        enum CodingKeys: String, CodingKey {
            case id, username
            case firstName = "first_name"
            case lastName = "last_name"
            case nickname, email
        }

        public init(
            id: String,
            username: String,
            firstName: String? = nil,
            lastName: String? = nil,
            nickname: String? = nil,
            email: String? = nil
        ) {
            self.id = id
            self.username = username
            self.firstName = firstName
            self.lastName = lastName
            self.nickname = nickname
            self.email = email
        }

        public var displayName: String {
            if let nickname, !nickname.isEmpty { return nickname }
            if let first = firstName, !first.isEmpty {
                if let last = lastName, !last.isEmpty { return "\(first) \(last)" }
                return first
            }
            return username
        }
    }

    /// A Mattermost channel.
    public struct Channel: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let type: String
        public let displayName: String
        public let name: String
        public let teamId: String?

        enum CodingKeys: String, CodingKey {
            case id, type
            case displayName = "display_name"
            case name
            case teamId = "team_id"
        }

        public init(id: String, type: String, displayName: String, name: String, teamId: String? = nil) {
            self.id = id
            self.type = type
            self.displayName = displayName
            self.name = name
            self.teamId = teamId
        }

        /// Whether this is a direct message channel.
        public var isDirectMessage: Bool {
            type == "D"
        }

        /// Whether this is a group message channel.
        public var isGroupMessage: Bool {
            type == "G"
        }
    }

    /// A Mattermost team.
    public struct Team: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let displayName: String

        enum CodingKeys: String, CodingKey {
            case id, name
            case displayName = "display_name"
        }

        public init(id: String, name: String, displayName: String) {
            self.id = id
            self.name = name
            self.displayName = displayName
        }
    }

    // MARK: - WebSocket Event Types

    /// The hello event sent when the WebSocket connection is established.
    public static let eventHello = "hello"
    /// A new post was created.
    public static let eventPosted = "posted"
    /// An existing post was edited.
    public static let eventPostEdited = "post_edited"
    /// A post was deleted.
    public static let eventPostDeleted = "post_deleted"
    /// A user is typing in a channel.
    public static let eventTyping = "typing"
    /// A user's status changed.
    public static let eventStatusChange = "status_change"

    // MARK: - URL Building

    /// Build the WebSocket URL from a Mattermost server URL.
    /// Converts `http(s)://` to `ws(s)://` and appends `/api/v4/websocket`.
    public static func webSocketURL(serverURL: String) -> URL? {
        let trimmed = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var wsURL = trimmed
        if wsURL.hasPrefix("https://") {
            wsURL = "wss://" + wsURL.dropFirst("https://".count)
        } else if wsURL.hasPrefix("http://") {
            wsURL = "ws://" + wsURL.dropFirst("http://".count)
        } else {
            return nil
        }
        return URL(string: wsURL + "/api/v4/websocket")
    }

    /// Build a REST API URL from a server URL and path.
    public static func restURL(serverURL: String, path: String) -> URL? {
        let trimmed = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: trimmed + cleanPath)
    }

    /// Build the posts endpoint URL.
    public static func postsURL(serverURL: String) -> URL? {
        restURL(serverURL: serverURL, path: "/api/v4/posts")
    }

    /// Build a users endpoint URL (e.g., `/api/v4/users/me`).
    public static func usersURL(serverURL: String, path: String = "/api/v4/users/me") -> URL? {
        restURL(serverURL: serverURL, path: path)
    }

    // MARK: - Request Body Building

    /// Build the WebSocket authentication challenge message.
    public static func authChallengeBody(token: String) -> Data? {
        let body: [String: Any] = [
            "seq": 1,
            "action": "authentication_challenge",
            "data": ["token": token],
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// Build JSON body for creating a new post.
    public static func createPostBody(channelId: String, message: String, rootId: String? = nil) -> Data? {
        var body: [String: Any] = [
            "channel_id": channelId,
            "message": message,
        ]
        if let rootId, !rootId.isEmpty {
            body["root_id"] = rootId
        }
        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Parsing

    /// Parse a WebSocket event from raw data.
    public static func parseWebSocketEvent(data: Data) -> WebSocketEvent? {
        try? JSONDecoder().decode(WebSocketEvent.self, from: data)
    }

    /// Parse a Post from an embedded JSON string (as found in EventData.post).
    public static func parsePost(from jsonString: String) -> Post? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Post.self, from: data)
    }

    /// Parse a User from API response data.
    public static func parseUser(data: Data) -> User? {
        try? JSONDecoder().decode(User.self, from: data)
    }

    // MARK: - Event Filtering

    /// Check if an event should be processed: only "posted" events, not from self.
    public static func shouldProcess(event: WebSocketEvent, myUserId: String) -> Bool {
        guard event.event == eventPosted else { return false }
        // Ignore posts from the current user
        if let data = event.data {
            if let postJSON = data.post, let post = parsePost(from: postJSON) {
                if post.userId == myUserId { return false }
            }
            if data.userId == myUserId { return false }
        }
        return true
    }

    /// Convenience to extract a Post from a WebSocket event.
    public static func extractPost(from event: WebSocketEvent) -> Post? {
        guard let postJSON = event.data?.post else { return nil }
        return parsePost(from: postJSON)
    }

    // MARK: - Formatting

    /// Truncate text for Mattermost (max 16383 chars for posts).
    public static func truncateForMattermost(_ text: String, maxLength: Int = 16383) -> String {
        guard text.count > maxLength else { return text }
        let suffix = "\n\n… (truncated)"
        return String(text.prefix(maxLength - suffix.count)) + suffix
    }

    // MARK: - Token / URL Validation

    /// Validate that a string looks like a Mattermost Personal Access Token.
    /// Tokens are typically 26+ character alphanumeric strings.
    public static func isValidToken(_ token: String) -> Bool {
        !token.isEmpty && token.count >= 26
    }

    /// Validate that a string looks like a valid Mattermost server URL.
    public static func isValidServerURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return false }
        guard URL(string: trimmed) != nil else { return false }
        return true
    }
}
