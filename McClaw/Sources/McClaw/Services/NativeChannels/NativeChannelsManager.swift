import Foundation
import Logging

/// Coordinates all native channel connections.
/// Manages lifecycle, config persistence, and routes incoming messages to CLIBridge.
@MainActor
@Observable
final class NativeChannelsManager {
    static let shared = NativeChannelsManager()

    private let logger = Logger(label: "ai.mcclaw.native-channels")

    // MARK: - Observable State

    var telegramState: NativeChannelState = .disconnected
    var telegramStats = NativeChannelStats()
    var telegramBotName: String?
    var slackState: NativeChannelState = .disconnected
    var slackStats = NativeChannelStats()
    var slackBotName: String?
    var discordState: NativeChannelState = .disconnected
    var discordStats = NativeChannelStats()
    var discordBotName: String?
    var matrixState: NativeChannelState = .disconnected
    var matrixStats = NativeChannelStats()
    var matrixBotName: String?
    var mattermostState: NativeChannelState = .disconnected
    var mattermostStats = NativeChannelStats()
    var mattermostBotName: String?
    var mastodonState: NativeChannelState = .disconnected
    var mastodonStats = NativeChannelStats()
    var mastodonBotName: String?
    var zulipState: NativeChannelState = .disconnected
    var zulipStats = NativeChannelStats()
    var zulipBotName: String?
    var rocketchatState: NativeChannelState = .disconnected
    var rocketchatStats = NativeChannelStats()
    var rocketchatBotName: String?
    var twitchState: NativeChannelState = .disconnected
    var twitchStats = NativeChannelStats()
    var twitchBotName: String?
    var configs: [NativeChannelConfig] = []
    var lastError: String?

    // MARK: - Available Channels

    static let availableChannels: [NativeChannelDefinition] = [
        NativeChannelDefinition(
            id: "telegram",
            name: "Telegram",
            icon: "paperplane.fill",
            connectorDefinitionId: "comm.telegram"
        ),
        NativeChannelDefinition(
            id: "slack",
            name: "Slack",
            icon: "number",
            connectorDefinitionId: "comm.slack"
        ),
        NativeChannelDefinition(
            id: "discord",
            name: "Discord",
            icon: "bubble.left",
            connectorDefinitionId: "comm.discord"
        ),
        NativeChannelDefinition(
            id: "matrix",
            name: "Matrix",
            icon: "square.grid.3x3",
            connectorDefinitionId: "comm.matrix"
        ),
        NativeChannelDefinition(
            id: "mattermost",
            name: "Mattermost",
            icon: "bubble.left.and.bubble.right",
            connectorDefinitionId: "comm.mattermost"
        ),
        NativeChannelDefinition(
            id: "mastodon",
            name: "Mastodon",
            icon: "globe",
            connectorDefinitionId: "comm.mastodon"
        ),
        NativeChannelDefinition(
            id: "zulip",
            name: "Zulip",
            icon: "bubble.left.and.text.bubble.right",
            connectorDefinitionId: "comm.zulip"
        ),
        NativeChannelDefinition(
            id: "rocketchat",
            name: "Rocket.Chat",
            icon: "bubble.left.and.exclamationmark.bubble.right",
            connectorDefinitionId: "comm.rocketchat"
        ),
        NativeChannelDefinition(
            id: "twitch",
            name: "Twitch",
            icon: "play.tv",
            connectorDefinitionId: "comm.twitch"
        ),
    ]

