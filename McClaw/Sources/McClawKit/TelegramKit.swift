import Foundation

/// Pure logic for Telegram Bot API: parsing, URL building, formatting.
/// No network calls, no side effects — fully testable.
public enum TelegramKit {

    // MARK: - Models

    /// A Telegram user.
    public struct User: Codable, Sendable, Equatable {
        public let id: Int64
        public let isBot: Bool
        public let firstName: String
        public let lastName: String?
        public let username: String?

        enum CodingKeys: String, CodingKey {
            case id
            case isBot = "is_bot"
            case firstName = "first_name"
            case lastName = "last_name"
            case username
        }

        public init(id: Int64, isBot: Bool, firstName: String, lastName: String? = nil, username: String? = nil) {
            self.id = id
            self.isBot = isBot
            self.firstName = firstName
            self.lastName = lastName
            self.username = username
        }

        public var displayName: String {
            if let last = lastName {
                return "\(firstName) \(last)"
            }
            return firstName
        }
    }

    /// A Telegram chat.
    public struct Chat: Codable, Sendable, Equatable {
        public let id: Int64
        public let type: String
        public let title: String?
        public let username: String?
        public let firstName: String?
        public let lastName: String?

        enum CodingKeys: String, CodingKey {
            case id, type, title, username
            case firstName = "first_name"
            case lastName = "last_name"
        }

        public init(id: Int64, type: String, title: String? = nil, username: String? = nil, firstName: String? = nil, lastName: String? = nil) {
            self.id = id
            self.type = type
            self.title = title
            self.username = username
            self.firstName = firstName
            self.lastName = lastName
        }

        public var displayName: String {
            if let title { return title }
            if let first = firstName {
                if let last = lastName { return "\(first) \(last)" }
                return first
            }
            if let username { return "@\(username)" }
            return "Chat \(id)"
        }
    }

    /// A Telegram message.
    public struct Message: Codable, Sendable, Equatable, Identifiable {
        public let messageId: Int
        public let from: User?
        public let chat: Chat
        public let date: Int
        public let text: String?

        enum CodingKeys: String, CodingKey {
            case messageId = "message_id"
            case from, chat, date, text
        }

        public var id: Int { messageId }

        public init(messageId: Int, from: User? = nil, chat: Chat, date: Int, text: String? = nil) {
            self.messageId = messageId
            self.from = from
            self.chat = chat
            self.date = date
            self.text = text
        }

        public var dateValue: Date {
            Date(timeIntervalSince1970: TimeInterval(date))
        }
    }

    /// A Telegram update from getUpdates.
    public struct Update: Codable, Sendable, Equatable, Identifiable {
        public let updateId: Int
        public let message: Message?
        public let editedMessage: Message?

        enum CodingKeys: String, CodingKey {
            case updateId = "update_id"
            case message
            case editedMessage = "edited_message"
        }

        public var id: Int { updateId }

        public init(updateId: Int, message: Message? = nil, editedMessage: Message? = nil) {
            self.updateId = updateId
            self.message = message
            self.editedMessage = editedMessage
        }

        /// The effective message from this update (message or edited_message).
        public var effectiveMessage: Message? {
            message ?? editedMessage
        }
    }

    /// Bot info from getMe.
    public struct BotInfo: Codable, Sendable, Equatable {
        public let id: Int64
        public let isBot: Bool
        public let firstName: String
        public let username: String?

        enum CodingKeys: String, CodingKey {
            case id
            case isBot = "is_bot"
            case firstName = "first_name"
            case username
        }

        public init(id: Int64, isBot: Bool, firstName: String, username: String? = nil) {
            self.id = id
            self.isBot = isBot
            self.firstName = firstName
            self.username = username
        }
    }

    /// Wrapper for Telegram Bot API responses.
    public struct APIResponse<T: Codable & Sendable>: Codable, Sendable {
        public let ok: Bool
        public let description: String?
        public let result: T?
        public let errorCode: Int?

        enum CodingKeys: String, CodingKey {
            case ok, description, result
            case errorCode = "error_code"
        }
    }

    // MARK: - URL Building

    private static let baseURL = "https://api.telegram.org"

