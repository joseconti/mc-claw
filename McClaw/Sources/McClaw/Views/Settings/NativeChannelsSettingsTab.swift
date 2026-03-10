import SwiftUI

/// Settings UI for native channels (Telegram, Slack, Discord).
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
        case .connecting: ("Connecting…", .orange)
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
        default: .disconnected
        }
    }

    private func channelStats(for channelId: String) -> NativeChannelStats {
        switch channelId {
        case "telegram": manager.telegramStats
        case "slack": manager.slackStats
        default: NativeChannelStats()
        }
    }

    private func channelError(for channelId: String) -> String? {
        switch channelId {
        case "telegram": manager.telegramStats.lastError
        case "slack": manager.slackStats.lastError
        default: nil
        }
    }

    private func botName(for channelId: String) -> String? {
        switch channelId {
        case "telegram": manager.telegramBotName
        case "slack": manager.slackBotName
        default: nil
        }
    }

    private func startChannel(_ channelId: String) async {
        // Get or create config
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
    @State private var selectedProviderId: String?
    @State private var appLevelToken = ""
    @State private var dmOnly = false

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

                Section("Security") {
                    // Slack/Discord: DM only mode
                    if channelId == "slack" {
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

                    // Slack: string channel IDs
                    if channelId == "slack" {
                        TextField("Allowed Channel IDs (comma-separated, empty = all)", text: $allowedChannelIdsText)
                            .textFieldStyle(.roundedBorder)
                        Text("Leave empty to respond in all channels. Add specific Slack channel IDs (e.g. C1234567) to restrict.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 500)
        .onAppear { loadConfig() }
    }

    private var channelName: String {
        NativeChannelsManager.availableChannels.first { $0.id == channelId }?.name ?? channelId
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
        if let ids = config.allowedChatIds, !ids.isEmpty {
            allowedChatIdsText = ids.map(String.init).joined(separator: ", ")
        }
        if let ids = config.allowedChannelIds, !ids.isEmpty {
            allowedChannelIdsText = ids.joined(separator: ", ")
        }
    }

    private func save() {
        let allowedChatIds: [Int64]? = allowedChatIdsText.isEmpty ? nil :
            allowedChatIdsText.split(separator: ",")
                .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }

        let allowedChannelIds: [String]? = allowedChannelIdsText.isEmpty ? nil :
            allowedChannelIdsText.split(separator: ",")
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
            dmOnly: dmOnly
        )
        manager.saveConfig(config)
    }
}
