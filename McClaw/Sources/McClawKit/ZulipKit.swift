import Foundation

/// Pure logic for Zulip REST API: parsing, URL building, auth, formatting.
/// No network calls, no side effects — fully testable.
public enum ZulipKit {

    // MARK: - Models

    /// Response from POST /api/v1/register.
    public struct RegisterResponse: Codable, Sendable, Equatable {
        public let queueId: String
        public let lastEventId: Int
        public let eventQueueLongpollTimeoutSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case queueId = "queue_id"
            case lastEventId = "last_event_id"
            case eventQueueLongpollTimeoutSeconds = "event_queue_longpoll_timeout_seconds"
        }

        public init(queueId: String, lastEventId: Int, eventQueueLongpollTimeoutSeconds: Int? = nil) {
            self.queueId = queueId
            self.lastEventId = lastEventId
            self.eventQueueLongpollTimeoutSeconds = eventQueueLongpollTimeoutSeconds
        }
    }

    /// Response from GET /api/v1/events.
    public struct EventsResponse: Codable, Sendable, Equatable {
        public let events: [Event]
        public let result: String

        public init(events: [Event], result: String) {
            self.events = events
            self.result = result
        }
    }

    /// A single event from the event queue.
    public struct Event: Codable, Sendable, Equatable {
        public let type: String
        public let id: Int
        public let message: ZulipMessage?

        public init(type: String, id: Int, message: ZulipMessage? = nil) {
            self.type = type
            self.id = id
            self.message = message
        }
    }

    /// A Zulip message.
    public struct ZulipMessage: Codable, Sendable, Equatable {
        public let id: Int
        public let senderId: Int
        public let senderFullName: String
        public let senderEmail: String
        public let content: String
        public let displayRecipient: DisplayRecipient?
        public let subject: String?
        public let type: String
        public let timestamp: Int

        enum CodingKeys: String, CodingKey {
            case id
            case senderId = "sender_id"
            case senderFullName = "sender_full_name"
            case senderEmail = "sender_email"
            case content
            case displayRecipient = "display_recipient"
            case subject, type, timestamp
        }

        public init(
            id: Int,
            senderId: Int,
            senderFullName: String,
            senderEmail: String,
            content: String,
            displayRecipient: DisplayRecipient? = nil,
            subject: String? = nil,
            type: String,
            timestamp: Int
        ) {
            self.id = id
            self.senderId = senderId
            self.senderFullName = senderFullName
            self.senderEmail = senderEmail
            self.content = content
            self.displayRecipient = displayRecipient
            self.subject = subject
            self.type = type
            self.timestamp = timestamp
        }

        public var dateValue: Date {
            Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
    }

    /// Display recipient — for streams it's a string (stream name),
    /// for DMs it's an array of user objects. Uses custom decoding.
    public enum DisplayRecipient: Codable, Sendable, Equatable {
        case stream(String)
        case users([RecipientUser])

        public struct RecipientUser: Codable, Sendable, Equatable {
            public let id: Int
            public let fullName: String
            public let email: String

            enum CodingKeys: String, CodingKey {
                case id
                case fullName = "full_name"
                case email
            }

            public init(id: Int, fullName: String, email: String) {
                self.id = id
                self.fullName = fullName
                self.email = email
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let streamName = try? container.decode(String.self) {
                self = .stream(streamName)
            } else if let users = try? container.decode([RecipientUser].self) {
                self = .users(users)
            } else {
                throw DecodingError.typeMismatch(
                    DisplayRecipient.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected String or [RecipientUser]"
                    )
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .stream(let name):
                try container.encode(name)
            case .users(let users):
                try container.encode(users)
            }
        }

        /// The stream name if this is a stream recipient.
        public var streamName: String? {
            if case .stream(let name) = self { return name }
            return nil
        }

        /// The users if this is a DM recipient.
        public var recipientUsers: [RecipientUser]? {
            if case .users(let users) = self { return users }
            return nil
        }
    }

    /// User profile from GET /api/v1/users/me.
    public struct UserProfile: Codable, Sendable, Equatable {
        public let userId: Int
        public let fullName: String
        public let email: String
        public let isBot: Bool

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case fullName = "full_name"
            case email
            case isBot = "is_bot"
        }

        public init(userId: Int, fullName: String, email: String, isBot: Bool) {
            self.userId = userId
            self.fullName = fullName
            self.email = email
            self.isBot = isBot
        }
    }

    /// Response from POST /api/v1/messages.
    public struct SendMessageResponse: Codable, Sendable, Equatable {
        public let id: Int?
        public let result: String
        public let msg: String

        public init(id: Int? = nil, result: String, msg: String) {
            self.id = id
            self.result = result
            self.msg = msg
        }
    }

    // MARK: - Message Types

    /// Stream (channel) message type.
    public static let streamType = "stream"

    /// Direct (private) message type.
    public static let directType = "private"

    // MARK: - URL Building

    /// Build URL for POST /api/v1/register.
    public static func registerURL(serverURL: String) -> URL? {
        URL(string: "\(normalizeServerURL(serverURL))/api/v1/register")
    }

    /// Build URL for GET /api/v1/events with queue_id and last_event_id.
    public static func eventsURL(serverURL: String, queueId: String, lastEventId: Int) -> URL? {
        var components = URLComponents(string: "\(normalizeServerURL(serverURL))/api/v1/events")
        components?.queryItems = [
            URLQueryItem(name: "queue_id", value: queueId),
            URLQueryItem(name: "last_event_id", value: String(lastEventId)),
        ]
        return components?.url
    }

    /// Build URL for POST /api/v1/messages.
    public static func messagesURL(serverURL: String) -> URL? {
        URL(string: "\(normalizeServerURL(serverURL))/api/v1/messages")
    }

    /// Build URL for GET /api/v1/users/me.
    public static func usersURL(serverURL: String) -> URL? {
        URL(string: "\(normalizeServerURL(serverURL))/api/v1/users/me")
    }

    /// Normalize server URL by removing trailing slash.
    private static func normalizeServerURL(_ urlString: String) -> String {
        var url = urlString
        while url.hasSuffix("/") {
            url.removeLast()
        }
        return url
    }

    // MARK: - Auth Building

    /// Build HTTP Basic Auth header value: "Basic base64(email:apiKey)".
    public static func basicAuthHeader(email: String, apiKey: String) -> String {
        let credentials = "\(email):\(apiKey)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    // MARK: - Request Body Building

    /// Build form-encoded body for POST /api/v1/register.
    public static func registerBody(eventTypes: [String] = ["message"]) -> Data? {
        guard let jsonTypes = try? JSONSerialization.data(withJSONObject: eventTypes),
              let typesString = String(data: jsonTypes, encoding: .utf8) else {
            return nil
        }
        let body = "event_types=\(formEncode(typesString))"
        return body.data(using: .utf8)
    }

    /// Build form-encoded body for sending a stream message.
    public static func sendStreamMessageBody(stream: String, topic: String, content: String) -> Data? {
        let parts = [
            "type=\(formEncode(streamType))",
            "to=\(formEncode(stream))",
            "topic=\(formEncode(topic))",
            "content=\(formEncode(content))",
        ]
        return parts.joined(separator: "&").data(using: .utf8)
    }

    /// Build form-encoded body for sending a direct message.
    /// `to` is a JSON array of user IDs or emails, e.g. `[12345]` or `["user@example.com"]`.
    public static func sendDirectMessageBody(to: String, content: String) -> Data? {
        let parts = [
            "type=\(formEncode(directType))",
            "to=\(formEncode(to))",
            "content=\(formEncode(content))",
        ]
        return parts.joined(separator: "&").data(using: .utf8)
    }

    /// Percent-encode a string for application/x-www-form-urlencoded.
    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Parsing

    /// Parse a register response.
    public static func parseRegisterResponse(data: Data) -> RegisterResponse? {
        let decoder = JSONDecoder()
        return try? decoder.decode(RegisterResponse.self, from: data)
    }

    /// Parse events from the event queue.
    public static func parseEvents(data: Data) -> [Event]? {
        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(EventsResponse.self, from: data),
              response.result == "success" else {
            return nil
        }
        return response.events
    }

    /// Parse user profile from /api/v1/users/me.
    public static func parseUserProfile(data: Data) -> UserProfile? {
        let decoder = JSONDecoder()
        return try? decoder.decode(UserProfile.self, from: data)
    }

    /// Parse send message response.
    public static func parseSendResponse(data: Data) -> SendMessageResponse? {
        let decoder = JSONDecoder()
        return try? decoder.decode(SendMessageResponse.self, from: data)
    }

    // MARK: - Event Filtering

    /// Check if an event should be processed: must be a message event and not from self.
    public static func shouldProcess(event: Event, myUserId: Int) -> Bool {
        guard event.type == "message" else { return false }
        guard let message = event.message else { return false }
        return message.senderId != myUserId
    }

    /// Check if a message is a stream (channel) message.
    public static func isStreamMessage(_ message: ZulipMessage) -> Bool {
        message.type == streamType
    }

    /// Check if a message is a direct (private) message.
    public static func isDirectMessage(_ message: ZulipMessage) -> Bool {
        message.type == directType
    }

    /// Extract the text content from a message.
    public static func extractText(from message: ZulipMessage) -> String? {
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Formatting

    /// Truncate text for Zulip (max 10000 chars by default).
    public static func truncateForZulip(_ text: String, maxLength: Int = 10000) -> String {
        guard text.count > maxLength else { return text }
        let suffix = "\n\n… (truncated)"
        return String(text.prefix(maxLength - suffix.count)) + suffix
    }

    /// Extract the topic (subject) from a stream message.
    public static func topicFromMessage(_ message: ZulipMessage) -> String? {
        guard isStreamMessage(message) else { return nil }
        guard let subject = message.subject, !subject.isEmpty else { return nil }
        return subject
    }

    // MARK: - Validation

    /// Validate that an API key looks reasonable (non-empty, >= 20 chars).
    public static func isValidAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count >= 20
    }

    /// Basic email format validation.
    public static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: "@", maxSplits: 2)
        guard parts.count == 2 else { return false }
        guard !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return parts[1].contains(".")
    }

    /// Validate that a server URL string is well-formed.
    public static func isValidServerURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let url = URL(string: trimmed) else { return false }
        guard let scheme = url.scheme, (scheme == "http" || scheme == "https") else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }
}
