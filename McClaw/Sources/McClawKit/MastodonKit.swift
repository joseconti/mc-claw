import Foundation

/// Pure logic for Mastodon API: parsing, URL building, formatting.
/// No network calls, no side effects — fully testable.
public enum MastodonKit {

    // MARK: - Models

    /// A Mastodon account.
    public struct Account: Codable, Sendable, Equatable {
        public let id: String
        public let username: String
        public let acct: String
        public let displayName: String
        public let bot: Bool
        public let url: String
        public let note: String

        enum CodingKeys: String, CodingKey {
            case id, username, acct
            case displayName = "display_name"
            case bot, url, note
        }

        public init(
            id: String,
            username: String,
            acct: String,
            displayName: String,
            bot: Bool,
            url: String,
            note: String
        ) {
            self.id = id
            self.username = username
            self.acct = acct
            self.displayName = displayName
            self.bot = bot
            self.url = url
            self.note = note
        }
    }

    /// Visibility of a Mastodon status.
    public enum Visibility: String, Codable, Sendable, Equatable {
        case `public`
        case unlisted
        case `private`
        case direct
    }

    /// A mention within a status.
    public struct Mention: Codable, Sendable, Equatable {
        public let id: String
        public let username: String
        public let acct: String
        public let url: String

        public init(id: String, username: String, acct: String, url: String) {
            self.id = id
            self.username = username
            self.acct = acct
            self.url = url
        }
    }

    /// A Mastodon status (toot).
    public struct Status: Codable, Sendable, Equatable {
        public let id: String
        public let content: String
        public let account: Account
        public let visibility: Visibility
        public let inReplyToId: String?
        public let spoilerText: String?
        public let createdAt: String
        public let mentions: [Mention]?

        enum CodingKeys: String, CodingKey {
            case id, content, account, visibility
            case inReplyToId = "in_reply_to_id"
            case spoilerText = "spoiler_text"
            case createdAt = "created_at"
            case mentions
        }

        public init(
            id: String,
            content: String,
            account: Account,
            visibility: Visibility,
            inReplyToId: String? = nil,
            spoilerText: String? = nil,
            createdAt: String,
            mentions: [Mention]? = nil
        ) {
            self.id = id
            self.content = content
            self.account = account
            self.visibility = visibility
            self.inReplyToId = inReplyToId
            self.spoilerText = spoilerText
            self.createdAt = createdAt
            self.mentions = mentions
        }

        /// Plain text content with HTML tags stripped.
        public var plainContent: String {
            MastodonKit.stripHTML(content)
        }
    }

    /// A Mastodon notification.
    public struct Notification: Codable, Sendable, Equatable {
        public let id: String
        public let type: String
        public let account: Account
        public let status: Status?
        public let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, type, account, status
            case createdAt = "created_at"
        }

