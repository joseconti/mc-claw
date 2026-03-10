import Foundation

/// Pure logic for Matrix Client-Server API: parsing, URL building, formatting.
/// No network calls, no side effects — fully testable.
public enum MatrixKit {

    // MARK: - Models

    /// Response from the /sync endpoint.
    public struct SyncResponse: Codable, Sendable, Equatable {
        public let nextBatch: String
        public let rooms: Rooms?

        enum CodingKeys: String, CodingKey {
            case nextBatch = "next_batch"
            case rooms
        }

        public init(nextBatch: String, rooms: Rooms? = nil) {
            self.nextBatch = nextBatch
            self.rooms = rooms
        }
    }

    /// Container for room data in a sync response.
    public struct Rooms: Codable, Sendable, Equatable {
        public let join: [String: JoinedRoom]?

        public init(join: [String: JoinedRoom]? = nil) {
            self.join = join
        }
    }

    /// Data for a joined room in a sync response.
    public struct JoinedRoom: Codable, Sendable, Equatable {
        public let timeline: Timeline?

        public init(timeline: Timeline? = nil) {
            self.timeline = timeline
        }
    }

    /// Timeline data within a joined room.
    public struct Timeline: Codable, Sendable, Equatable {
        public let events: [RoomEvent]?
        public let limited: Bool?
        public let prevBatch: String?

        enum CodingKeys: String, CodingKey {
            case events, limited
            case prevBatch = "prev_batch"
        }

        public init(events: [RoomEvent]? = nil, limited: Bool? = nil, prevBatch: String? = nil) {
            self.events = events
            self.limited = limited
            self.prevBatch = prevBatch
        }
    }

    /// A Matrix room event.
    public struct RoomEvent: Codable, Sendable, Equatable {
        public let type: String
        public let eventId: String
        public let sender: String
        public let originServerTs: Int64
        public let content: EventContent?

        enum CodingKeys: String, CodingKey {
            case type
            case eventId = "event_id"
            case sender
            case originServerTs = "origin_server_ts"
            case content
        }

        public init(
            type: String,
            eventId: String,
            sender: String,
            originServerTs: Int64,
            content: EventContent? = nil
        ) {
            self.type = type
            self.eventId = eventId
            self.sender = sender
            self.originServerTs = originServerTs
            self.content = content
        }

        /// The date of this event.
        public var dateValue: Date {
            Date(timeIntervalSince1970: TimeInterval(originServerTs) / 1000.0)
        }
    }

    /// Content of a Matrix event.
    public struct EventContent: Codable, Sendable, Equatable {
        public let msgtype: String?
        public let body: String?
        public let format: String?
        public let formattedBody: String?
        public let displayname: String?
        public let membership: String?

        enum CodingKeys: String, CodingKey {
            case msgtype, body, format
            case formattedBody = "formatted_body"
            case displayname, membership
        }

        public init(
            msgtype: String? = nil,
            body: String? = nil,
            format: String? = nil,
            formattedBody: String? = nil,
            displayname: String? = nil,
            membership: String? = nil
        ) {
            self.msgtype = msgtype
            self.body = body
            self.format = format
            self.formattedBody = formattedBody
            self.displayname = displayname
            self.membership = membership
        }
    }

    /// Response from the /account/whoami endpoint.
    public struct WhoAmIResponse: Codable, Sendable, Equatable {
        public let userId: String
        public let deviceId: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case deviceId = "device_id"
        }

