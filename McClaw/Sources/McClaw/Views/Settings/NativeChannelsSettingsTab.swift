import SwiftUI

/// Settings UI for native channels.
/// Shows connection status, configuration, and controls for each channel.
struct NativeChannelsSettingsTab: View {
    @State private var manager = NativeChannelsManager.shared
    @State private var connectorStore = ConnectorStore.shared
    @State private var editingChannelId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Persistent bot connections that run in the background. Messages are processed by your active AI provider.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(NativeChannelsManager.availableChannels, id: \.id) { definition in
                channelCard(definition)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingChannelId != nil },
            set: { if !$0 { editingChannelId = nil } }
        )) {
            if let channelId = editingChannelId {
                NativeChannelConfigSheet(channelId: channelId)
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
                                .font(.subheadline)
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
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
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
            .font(.subheadline.weight(.medium))
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
            let hasConfig = manager.config(for: definition.id) != nil

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
            } else if !hasConfig {
                Text("Configure connector first")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                editingChannelId = definition.id
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Reset button — removes config, connector instance, and keychain credentials
            if hasConfig || hasConnector {
                Button {
                    Task { await resetChannel(definition) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Reset channel configuration")
            }
        }
    }

    /// Fully reset a channel: stop it, remove config, delete connector instance and keychain credentials.
    private func resetChannel(_ definition: NativeChannelDefinition) async {
        // Stop channel if running
        await manager.removeConfig(channelId: definition.id)

        // Remove associated connector instance and keychain credentials
        if let instanceId = manager.connectorInstanceId(for: definition.id) {
            connectorStore.setConnected(id: instanceId, connected: false)
            Task {
                await KeychainService.shared.deleteCredentials(instanceId: instanceId)
            }
            connectorStore.removeInstance(id: instanceId)
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
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Text(label)
                .font(.subheadline)
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
    @State private var connectorStore = ConnectorStore.shared

    // Credentials
    @State private var botToken = ""
    @State private var hasExistingToken = false

    // General
    @State private var enabled = true
    @State private var respondWithAI = true
    @State private var autoReconnect = true
    @State private var systemPrompt = ""
    @State private var selectedProviderId: String?

    // Platform-specific
    @State private var appLevelToken = ""
    @State private var dmOnly = false
    @State private var serverURL = ""
    @State private var botEmail = ""
    @State private var twitchClientId = ""
    @State private var rcUserId = ""
    @State private var replyVisibility = "unlisted"

    // Security
    @State private var allowedChatIdsText = ""
    @State private var allowedChannelIdsText = ""
    @State private var allowedRoomIdsText = ""

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
                // Credentials — always first, most important
                Section("Credentials") {
                    credentialsFields

                    if hasExistingToken && botToken.isEmpty {
                        Label("Token already configured", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }

                Section("General") {
                    Toggle("Enabled", isOn: $enabled)
                    Toggle("Auto-reconnect on error", isOn: $autoReconnect)
                }

                // Server URL (Matrix, Mattermost, Mastodon, Zulip, Rocket.Chat)
                if Self.channelsNeedingServerURL.contains(channelId) {
                    Section("Server") {
                        TextField(serverURLPlaceholder, text: $serverURL)
                            .mcclawTextField()
                        Text(serverURLHint)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Slack-specific: App-Level Token
                if channelId == "slack" {
                    Section("Socket Mode") {
                        SecureField("App-Level Token (xapp-...)", text: $appLevelToken)
                            .mcclawTextField()
                        Text("Required for Socket Mode. Create one in your Slack app's Basic Information page.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Zulip-specific: Bot Email
                if channelId == "zulip" {
                    Section("Bot Identity") {
                        TextField("Bot email (e.g. mybot-bot@your-org.zulipchat.com)", text: $botEmail)
                            .mcclawTextField()
                    }
                }

                // Rocket.Chat-specific: User ID
                if channelId == "rocketchat" {
                    Section("User Identity") {
                        TextField("User ID", text: $rcUserId)
                            .mcclawTextField()
                        Text("Found in Administration > Users or your profile.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Twitch-specific: Client ID
                if channelId == "twitch" {
                    Section("Twitch App") {
                        TextField("Client ID", text: $twitchClientId)
                            .mcclawTextField()
                        Text("From your Twitch Developer Console application.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("AI Response") {
                    Toggle("Respond with AI", isOn: $respondWithAI)

                    if respondWithAI {
                        Picker("AI Provider", selection: $selectedProviderId) {
                            Text("Active provider").tag(nil as String?)
                            ForEach(AppState.shared.installedAIProviders, id: \.id) { cli in
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
                    if channelId == "slack" || channelId == "discord" {
                        Toggle("DMs only (ignore channel messages unless mentioned)", isOn: $dmOnly)
                    }

                    if channelId == "telegram" {
                        TextField("Allowed Chat IDs (comma-separated, empty = all)", text: $allowedChatIdsText)
                            .mcclawTextField()
                        Text("Leave empty to respond to all chats. Add specific chat IDs to restrict access.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if ["slack", "discord", "mattermost", "rocketchat", "twitch"].contains(channelId) {
                        TextField("Allowed Channel IDs (comma-separated, empty = all)", text: $allowedChannelIdsText)
                            .mcclawTextField()
                        Text("Leave empty to respond in all channels. Add specific channel IDs to restrict.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if ["matrix", "zulip"].contains(channelId) {
                        TextField("Allowed Room/Stream IDs (comma-separated, empty = all)", text: $allowedRoomIdsText)
                            .mcclawTextField()
                        Text(channelId == "matrix" ? "Matrix room IDs (e.g. !abc123:matrix.org)" : "Zulip stream names or IDs")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 620)
        .onAppear { loadConfig() }
    }

    // MARK: - Credentials Fields

    @ViewBuilder
    private var credentialsFields: some View {
        switch channelId {
        case "telegram":
            SecureField("Bot Token (from @BotFather)", text: $botToken)
                .mcclawTextField()
            Text("Create a bot with @BotFather on Telegram and paste the token here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case "slack":
            SecureField("Bot Token (xoxb-...)", text: $botToken)
                .mcclawTextField()
            Text("OAuth Bot Token from your Slack app's OAuth & Permissions page.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case "discord":
            SecureField("Bot Token", text: $botToken)
                .mcclawTextField()
            Text("From the Bot section of your Discord application in the Developer Portal.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case "matrix":
            SecureField("Access Token", text: $botToken)
                .mcclawTextField()
            Text("Matrix access token. Generate one via Element or the Matrix API.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case "mattermost":
            SecureField("Personal Access Token", text: $botToken)
                .mcclawTextField()
            Text("Create a Personal Access Token in Account Settings > Security.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case "mastodon":
            SecureField("Access Token", text: $botToken)
                .mcclawTextField()
            Text("From your Mastodon instance's Development > New Application page.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case "zulip":
            SecureField("API Key", text: $botToken)
                .mcclawTextField()
            Text("Found in Settings > Your Bots on your Zulip server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case "rocketchat":
            SecureField("Auth Token", text: $botToken)
                .mcclawTextField()
            Text("Personal Access Token from Administration > My Account > Security.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case "twitch":
            SecureField("OAuth Token", text: $botToken)
                .mcclawTextField()
            Text("OAuth token with chat scopes. Generate via Twitch CLI or OAuth flow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        default:
            SecureField("API Token", text: $botToken)
                .mcclawTextField()
        }
    }

    // MARK: - Helpers

    private var channelName: String {
        NativeChannelsManager.availableChannels.first { $0.id == channelId }?.name ?? channelId
    }

    private var connectorDefinitionId: String {
        NativeChannelsManager.availableChannels.first { $0.id == channelId }?.connectorDefinitionId ?? ""
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

    // MARK: - Load

    private func loadConfig() {
        // Load channel config
        if let config = manager.config(for: channelId) {
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

        // Check if credentials already exist in Keychain
        Task {
            if let instanceId = manager.connectorInstanceId(for: channelId) {
                let creds = await KeychainService.shared.loadCredentials(instanceId: instanceId)
                await MainActor.run {
                    hasExistingToken = creds?.hasValidToken ?? false
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        let defId = connectorDefinitionId
        guard !defId.isEmpty else { return }

        // Ensure connector instance exists — create if needed
        let instanceId: String
        if let existingId = manager.connectorInstanceId(for: channelId) {
            instanceId = existingId
        } else {
            guard let newInstance = connectorStore.addInstance(definitionId: defId) else { return }
            connectorStore.setConnected(id: newInstance.id, connected: true)
            instanceId = newInstance.id
        }

        // Save credentials to Keychain if token was entered
        if !botToken.isEmpty {
            let useApiKey = ["telegram", "zulip"].contains(channelId)
            let credentials = ConnectorCredentials(
                accessToken: useApiKey ? nil : botToken,
                apiKey: useApiKey ? botToken : nil
            )
            Task {
                try? await KeychainService.shared.saveCredentials(
                    instanceId: instanceId,
                    credentials: credentials
                )
            }
            connectorStore.setConnected(id: instanceId, connected: true)
        }

        // Build config
        let allowedChatIds: [Int64]? = allowedChatIdsText.isEmpty ? nil :
            allowedChatIdsText.split(separator: ",")
                .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }

        let allowedChannelIds: [String]? = allowedChannelIdsText.isEmpty ? nil :
            allowedChannelIdsText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }

        let allowedRoomIds: [String]? = allowedRoomIdsText.isEmpty ? nil :
            allowedRoomIdsText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }

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
