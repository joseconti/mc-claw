import Foundation

/// Pure logic for Rocket.Chat REST API and DDP WebSocket: parsing, URL building, formatting.
/// No network calls, no side effects — fully testable.
public enum RocketChatKit {

    // MARK: - Models

    /// A Rocket.Chat user within a message.
    public struct RCUser: Sendable, Equatable {
        public let id: String
        public let username: String
        public let name: String?

        public init(id: String, username: String, name: String? = nil) {
            self.id = id
            self.username = username
            self.name = name
        }

        public var displayName: String {
            if let name, !name.isEmpty { return name }
            return username
        }
    }

    /// A Rocket.Chat message.
    public struct RCMessage: Sendable, Equatable, Identifiable {
        public let id: String
        public let rid: String
        public let msg: String
        public let ts: String
        public let user: RCUser
        public let tmid: String?

        public init(id: String, rid: String, msg: String, ts: String, user: RCUser, tmid: String? = nil) {
            self.id = id
            self.rid = rid
            self.msg = msg
            self.ts = ts
            self.user = user
            self.tmid = tmid
        }
    }

    /// A Rocket.Chat channel/room.
    public struct RCChannel: Sendable, Equatable {
        public let id: String
        public let name: String?
        public let type: String
        public let topic: String?

        public init(id: String, name: String? = nil, type: String, topic: String? = nil) {
            self.id = id
            self.name = name
            self.type = type
            self.topic = topic
        }

        public var displayName: String {
            if let name, !name.isEmpty { return name }
            return "Room \(id)"
        }
    }

    /// Response from GET /api/v1/me.
    public struct MeResponse: Sendable, Equatable {
        public let id: String
        public let username: String
        public let name: String?
        public let status: String?
        public let active: Bool

        public init(id: String, username: String, name: String? = nil, status: String? = nil, active: Bool = true) {
            self.id = id
            self.username = username
            self.name = name
            self.status = status
            self.active = active
        }

        public var displayName: String {
            if let name, !name.isEmpty { return name }
            return username
        }
    }

    /// Result extracted from a DDP login response.
    public struct LoginResult: Sendable, Equatable {
        public let id: String
        public let token: String
        public let tokenExpires: String?

        public init(id: String, token: String, tokenExpires: String? = nil) {
            self.id = id
            self.token = token
            self.tokenExpires = tokenExpires
        }
    }

    /// A parsed DDP message (generic structure).
    /// DDP has dynamic structure so we use manual JSON parsing.
    /// Uses @unchecked Sendable because [String: Any] is not Sendable but
    /// the struct is immutable and only constructed from parsed JSON.
    public struct DDPMessage: @unchecked Sendable, Equatable {
        public let msg: String?
        public let id: String?
        public let collection: String?
        public let raw: [String: Any]

        public init(msg: String? = nil, id: String? = nil, collection: String? = nil, raw: [String: Any] = [:]) {
            self.msg = msg
            self.id = id
            self.collection = collection
            self.raw = raw
        }

        public static func == (lhs: DDPMessage, rhs: DDPMessage) -> Bool {
            lhs.msg == rhs.msg && lhs.id == rhs.id && lhs.collection == rhs.collection
        }

        /// Whether this is a ping message that needs a pong response.
        public var isPing: Bool { msg == ddpPing }

        /// Whether this is a connected response.
        public var isConnected: Bool { msg == ddpConnected }

        /// Whether this is a result response (login, method calls).
        public var isResult: Bool { msg == ddpResult }

        /// Whether this is a changed event (subscription data).
        public var isChanged: Bool { msg == ddpChanged }

        /// Whether this is a ready confirmation for a subscription.
        public var isReady: Bool { msg == ddpReady }

        /// Whether this is an error message.
        public var isError: Bool { msg == ddpError }
    }

    // MARK: - DDP Message Types

    public static let ddpConnect = "connect"
    public static let ddpConnected = "connected"
    public static let ddpPing = "ping"
    public static let ddpPong = "pong"
    public static let ddpSub = "sub"
    public static let ddpUnsub = "unsub"
    public static let ddpMethod = "method"
    public static let ddpResult = "result"
    public static let ddpChanged = "changed"
    public static let ddpAdded = "added"
    public static let ddpReady = "ready"
    public static let ddpError = "error"

    // MARK: - URL Building

    /// Convert a Rocket.Chat server URL to its DDP WebSocket URL.
    /// Converts http(s) to ws(s) and appends /websocket.
    public static func webSocketURL(serverURL: String) -> URL? {
        var normalized = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove trailing slash
        while normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        // Convert scheme
        if normalized.hasPrefix("https://") {
            normalized = "wss://" + normalized.dropFirst("https://".count)
        } else if normalized.hasPrefix("http://") {
            normalized = "ws://" + normalized.dropFirst("http://".count)
        } else if !normalized.hasPrefix("wss://") && !normalized.hasPrefix("ws://") {
            normalized = "wss://" + normalized
        }
        return URL(string: "\(normalized)/websocket")
    }

