import SwiftUI

/// Settings UI for native channels.
/// Shows connection status, configuration, and controls for each channel.
struct NativeChannelsSettingsTab: View {
    @State private var manager = NativeChannelsManager.shared
    @State private var connectorStore = ConnectorStore.shared
    @State private var showingConfig = false
    @State private var editingChannelId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Native Channels")
                .font(.headline)
            Text("Persistent bot connections that run in the background. Messages are processed by your active AI provider.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(NativeChannelsManager.availableChannels, id: \.id) { definition in
                channelCard(definition)
            }
        }
    }

    // MARK: - Channel Card

    private func channelCard(_ definition: NativeChannelDefinition) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: definition.icon)
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(definition.name)
                                .font(.body.weight(.semibold))
                            statusBadge(for: definition.id)
                        }
                        if let botName = botName(for: definition.id) {
                            Text(botName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    channelActions(definition)
                }

                // Stats (when connected)
                if channelState(for: definition.id) == .connected {
                    statsView(for: definition.id)
                }

                // Error message
                if let error = channelError(for: definition.id) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showingConfig) {
            if let channelId = editingChannelId {
                NativeChannelConfigSheet(channelId: channelId)
            }
        }
    }

    // MARK: - Status Badge

    private func statusBadge(for channelId: String) -> some View {
        let state = channelState(for: channelId)
        let (text, color): (String, Color) = switch state {
        case .disconnected: ("Disconnected", .secondary)
        case .connecting: ("Connecting...", .orange)
        case .connected: ("Connected", .green)
        case .error: ("Error", .red)
        }

        return Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Actions

    private func channelActions(_ definition: NativeChannelDefinition) -> some View {
        HStack(spacing: 8) {
            let state = channelState(for: definition.id)
            let hasConnector = manager.hasValidConnector(for: definition.id)

            if state == .connected || state == .connecting {
                Button("Stop") {
                    Task { await manager.stopChannel(channelId: definition.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if hasConnector {
                Button("Start") {
                    Task { await startChannel(definition.id) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Text("Configure connector first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                editingChannelId = definition.id
                showingConfig = true
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Stats

    private func statsView(for channelId: String) -> some View {
        let stats = channelStats(for: channelId)
        return HStack(spacing: 16) {
            statItem(label: "Received", value: "\(stats.messagesReceived)")
            statItem(label: "Sent", value: "\(stats.messagesSent)")
            if let since = stats.connectedSince {
                statItem(label: "Uptime", value: formatUptime(since: since))
            }
            if let lastMsg = stats.lastMessageAt {
                statItem(label: "Last message", value: formatRelative(lastMsg))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
        }
    }

    // MARK: - Helpers

    private func channelState(for channelId: String) -> NativeChannelState {
        switch channelId {
        case "telegram": manager.telegramState
        case "slack": manager.slackState
        case "discord": manager.discordState
        case "matrix": manager.matrixState
        case "mattermost": manager.mattermostState
        case "mastodon": manager.mastodonState
        case "zulip": manager.zulipState
        case "rocketchat": manager.rocketchatState
        case "twitch": manager.twitchState
        default: .disconnected
        }
    }

    private func channelStats(for channelId: String) -> NativeChannelStats {
        switch channelId {
        case "telegram": manager.telegramStats
        case "slack": manager.slackStats
        case "discord": manager.discordStats
        case "matrix": manager.matrixStats
        case "mattermost": manager.mattermostStats
        case "mastodon": manager.mastodonStats
        case "zulip": manager.zulipStats
        case "rocketchat": manager.rocketchatStats
        case "twitch": manager.twitchStats
        default: NativeChannelStats()
        }
    }

    private func channelError(for channelId: String) -> String? {
        channelStats(for: channelId).lastError
    }

    private func botName(for channelId: String) -> String? {
        switch channelId {
        case "telegram": manager.telegramBotName
        case "slack": manager.slackBotName
        case "discord": manager.discordBotName
        case "matrix": manager.matrixBotName
        case "mattermost": manager.mattermostBotName
        case "mastodon": manager.mastodonBotName
        case "zulip": manager.zulipBotName
        case "rocketchat": manager.rocketchatBotName
        case "twitch": manager.twitchBotName
        default: nil
        }
    }

    private func startChannel(_ channelId: String) async {
        var config = manager.config(for: channelId)
        if config == nil {
            guard let instanceId = manager.connectorInstanceId(for: channelId) else { return }
            config = NativeChannelConfig(
                channelId: channelId,
                connectorInstanceId: instanceId
            )
            manager.saveConfig(config!)
        }
        await manager.startChannel(config: config!)
    }

    private func formatUptime(since: Date) -> String {
        let interval = Date().timeIntervalSince(since)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }

    private func formatRelative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

// MARK: - Config Sheet

struct NativeChannelConfigSheet: View {
    let channelId: String
    @Environment(\.dismiss) private var dismiss
    @State private var manager = NativeChannelsManager.shared

    @State private var enabled = true
    @State private var respondWithAI = true
    @State private var autoReconnect = true
    @State private var systemPrompt = ""
    @State private var allowedChatIdsText = ""
    @State private var allowedChannelIdsText = ""
    @State private var allowedRoomIdsText = ""
    @State private var selectedProviderId: String?
    @State private var appLevelToken = ""
    @State private var dmOnly = false
    @State private var serverURL = ""
    @State private var botEmail = ""
    @State private var twitchClientId = ""
    @State private var rcUserId = ""
    @State private var replyVisibility = "unlisted"

    private static let channelsNeedingServerURL: Set<String> = ["matrix", "mattermost", "mastodon", "zulip", "rocketchat"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(channelName) Configuration")
                    .font(.headline)
                Spacer()
                Button("Done") { save(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()

            Divider()

            Form {
                Section("General") {
                    Toggle("Enabled", isOn: $enabled)
                    Toggle("Auto-reconnect on error", isOn: $autoReconnect)
                }

                // Server URL (Matrix, Mattermost, Mastodon, Zulip, Rocket.Chat)
                if Self.channelsNeedingServerURL.contains(channelId) {
                    Section("Server") {
                        TextField(serverURLPlaceholder, text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                        Text(serverURLHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Slack-specific: App-Level Token
                if channelId == "slack" {
                    Section("Socket Mode") {
                        SecureField("App-Level Token (xapp-...)", text: $appLevelToken)
                            .textFieldStyle(.roundedBorder)
                        Text("Required for Socket Mode. Create one in your Slack app's Basic Information page.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Zulip-specific: Bot Email
                if channelId == "zulip" {
                    Section("Bot Authentication") {
                        TextField("Bot email (e.g. mybot-bot@your-org.zulipchat.com)", text: $botEmail)
                            .textFieldStyle(.roundedBorder)
                        Text("The email of the bot account. API key is stored in the connector credentials.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Rocket.Chat-specific: User ID
                if channelId == "rocketchat" {
                    Section("Authentication") {
                        TextField("User ID", text: $rcUserId)
                            .textFieldStyle(.roundedBorder)
                        Text("Your Rocket.Chat user ID. Found in Administration > Users or your profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Twitch-specific: Client ID
                if channelId == "twitch" {
                    Section("Twitch App") {
                        TextField("Client ID", text: $twitchClientId)
                            .textFieldStyle(.roundedBorder)
                        Text("From your Twitch Developer Console application.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("AI Response") {
                    Toggle("Respond with AI", isOn: $respondWithAI)

                    if respondWithAI {
                        Picker("AI Provider", selection: $selectedProviderId) {
                            Text("Active provider").tag(nil as String?)
                            ForEach(AppState.shared.availableCLIs.filter(\.isInstalled), id: \.id) { cli in
                                Text(cli.displayName).tag(cli.id as String?)
                            }
                        }

                        TextField("System prompt (optional)", text: $systemPrompt, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }

                // Mastodon-specific: Reply visibility
                if channelId == "mastodon" {
                    Section("Reply Settings") {
                        Picker("Reply visibility", selection: $replyVisibility) {
                            Text("Public").tag("public")
                            Text("Unlisted").tag("unlisted")
                            Text("Followers only").tag("private")
                            Text("Direct message").tag("direct")
                        }
                    }
                }

                Section("Security") {
                    // DM only mode (Slack, Discord)
                    if channelId == "slack" || channelId == "discord" {
                        Toggle("DMs only (ignore channel messages unless mentioned)", isOn: $dmOnly)
                    }

                    // Telegram: numeric chat IDs
                    if channelId == "telegram" {
                        TextField("Allowed Chat IDs (comma-separated, empty = all)", text: $allowedChatIdsText)
                            .textFieldStyle(.roundedBorder)
                        Text("Leave empty to respond to all chats. Add specific chat IDs to restrict access.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // String channel IDs (Slack, Discord, Mattermost, Rocket.Chat, Twitch)
                    if ["slack", "discord", "mattermost", "rocketchat", "twitch"].contains(channelId) {
                        TextField("Allowed Channel IDs (comma-separated, empty = all)", text: $allowedChannelIdsText)
                            .textFieldStyle(.roundedBorder)
                        Text("Leave empty to respond in all channels. Add specific channel IDs to restrict.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Room IDs (Matrix, Zulip)
                    if ["matrix", "zulip"].contains(channelId) {
                        TextField("Allowed Room/Stream IDs (comma-separated, empty = all)", text: $allowedRoomIdsText)
                            .textFieldStyle(.roundedBorder)
                        Text(channelId == "matrix" ? "Matrix room IDs (e.g. !abc123:matrix.org)" : "Zulip stream names or IDs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 580)
        .onAppear { loadConfig() }
    }

    private var channelName: String {
        NativeChannelsManager.availableChannels.first { $0.id == channelId }?.name ?? channelId
    }

    private var serverURLPlaceholder: String {
        switch channelId {
        case "matrix": return "https://matrix.org"
        case "mattermost": return "https://your-server.mattermost.com"
        case "mastodon": return "https://mastodon.social"
        case "zulip": return "https://your-org.zulipchat.com"
        case "rocketchat": return "https://your-server.rocket.chat"
        default: return "https://..."
        }
    }

    private var serverURLHint: String {
        switch channelId {
        case "matrix": return "Your Matrix homeserver URL."
        case "mattermost": return "Your Mattermost server URL (self-hosted or cloud)."
        case "mastodon": return "Your Mastodon instance URL."
        case "zulip": return "Your Zulip server URL."
        case "rocketchat": return "Your Rocket.Chat server URL."
        default: return "Server URL."
        }
    }

    private func loadConfig() {
        guard let config = manager.config(for: channelId) else { return }
        enabled = config.enabled
        respondWithAI = config.respondWithAI
        autoReconnect = config.autoReconnect
        systemPrompt = config.systemPrompt ?? ""
        selectedProviderId = config.aiProviderId
        appLevelToken = config.appLevelToken ?? ""
        dmOnly = config.dmOnly ?? false
        serverURL = config.serverURL ?? ""
        botEmail = config.botEmail ?? ""
        twitchClientId = config.clientId ?? ""
        rcUserId = config.userId ?? ""
        replyVisibility = config.replyVisibility ?? "unlisted"
        if let ids = config.allowedChatIds, !ids.isEmpty {
            allowedChatIdsText = ids.map(String.init).joined(separator: ", ")
        }
        if let ids = config.allowedChannelIds, !ids.isEmpty {
            allowedChannelIdsText = ids.joined(separator: ", ")
        }
        if let ids = config.allowedRoomIds, !ids.isEmpty {
            allowedRoomIdsText = ids.joined(separator: ", ")
        }
    }

    private func save() {
        let allowedChatIds: [Int64]? = allowedChatIdsText.isEmpty ? nil :
            allowedChatIdsText.split(separator: ",")
                .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }

        let allowedChannelIds: [String]? = allowedChannelIdsText.isEmpty ? nil :
            allowedChannelIdsText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }

        let allowedRoomIds: [String]? = allowedRoomIdsText.isEmpty ? nil :
            allowedRoomIdsText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }

        guard let instanceId = manager.connectorInstanceId(for: channelId) ??
              manager.config(for: channelId)?.connectorInstanceId else { return }

        let config = NativeChannelConfig(
            channelId: channelId,
            connectorInstanceId: instanceId,
            enabled: enabled,
            autoReconnect: autoReconnect,
            respondWithAI: respondWithAI,
            aiProviderId: selectedProviderId,
            allowedChatIds: allowedChatIds,
            allowedChannelIds: allowedChannelIds,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
            appLevelToken: appLevelToken.isEmpty ? nil : appLevelToken,
            dmOnly: dmOnly,
            serverURL: serverURL.isEmpty ? nil : serverURL,
            botEmail: botEmail.isEmpty ? nil : botEmail,
            clientId: twitchClientId.isEmpty ? nil : twitchClientId,
            userId: rcUserId.isEmpty ? nil : rcUserId,
            allowedRoomIds: allowedRoomIds,
            replyVisibility: channelId == "mastodon" ? replyVisibility : nil
        )
        manager.saveConfig(config)
    }
}
