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
        }
        logger.info("NativeChannelsManager stopped all channels")
    }

    // MARK: - Channel Management

    /// Start a specific channel.
    func startChannel(config: NativeChannelConfig) async {
        switch config.channelId {
        case "telegram":
            let service = TelegramNativeService.shared
            await service.setOnMessage { [weak self] message in
                await self?.handleIncomingMessage(message)
            }
            await service.start(config: config)
            await refreshTelegramState()

        case "slack":
            let service = SlackNativeService.shared
            await service.setOnMessage { [weak self] message in
                await self?.handleIncomingMessage(message)
            }
            await service.start(config: config)
            await refreshSlackState()

        default:
            logger.warning("Unknown native channel: \(config.channelId)")
        }
    }

    /// Stop a specific channel.
    func stopChannel(channelId: String) async {
        switch channelId {
        case "telegram":
            await TelegramNativeService.shared.stop()
            await refreshTelegramState()

        case "slack":
            await SlackNativeService.shared.stop()
            await refreshSlackState()

        default:
            logger.warning("Unknown native channel: \(channelId)")
        }
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

    /// Remove a channel config.
    func removeConfig(channelId: String) async {
        await stopChannel(channelId: channelId)
        configs.removeAll { $0.channelId == channelId }
        saveToDisk()
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
            await refreshTelegramState()
            await refreshSlackState()
        }
    }

    private func refreshTelegramState() async {
        let service = TelegramNativeService.shared
        telegramState = await service.state
        telegramStats = await service.stats
        telegramBotName = await service.botDisplayName
    }

    private func refreshSlackState() async {
        let service = SlackNativeService.shared
        slackState = await service.state
        slackStats = await service.stats
        slackBotName = await service.botDisplayName
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