    /// Build a REST API URL for a given path.
    public static func restURL(serverURL: String, path: String) -> URL? {
        var normalized = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        let cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: "\(normalized)\(cleanPath)")
    }

    /// Build the chat.sendMessage REST URL.
    public static func sendMessageURL(serverURL: String) -> URL? {
        restURL(serverURL: serverURL, path: "/api/v1/chat.sendMessage")
    }

    /// Build the /me REST URL.
    public static func meURL(serverURL: String) -> URL? {
        restURL(serverURL: serverURL, path: "/api/v1/me")
    }

    // MARK: - DDP Payload Building

    /// Build the DDP connect payload.
    public static func connectPayload() -> Data? {
        let body: [String: Any] = [
            "msg": "connect",
            "version": "1",
            "support": ["1"],
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// Build the DDP login payload using a resume token.
    public static func loginPayload(token: String, id: String = "login-1") -> Data? {
        let body: [String: Any] = [
            "msg": "method",
            "method": "login",
            "id": id,
            "params": [["resume": token]],
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// Build a DDP pong response.
    public static func pongPayload(id: String? = nil) -> Data? {
        var body: [String: Any] = ["msg": "pong"]
        if let id {
            body["id"] = id
        }
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// Build a DDP subscription payload for stream-room-messages.
    public static func subscribeMessagesPayload(subId: String = "sub-0") -> Data? {
        let body: [String: Any] = [
            "msg": "sub",
            "id": subId,
            "name": "stream-room-messages",
            "params": ["__my_messages__", false],
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - REST Request Body Building

    /// Build JSON body for chat.sendMessage.
    public static func sendMessageBody(roomId: String, text: String, threadId: String? = nil) -> Data? {
        var message: [String: Any] = [
            "rid": roomId,
            "msg": text,
        ]
        if let threadId {
            message["tmid"] = threadId
        }
        let body: [String: Any] = ["message": message]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Auth Header Building

    /// Build authentication headers for Rocket.Chat REST API.
    public static func authHeaders(userId: String, token: String) -> [String: String] {
        [
            "X-Auth-Token": token,
            "X-User-Id": userId,
            "Content-Type": "application/json",
        ]
    }

    // MARK: - Parsing

    /// Parse a DDP message from raw WebSocket data.
    public static func parseDDPMessage(data: Data) -> DDPMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return DDPMessage(
            msg: json["msg"] as? String,
            id: json["id"] as? String,
            collection: json["collection"] as? String,
            raw: json
        )
    }

    /// Extract an RCMessage from a stream-room-messages "changed" DDP event.
    public static func parseMessage(from ddpData: Data) -> RCMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: ddpData) as? [String: Any],
              json["msg"] as? String == "changed",
              json["collection"] as? String == "stream-room-messages",
              let fields = json["fields"] as? [String: Any],
              let args = fields["args"] as? [[String: Any]],
              let msgObj = args.first else {
            return nil
        }
        return parseMessageObject(msgObj)
    }

    /// Parse a message object dictionary into an RCMessage.
    private static func parseMessageObject(_ obj: [String: Any]) -> RCMessage? {
        guard let id = obj["_id"] as? String,
              let rid = obj["rid"] as? String,
              let msg = obj["msg"] as? String,
              let userObj = obj["u"] as? [String: Any],
              let userId = userObj["_id"] as? String,
              let username = userObj["username"] as? String else {
            return nil
        }

        let ts: String
        if let tsDict = obj["ts"] as? [String: Any], let dateStr = tsDict["$date"] as? Int64 {
            ts = String(dateStr)
        } else if let tsStr = obj["ts"] as? String {
            ts = tsStr
        } else {
            ts = ""
        }

        let user = RCUser(
            id: userId,
            username: username,
            name: userObj["name"] as? String
        )

        return RCMessage(
            id: id,
            rid: rid,
            msg: msg,
            ts: ts,
            user: user,
            tmid: obj["tmid"] as? String
        )
    }

    /// Parse GET /api/v1/me response.
    public static func parseMe(data: Data) -> MeResponse? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["_id"] as? String,
              let username = json["username"] as? String else {
            return nil
        }

        return MeResponse(
            id: id,
            username: username,
            name: json["name"] as? String,
            status: json["status"] as? String,
            active: json["active"] as? Bool ?? true
        )
    }

    /// Parse a login result from a DDP method response.
    public static func parseLoginResult(from ddpMessage: DDPMessage) -> LoginResult? {
        guard ddpMessage.isResult else { return nil }
        guard let result = ddpMessage.raw["result"] as? [String: Any],
              let id = result["id"] as? String,
              let token = result["token"] as? String else {
            return nil
        }

        let tokenExpires: String?
        if let expires = result["tokenExpires"] as? [String: Any],
           let dateVal = expires["$date"] as? Int64 {
            tokenExpires = String(dateVal)
        } else {
            tokenExpires = nil
        }

        return LoginResult(id: id, token: token, tokenExpires: tokenExpires)
    }

    // MARK: - Event Filtering

    /// Check if a message should be processed (not from self, has text).
    public static func shouldProcess(message: RCMessage, myUserId: String) -> Bool {
        guard message.user.id != myUserId else { return false }
        guard !message.msg.isEmpty else { return false }
        return true
    }

    /// Extract the text content from a message.
    public static func extractText(from message: RCMessage) -> String? {
        let text = message.msg.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Formatting

    /// Truncate text for Rocket.Chat (max 65536 chars by default).
    public static func truncateForRocketChat(_ text: String, maxLength: Int = 65536) -> String {
        guard text.count > maxLength else { return text }
        let suffix = "\n\n… (truncated)"
        return String(text.prefix(maxLength - suffix.count)) + suffix
    }

    // MARK: - Validation

    /// Validate that a token is non-empty and reasonably long.
    public static func isValidToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 10
    }

    /// Validate that a string looks like a valid Rocket.Chat server URL.
    public static func isValidServerURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return false }
        guard let url = URL(string: trimmed), url.host != nil else { return false }
        return true
    }
}