        public init(userId: String, deviceId: String? = nil) {
            self.userId = userId
            self.deviceId = deviceId
        }
    }

    /// Response from sending a message.
    public struct SendMessageResponse: Codable, Sendable, Equatable {
        public let eventId: String

        enum CodingKeys: String, CodingKey {
            case eventId = "event_id"
        }

        public init(eventId: String) {
            self.eventId = eventId
        }
    }

    // MARK: - URL Building

    /// Build URL for the /sync endpoint.
    public static func syncURL(homeserver: String, sinceToken: String? = nil, timeout: Int = 30000, filter: String? = nil) -> URL? {
        let base = homeserver.hasSuffix("/") ? String(homeserver.dropLast()) : homeserver
        var components = URLComponents(string: "\(base)/_matrix/client/v3/sync")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "timeout", value: String(timeout)),
        ]
        if let sinceToken {
            queryItems.append(URLQueryItem(name: "since", value: sinceToken))
        }
        if let filter {
            queryItems.append(URLQueryItem(name: "filter", value: filter))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    /// Build URL for sending a message to a room.
    public static func sendMessageURL(homeserver: String, roomId: String, txnId: String) -> URL? {
        let base = homeserver.hasSuffix("/") ? String(homeserver.dropLast()) : homeserver
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        return URL(string: "\(base)/_matrix/client/v3/rooms/\(encodedRoomId)/send/m.room.message/\(txnId)")
    }

    /// Build URL for the /account/whoami endpoint.
    public static func whoAmIURL(homeserver: String) -> URL? {
        let base = homeserver.hasSuffix("/") ? String(homeserver.dropLast()) : homeserver
        return URL(string: "\(base)/_matrix/client/v3/account/whoami")
    }

    /// Build URL for the /joined_rooms endpoint.
    public static func joinedRoomsURL(homeserver: String) -> URL? {
        let base = homeserver.hasSuffix("/") ? String(homeserver.dropLast()) : homeserver
        return URL(string: "\(base)/_matrix/client/v3/joined_rooms")
    }

    // MARK: - Request Body Building

    /// Build JSON body for a plain text message (m.text).
    public static func textMessageBody(text: String) -> Data? {
        let body: [String: Any] = [
            "msgtype": "m.text",
            "body": text,
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// Build JSON body for a notice message (m.notice), typically used by bots.
    public static func noticeMessageBody(text: String) -> Data? {
        let body: [String: Any] = [
            "msgtype": "m.notice",
            "body": text,
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// Build JSON body for a formatted HTML message.
    public static func htmlMessageBody(text: String, html: String) -> Data? {
        let body: [String: Any] = [
            "msgtype": "m.text",
            "body": text,
            "format": "org.matrix.custom.html",
            "formatted_body": html,
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Parsing

    /// Parse a /sync JSON response.
    public static func parseSyncResponse(data: Data) -> SyncResponse? {
        let decoder = JSONDecoder()
        return try? decoder.decode(SyncResponse.self, from: data)
    }

    /// Parse a /account/whoami JSON response.
    public static func parseWhoAmI(data: Data) -> WhoAmIResponse? {
        let decoder = JSONDecoder()
        return try? decoder.decode(WhoAmIResponse.self, from: data)
    }

    /// Parse a send message response.
    public static func parseSendResponse(data: Data) -> SendMessageResponse? {
        let decoder = JSONDecoder()
        return try? decoder.decode(SendMessageResponse.self, from: data)
    }

    // MARK: - Event Filtering

    /// Extract m.room.message events from a sync response, filtering out own messages.
    public static func extractMessages(from sync: SyncResponse, myUserId: String) -> [(roomId: String, event: RoomEvent)] {
        var results: [(roomId: String, event: RoomEvent)] = []

        guard let joinedRooms = sync.rooms?.join else { return results }

        for (roomId, room) in joinedRooms {
            guard let events = room.timeline?.events else { continue }
            for event in events {
                guard event.type == "m.room.message" else { continue }
                guard event.sender != myUserId else { continue }
                results.append((roomId: roomId, event: event))
            }
        }

        return results
    }

    /// Check if an event is a text message (m.text or m.notice).
    public static func isTextMessage(_ event: RoomEvent) -> Bool {
        guard event.type == "m.room.message" else { return false }
        guard let msgtype = event.content?.msgtype else { return false }
        return msgtype == "m.text" || msgtype == "m.notice"
    }

    /// Extract the text body from a room event.
    public static func extractText(from event: RoomEvent) -> String? {
        guard event.type == "m.room.message" else { return nil }
        guard let body = event.content?.body, !body.isEmpty else { return nil }
        return body
    }

    // MARK: - Formatting

    /// Truncate text for Matrix (max 65536 chars by default).
    public static func truncateForMatrix(_ text: String, maxLength: Int = 65536) -> String {
        guard text.count > maxLength else { return text }
        let suffix = "\n\n… (truncated)"
        return String(text.prefix(maxLength - suffix.count)) + suffix
    }

    /// Generate a UUID-based transaction ID for sending messages.
    public static func generateTxnId() -> String {
        UUID().uuidString
    }

    // MARK: - Token Validation

    /// Basic validation that a string looks like a Matrix access token.
    /// Must be non-empty and of reasonable length.
    public static func isValidAccessToken(_ token: String) -> Bool {
        !token.isEmpty && token.count >= 10 && token.count <= 1024
    }

    /// Validate that a string looks like a Matrix homeserver URL.
    /// Must start with https:// or http://.
    public static func isValidHomeserverURL(_ urlString: String) -> Bool {
        guard urlString.hasPrefix("https://") || urlString.hasPrefix("http://") else { return false }
        guard let url = URL(string: urlString) else { return false }
        guard url.host != nil else { return false }
        return true
    }
}