    /// Build URL for a Bot API method.
    public static func apiURL(token: String, method: String, params: [String: String] = [:]) -> URL? {
        var components = URLComponents(string: "\(baseURL)/bot\(token)/\(method)")
        if !params.isEmpty {
            components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components?.url
    }

    /// Build getUpdates URL with long-polling parameters.
    public static func getUpdatesURL(token: String, offset: Int?, limit: Int = 100, timeout: Int = 30) -> URL? {
        var params: [String: String] = [
            "limit": String(limit),
            "timeout": String(timeout),
            "allowed_updates": "[\"message\",\"edited_message\"]",
        ]
        if let offset {
            params["offset"] = String(offset)
        }
        return apiURL(token: token, method: "getUpdates", params: params)
    }

    /// Build sendMessage URL.
    public static func sendMessageURL(token: String) -> URL? {
        URL(string: "\(baseURL)/bot\(token)/sendMessage")
    }

    /// Build getMe URL.
    public static func getMeURL(token: String) -> URL? {
        apiURL(token: token, method: "getMe")
    }

    // MARK: - Request Body Building

    /// Build JSON body for sendMessage.
    public static func sendMessageBody(chatId: Int64, text: String, parseMode: String = "Markdown", replyToMessageId: Int? = nil) -> Data? {
        var body: [String: Any] = [
            "chat_id": chatId,
            "text": text,
            "parse_mode": parseMode,
        ]
        if let replyId = replyToMessageId {
            body["reply_to_message_id"] = replyId
        }
        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Parsing

    /// Parse a getUpdates JSON response.
    public static func parseUpdates(data: Data) -> [Update]? {
        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(APIResponse<[Update]>.self, from: data),
              response.ok else {
            return nil
        }
        return response.result
    }

    /// Parse a getMe JSON response.
    public static func parseBotInfo(data: Data) -> BotInfo? {
        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(APIResponse<BotInfo>.self, from: data),
              response.ok else {
            return nil
        }
        return response.result
    }

    /// Parse a sendMessage JSON response.
    public static func parseSentMessage(data: Data) -> Message? {
        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(APIResponse<Message>.self, from: data),
              response.ok else {
            return nil
        }
        return response.result
    }

    // MARK: - Offset Calculation

    /// Calculate the next offset for getUpdates polling.
    /// Telegram requires offset = last_update_id + 1 to acknowledge processed updates.
    public static func nextOffset(from updates: [Update]) -> Int? {
        guard let last = updates.max(by: { $0.updateId < $1.updateId }) else {
            return nil
        }
        return last.updateId + 1
    }

    // MARK: - Filtering

    /// Filter updates to only include text messages (not from bots).
    public static func filterTextMessages(_ updates: [Update]) -> [Update] {
        updates.filter { update in
            guard let msg = update.effectiveMessage else { return false }
            guard msg.text != nil else { return false }
            guard msg.from?.isBot != true else { return false }
            return true
        }
    }

    // MARK: - Formatting

    /// Truncate a long response for Telegram (max 4096 chars).
    public static func truncateForTelegram(_ text: String, maxLength: Int = 4096) -> String {
        guard text.count > maxLength else { return text }
        let suffix = "\n\n… (truncated)"
        return String(text.prefix(maxLength - suffix.count)) + suffix
    }

    /// Escape special Markdown characters for Telegram MarkdownV2.
    public static func escapeMarkdownV2(_ text: String) -> String {
        let specialChars: Set<Character> = ["_", "*", "[", "]", "(", ")", "~", "`", ">", "#", "+", "-", "=", "|", "{", "}", ".", "!"]
        return String(text.flatMap { char -> [Character] in
            if specialChars.contains(char) {
                return ["\\", char]
            }
            return [char]
        })
    }

    /// Format a user mention.
    public static func formatUserMention(_ user: User) -> String {
        if let username = user.username {
            return "@\(username)"
        }
        return user.displayName
    }

    // MARK: - Token Validation

    /// Basic validation that a string looks like a Telegram bot token.
    /// Format: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`
    public static func isValidBotToken(_ token: String) -> Bool {
        let parts = token.split(separator: ":")
        guard parts.count == 2 else { return false }
        guard let _ = Int64(parts[0]) else { return false }
        guard parts[1].count >= 20 else { return false }
        return true
    }
}