    private var configFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw")
            .appendingPathComponent("native-channels.json")
    }

    private init() {}

    // MARK: - Lifecycle

    /// Load saved configs and start enabled channels.
    func start() {
        loadFromDisk()
        logger.info("NativeChannelsManager started with \(configs.count) config(s)")

        for config in configs where config.enabled {
            Task {
                await startChannel(config: config)
            }
        }
    }

    /// Stop all channels.
    func stop() {
        Task {
            await TelegramNativeService.shared.stop()
            await SlackNativeService.shared.stop()
            await DiscordNativeService.shared.stop()
            await MatrixNativeService.shared.stop()
            await MattermostNativeService.shared.stop()
            await MastodonNativeService.shared.stop()
            await ZulipNativeService.shared.stop()
            await RocketChatNativeService.shared.stop()
            await TwitchNativeService.shared.stop()
        }
        logger.info("NativeChannelsManager stopped all channels")
    }

    // MARK: - Channel Management

    /// Start a specific channel.
    func startChannel(config: NativeChannelConfig) async {
        let handler: @Sendable (NativeChannelMessage) async -> String? = { [weak self] message in
            await self?.handleIncomingMessage(message)
        }

        switch config.channelId {
        case "telegram":
            let service = TelegramNativeService.shared
            await service.setOnMessage(handler)
            await service.start(config: config)

        case "slack":
            let service = SlackNativeService.shared
            await service.setOnMessage(handler)
            await service.start(config: config)

        case "discord":
            let service = DiscordNativeService.shared
            await service.setOnMessage(handler)
            await service.start(config: config)

        case "matrix":
            let service = MatrixNativeService.shared
            await service.setOnMessage(handler)
            await service.start(config: config)

        case "mattermost":
            let service = MattermostNativeService.shared
            await service.setOnMessage(handler)
            await service.start(config: config)

        case "mastodon":
            let service = MastodonNativeService.shared
            await service.setOnMessage(handler)
            await service.start(config: config)

        case "zulip":
            let service = ZulipNativeService.shared
            await service.setOnMessage(handler)
            await service.start(config: config)

        case "rocketchat":
            let service = RocketChatNativeService.shared
            await service.setOnMessage(handler)
            await service.start(config: config)

        case "twitch":
            let service = TwitchNativeService.shared
            await service.setOnMessage(handler)
            await service.start(config: config)

        default:
            logger.warning("Unknown native channel: \(config.channelId)")
        }

        await refreshChannelState(config.channelId)
    }

    /// Stop a specific channel.
    func stopChannel(channelId: String) async {
        switch channelId {
        case "telegram": await TelegramNativeService.shared.stop()
        case "slack": await SlackNativeService.shared.stop()
        case "discord": await DiscordNativeService.shared.stop()
        case "matrix": await MatrixNativeService.shared.stop()
        case "mattermost": await MattermostNativeService.shared.stop()
        case "mastodon": await MastodonNativeService.shared.stop()
        case "zulip": await ZulipNativeService.shared.stop()
        case "rocketchat": await RocketChatNativeService.shared.stop()
        case "twitch": await TwitchNativeService.shared.stop()
        default: logger.warning("Unknown native channel: \(channelId)")
        }
        await refreshChannelState(channelId)
    }

    /// Add or update a channel config.
    func saveConfig(_ config: NativeChannelConfig) {
        if let index = configs.firstIndex(where: { $0.channelId == config.channelId }) {
            configs[index] = config
        } else {
            configs.append(config)
        }
        saveToDisk()
    }

    /// Remove a channel config and clear its stats/errors.
    func removeConfig(channelId: String) async {
        await stopChannel(channelId: channelId)
        await clearChannelStats(channelId: channelId)
        configs.removeAll { $0.channelId == channelId }
        saveToDisk()
    }

    /// Clear stats and error state for a channel service.
    private func clearChannelStats(channelId: String) async {
        switch channelId {
        case "telegram": await TelegramNativeService.shared.clearStats()
        case "slack": await SlackNativeService.shared.clearStats()
        case "discord": await DiscordNativeService.shared.clearStats()
        case "matrix": await MatrixNativeService.shared.clearStats()
        case "mattermost": await MattermostNativeService.shared.clearStats()
        case "mastodon": await MastodonNativeService.shared.clearStats()
        case "zulip": await ZulipNativeService.shared.clearStats()
        case "rocketchat": await RocketChatNativeService.shared.clearStats()
        case "twitch": await TwitchNativeService.shared.clearStats()
        default: break
        }
        await refreshChannelState(channelId)
    }

    /// Get config for a channel.
    func config(for channelId: String) -> NativeChannelConfig? {
        configs.first { $0.channelId == channelId }
    }

    /// Check if a channel has a valid connector configured.
    func hasValidConnector(for channelId: String) -> Bool {
        guard let definition = Self.availableChannels.first(where: { $0.id == channelId }) else { return false }
        let connectorInstances = ConnectorStore.shared.instances
        return connectorInstances.contains { $0.definitionId == definition.connectorDefinitionId }
    }

    /// Get the connector instance ID for a channel.
    func connectorInstanceId(for channelId: String) -> String? {
        guard let definition = Self.availableChannels.first(where: { $0.id == channelId }) else { return nil }
        return ConnectorStore.shared.instances.first { $0.definitionId == definition.connectorDefinitionId }?.id
    }

    // MARK: - State Sync

    /// Called by channel services when their state changes.
    func channelStateDidChange() {
        Task { @MainActor in
            for channel in Self.availableChannels {
                await refreshChannelState(channel.id)
            }
        }
    }

    private func refreshChannelState(_ channelId: String) async {
        switch channelId {
        case "telegram":
            let s = TelegramNativeService.shared
            telegramState = await s.state
            telegramStats = await s.stats
            telegramBotName = await s.botDisplayName
        case "slack":
            let s = SlackNativeService.shared
            slackState = await s.state
            slackStats = await s.stats
            slackBotName = await s.botDisplayName
        case "discord":
            let s = DiscordNativeService.shared
            discordState = await s.state
            discordStats = await s.stats
            discordBotName = await s.botDisplayName
        case "matrix":
            let s = MatrixNativeService.shared
            matrixState = await s.state
            matrixStats = await s.stats
            matrixBotName = await s.botDisplayName
        case "mattermost":
            let s = MattermostNativeService.shared
            mattermostState = await s.state
            mattermostStats = await s.stats
            mattermostBotName = await s.botDisplayName
        case "mastodon":
            let s = MastodonNativeService.shared
            mastodonState = await s.state
            mastodonStats = await s.stats
            mastodonBotName = await s.botDisplayName
        case "zulip":
            let s = ZulipNativeService.shared
            zulipState = await s.state
            zulipStats = await s.stats
            zulipBotName = await s.botDisplayName
        case "rocketchat":
            let s = RocketChatNativeService.shared
            rocketchatState = await s.state
            rocketchatStats = await s.stats
            rocketchatBotName = await s.botDisplayName
        case "twitch":
            let s = TwitchNativeService.shared
            twitchState = await s.state
            twitchStats = await s.stats
            twitchBotName = await s.botDisplayName
        default:
            break
        }
    }

    // MARK: - Message Routing

    /// Handle an incoming message from any native channel.
    /// Routes to CLIBridge and returns the AI response.
    private func handleIncomingMessage(_ message: NativeChannelMessage) async -> String? {
        let config = configs.first { $0.channelId == message.channelId }

        // Check if AI responses are enabled
        guard config?.respondWithAI != false else {
            logger.info("AI responses disabled for \(message.channelId), ignoring")
            return nil
        }

        // Resolve which CLI provider to use
        let provider: CLIProviderInfo
        if let aiId = config?.aiProviderId,
           let specific = AppState.shared.availableCLIs.first(where: { $0.id == aiId && $0.isInstalled }) {
            provider = specific
        } else if let current = AppState.shared.currentCLI {
            provider = current
        } else {
            logger.error("No CLI provider available to handle message")
            return nil
        }

        // Build system prompt with channel context
        let systemPrompt = buildSystemPrompt(config: config, message: message)

        logger.info("Routing message to \(provider.displayName)")

        // Send to CLIBridge and collect response
        var responseText = ""
        let stream = await CLIBridge.shared.send(
            message: message.text,
            provider: provider,
            sessionId: nil,
            systemPrompt: systemPrompt
        )

        for await event in stream {
            switch event {
            case .text(let text):
                responseText += text
            case .error(let err):
                logger.error("CLI error: \(err)")
                return nil
            case .done:
                break
            default:
                break
            }
        }

        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return responseText
    }

    private func buildSystemPrompt(config: NativeChannelConfig?, message: NativeChannelMessage) -> String? {
        var parts: [String] = []

        if let custom = config?.systemPrompt, !custom.isEmpty {
            parts.append(custom)
        }

        parts.append("You are responding to a message from \(message.senderName) on \(message.channelId). Keep responses concise and helpful.")

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Outbound Messaging

    /// Send an outbound message to a native channel (e.g. from cron job delivery).
    /// - Parameters:
    ///   - channelId: The native channel ID (e.g. "telegram", "slack").
    ///   - text: The message text to send.
    ///   - recipientId: Platform-specific target (chat ID, channel ID, room ID).
    /// - Returns: true if the message was sent successfully.
    func sendMessage(channelId: String, text: String, recipientId: String) async -> Bool {
        switch channelId {
        case "telegram":
            return await TelegramNativeService.shared.sendOutbound(text: text, recipientId: recipientId)
        case "slack":
            return await SlackNativeService.shared.sendOutbound(text: text, recipientId: recipientId)
        case "discord":
            return await DiscordNativeService.shared.sendOutbound(text: text, recipientId: recipientId)
        case "matrix":
            return await MatrixNativeService.shared.sendOutbound(text: text, recipientId: recipientId)
        case "mattermost":
            return await MattermostNativeService.shared.sendOutbound(text: text, recipientId: recipientId)
        case "mastodon":
            return await MastodonNativeService.shared.sendOutbound(text: text, recipientId: recipientId)
        case "zulip":
            return await ZulipNativeService.shared.sendOutbound(text: text, recipientId: recipientId)
        case "rocketchat":
            return await RocketChatNativeService.shared.sendOutbound(text: text, recipientId: recipientId)
        case "twitch":
            return await TwitchNativeService.shared.sendOutbound(text: text, recipientId: recipientId)
        default:
            logger.warning("Unknown native channel for outbound: \(channelId)")
            return false
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: configFileURL)
            configs = try JSONDecoder().decode([NativeChannelConfig].self, from: data)
        } catch {
            logger.error("Failed to load native channels config: \(error.localizedDescription)")
        }
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: configFileURL, options: .atomic)
        } catch {
            logger.error("Failed to save native channels config: \(error.localizedDescription)")
        }
    }
}
