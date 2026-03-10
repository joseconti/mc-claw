import Foundation

/// State of a native channel connection.
enum NativeChannelState: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case error
}

/// A native channel definition.
struct NativeChannelDefinition: Sendable {
    let id: String
    let name: String
    let icon: String
    let connectorDefinitionId: String
}

/// Configuration for a native channel instance.
struct NativeChannelConfig: Codable, Sendable {
    let channelId: String
    let connectorInstanceId: String
    var enabled: Bool
    var autoReconnect: Bool
    var respondWithAI: Bool
    var aiProviderId: String?
    var allowedChatIds: [Int64]?
    var allowedChannelIds: [String]?
    var systemPrompt: String?
    /// Slack Socket Mode requires an app-level token (xapp-) in addition to the bot token.
    var appLevelToken: String?
    /// Whether to respond only to DMs (Slack/Discord). If false, responds in channels where mentioned.
    var dmOnly: Bool?
    /// Server/instance URL for self-hosted platforms (Matrix, Mattermost, Zulip, Rocket.Chat, Mastodon).
    var serverURL: String?
    /// Bot email for Zulip authentication (used with API key).
    var botEmail: String?
    /// Client ID for platforms that require it (Twitch).
    var clientId: String?
    /// User ID for platforms that require it (Rocket.Chat auth).
    var userId: String?
    /// Allowed room/stream IDs (Matrix rooms, Zulip streams).
    var allowedRoomIds: [String]?
    /// Mastodon post visibility (public, unlisted, private, direct).
    var replyVisibility: String?

    init(
        channelId: String,
        connectorInstanceId: String,
        enabled: Bool = true,
        autoReconnect: Bool = true,
        respondWithAI: Bool = true,
        aiProviderId: String? = nil,
        allowedChatIds: [Int64]? = nil,
        allowedChannelIds: [String]? = nil,
        systemPrompt: String? = nil,
        appLevelToken: String? = nil,
        dmOnly: Bool? = nil,
        serverURL: String? = nil,
        botEmail: String? = nil,
        clientId: String? = nil,
        userId: String? = nil,
        allowedRoomIds: [String]? = nil,
        replyVisibility: String? = nil
    ) {
        self.channelId = channelId
        self.connectorInstanceId = connectorInstanceId
        self.enabled = enabled
        self.autoReconnect = autoReconnect
        self.respondWithAI = respondWithAI
        self.aiProviderId = aiProviderId
        self.allowedChatIds = allowedChatIds
        self.allowedChannelIds = allowedChannelIds
        self.systemPrompt = systemPrompt
        self.appLevelToken = appLevelToken
        self.dmOnly = dmOnly
        self.serverURL = serverURL
        self.botEmail = botEmail
        self.clientId = clientId
        self.userId = userId
        self.allowedRoomIds = allowedRoomIds
        self.replyVisibility = replyVisibility
    }
}

/// An incoming message from a native channel.
struct NativeChannelMessage: Identifiable, Sendable {
    let id: String
    let channelId: String
    /// Numeric chat ID (Telegram). Use 0 for string-based platforms.
    let chatId: Int64
    /// Numeric sender ID (Telegram). Use 0 for string-based platforms.
    let senderId: Int64
    let senderName: String
    let text: String
    let date: Date
    let replyToMessageId: Int?
    /// String-based channel ID (Slack, Discord).
    let platformChannelId: String?
    /// String-based user ID (Slack, Discord).
    let platformUserId: String?
    /// Thread timestamp for threaded replies (Slack).
    let threadId: String?

    init(
        id: String = UUID().uuidString,
        channelId: String,
        chatId: Int64 = 0,
        senderId: Int64 = 0,
        senderName: String,
        text: String,
        date: Date,
        replyToMessageId: Int? = nil,
        platformChannelId: String? = nil,
        platformUserId: String? = nil,
        threadId: String? = nil
    ) {
        self.id = id
        self.channelId = channelId
        self.chatId = chatId
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.date = date
        self.replyToMessageId = replyToMessageId
        self.platformChannelId = platformChannelId
        self.platformUserId = platformUserId
        self.threadId = threadId
    }
}

/// Stats for a native channel connection.
struct NativeChannelStats: Sendable {
    var messagesReceived: Int = 0
    var messagesSent: Int = 0
    var lastMessageAt: Date?
    var connectedSince: Date?
    var reconnectCount: Int = 0
    var lastError: String?
}