        public init(
            id: String,
            type: String,
            account: Account,
            status: Status? = nil,
            createdAt: String
        ) {
            self.id = id
            self.type = type
            self.account = account
            self.status = status
            self.createdAt = createdAt
        }
    }

    /// A WebSocket/SSE streaming event.
    public struct StreamEvent: Sendable, Equatable {
        public let event: String
        public let payload: String

        public init(event: String, payload: String) {
            self.event = event
            self.payload = payload
        }
    }

    // MARK: - Notification Types

    public static let notificationMention = "mention"
    public static let notificationFavourite = "favourite"
    public static let notificationReblog = "reblog"
    public static let notificationFollow = "follow"
    public static let notificationPoll = "poll"
    public static let notificationUpdate = "update"

    // MARK: - URL Building

    /// Build WebSocket streaming URL.
    public static func streamingURL(instanceURL: String, token: String, stream: String = "user") -> URL? {
        guard let base = sanitizeInstanceURL(instanceURL) else { return nil }
        var components = URLComponents(string: "\(base)/api/v1/streaming")
        components?.scheme = "wss"
        components?.queryItems = [
            URLQueryItem(name: "stream", value: stream),
            URLQueryItem(name: "access_token", value: token),
        ]
        return components?.url
    }

    /// Build verify credentials URL.
    public static func verifyCredentialsURL(instanceURL: String) -> URL? {
        guard let base = sanitizeInstanceURL(instanceURL) else { return nil }
        return URL(string: "\(base)/api/v1/accounts/verify_credentials")
    }

    /// Build post status URL.
    public static func postStatusURL(instanceURL: String) -> URL? {
        guard let base = sanitizeInstanceURL(instanceURL) else { return nil }
        return URL(string: "\(base)/api/v1/statuses")
    }

    /// Build notifications URL with optional type filters and pagination.
    public static func notificationsURL(instanceURL: String, types: [String] = [], sinceId: String? = nil) -> URL? {
        guard let base = sanitizeInstanceURL(instanceURL) else { return nil }
        var components = URLComponents(string: "\(base)/api/v1/notifications")
        var queryItems: [URLQueryItem] = []
        for type in types {
            queryItems.append(URLQueryItem(name: "types[]", value: type))
        }
        if let sinceId {
            queryItems.append(URLQueryItem(name: "since_id", value: sinceId))
        }
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        return components?.url
    }

    /// Build status context URL (conversation thread).
    public static func statusContextURL(instanceURL: String, statusId: String) -> URL? {
        guard let base = sanitizeInstanceURL(instanceURL) else { return nil }
        return URL(string: "\(base)/api/v1/statuses/\(statusId)/context")
    }

    // MARK: - Request Body Building

    /// Build JSON body for posting a status.
    public static func postStatusBody(
        text: String,
        inReplyToId: String? = nil,
        visibility: Visibility = .public,
        spoilerText: String? = nil
    ) -> Data? {
        var body: [String: Any] = [
            "status": text,
            "visibility": visibility.rawValue,
        ]
        if let inReplyToId {
            body["in_reply_to_id"] = inReplyToId
        }
        if let spoilerText, !spoilerText.isEmpty {
            body["spoiler_text"] = spoilerText
        }
        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Parsing

    /// Parse an account from JSON data.
    public static func parseAccount(data: Data) -> Account? {
        let decoder = JSONDecoder()
        return try? decoder.decode(Account.self, from: data)
    }

    /// Parse a status from JSON data.
    public static func parseStatus(data: Data) -> Status? {
        let decoder = JSONDecoder()
        return try? decoder.decode(Status.self, from: data)
    }

    /// Parse a notifications array from JSON data.
    public static func parseNotifications(data: Data) -> [Notification]? {
        let decoder = JSONDecoder()
        return try? decoder.decode([Notification].self, from: data)
    }

    /// Parse an SSE stream event from text.
    /// SSE format: "event: update\ndata: {\"id\":...}"
    public static func parseStreamEvent(text: String) -> StreamEvent? {
        var eventName: String?
        var dataLines: [String] = []

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("event:") {
                eventName = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("data:") {
                let dataValue = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                dataLines.append(dataValue)
            }
        }

        guard let event = eventName, !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        return StreamEvent(event: event, payload: payload)
    }

    /// Parse the payload JSON string within a stream event into a Status.
    public static func parseStreamPayload(event: StreamEvent) -> Status? {
        guard let data = event.payload.data(using: .utf8) else { return nil }
        return parseStatus(data: data)
    }

    // MARK: - Event Filtering

    /// Check if a notification is a mention.
    public static func isMention(_ notification: Notification) -> Bool {
        notification.type == notificationMention
    }

    /// Check if a notification should be processed (mention type, not from self).
    public static func shouldProcess(notification: Notification, myAccountId: String) -> Bool {
        guard notification.type == notificationMention else { return false }
        guard notification.account.id != myAccountId else { return false }
        return true
    }

    /// Extract plain text from a status by stripping HTML tags.
    public static func extractText(from status: Status) -> String {
        stripHTML(status.content)
    }

    // MARK: - Formatting

    /// Truncate text for Mastodon (default 500 chars).
    public static func truncateForMastodon(_ text: String, maxLength: Int = 500) -> String {
        guard text.count > maxLength else { return text }
        let suffix = "\n\n… (truncated)"
        return String(text.prefix(maxLength - suffix.count)) + suffix
    }

    /// Strip HTML tags from a string and decode common HTML entities.
    public static func stripHTML(_ html: String) -> String {
        // Replace <br> and <br/> with newlines
        var result = html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "</p><p>", with: "\n\n")

        // Strip all remaining HTML tags
        while let openRange = result.range(of: "<"),
              let closeRange = result.range(of: ">", range: openRange.upperBound..<result.endIndex) {
            result.removeSubrange(openRange.lowerBound...closeRange.lowerBound)
        }

        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Token/URL Validation

    /// Validate that a string looks like a Mastodon access token.
    /// Non-empty and reasonable length (typically 43+ chars).
    public static func isValidAccessToken(_ token: String) -> Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && token.count >= 10
    }

    /// Validate that a string is a valid Mastodon instance URL (https scheme required).
    public static func isValidInstanceURL(_ urlString: String) -> Bool {
        guard let components = URLComponents(string: urlString),
              components.scheme == "https",
              let host = components.host,
              !host.isEmpty,
              host.contains(".") else {
            return false
        }
        return true
    }

    // MARK: - Private Helpers

    /// Sanitize instance URL by removing trailing slashes.
    private static func sanitizeInstanceURL(_ urlString: String) -> String? {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") {
            cleaned = String(cleaned.dropLast())
        }
        guard !cleaned.isEmpty else { return nil }
        return cleaned
    }
}
