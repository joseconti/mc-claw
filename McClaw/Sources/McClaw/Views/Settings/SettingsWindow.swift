import SwiftUI
import UniformTypeIdentifiers

/// Settings window with sidebar navigation, styled like Claude Desktop.
struct SettingsWindow: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            settingsDetail
        }
        .frame(width: 800, height: 560)
    }

    // MARK: - Sidebar

    private var settingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsSection.mainSections, id: \.self) { section in
                    sidebarRow(section)
                }

                sidebarHeader("Integrations")
                ForEach(SettingsSection.integrationSections, id: \.self) { section in
                    sidebarRow(section)
                }

                sidebarHeader("Advanced")
                ForEach(SettingsSection.advancedSections, id: \.self) { section in
                    sidebarRow(section)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .frame(width: 200)
        .background(.ultraThinMaterial)
    }

    private func sidebarRow(_ section: SettingsSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            Label(section.title, systemImage: section.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    selectedSection == section
                        ? Color.accentColor.opacity(0.2)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedSection == section ? .primary : .secondary)
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.leading, 8)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    // MARK: - Detail

    private var settingsDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedSection.title)
                    .font(.title.weight(.bold))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                settingsContent
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsTab()
                .environment(appState)
        case .clis:
            CLIsSettingsTab()
                .environment(appState)
        case .mcp:
            MCPSettingsTab()
                .environment(appState)
        case .security:
            SecuritySettingsTab()
                .environment(appState)
        case .connectors:
            ConnectorsSettingsTab()
        case .channels:
            ChannelsSettingsTab()
                .environment(appState)
        case .plugins:
            PluginsSettingsTab()
                .environment(appState)
        case .skills:
            SkillsSettingsTab()
        case .voice:
            VoiceSettingsTab()
                .environment(appState)
        case .cron:
            CronSettings()
        case .remote:
            RemoteSettingsTab()
                .environment(appState)
        case .logs:
            DiagnosticsSettingsTab()
        case .advanced:
            AdvancedSettingsTab()
                .environment(appState)
        }
    }
}

// MARK: - Settings Sections

enum SettingsSection: String, Hashable, CaseIterable {
    case general, clis, mcp, security
    case connectors, channels, plugins, skills, voice, cron, remote
    case logs, advanced

    var title: String {
        switch self {
        case .general: "General"
        case .clis: "CLIs"
        case .mcp: "MCP"
        case .security: "Security"
        case .connectors: "Connectors"
        case .channels: "Channels"
        case .plugins: "Plugins"
        case .skills: "Skills"
        case .voice: "Voice"
        case .cron: "Cron"
        case .remote: "Remote"
        case .logs: "Logs"
        case .advanced: "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .clis: "terminal"
        case .mcp: "server.rack"
        case .security: "lock.shield"
        case .connectors: "cable.connector"
        case .channels: "message"
        case .plugins: "puzzlepiece"
        case .skills: "sparkles"
        case .voice: "waveform"
        case .cron: "clock.arrow.2.circlepath"
        case .remote: "network"
        case .logs: "doc.text.magnifyingglass"
        case .advanced: "wrench.and.screwdriver"
        }
    }

    static let mainSections: [SettingsSection] = [.general, .clis, .mcp, .security]
    static let integrationSections: [SettingsSection] = [.connectors, .skills, .voice]
    static let advancedSections: [SettingsSection] = [.logs, .advanced]
}

// MARK: - Settings Tabs

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var updater = UpdaterService.shared

    var body: some View {
        @Bindable var state = appState
        Form {
            Section("Profile") {
                HStack(spacing: 16) {
                    // Gravatar avatar
                    Group {
                        if let avatar = appState.userAvatarImage {
                            Image(nsImage: avatar)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.userName ?? "Set your name")
                            .font(.headline)
                            .foregroundStyle(appState.userName == nil ? .secondary : .primary)
                        Text(appState.userEmail ?? "Set your email")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                TextField("Name", text: Binding(
                    get: { state.userName ?? "" },
                    set: { state.userName = $0.isEmpty ? nil : $0 }
                ), prompt: Text("Your name"))

                TextField("Email", text: Binding(
                    get: { state.userEmail ?? "" },
                    set: { state.userEmail = $0.isEmpty ? nil : $0 }
                ), prompt: Text("your@email.com (used for Gravatar)"))

                TextField("About you", text: Binding(
                    get: { state.userDescription ?? "" },
                    set: { state.userDescription = $0.isEmpty ? nil : $0 }
                ), prompt: Text("Brief description of your work and goals"), axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("Appearance") {
                Toggle("Launch at login", isOn: $state.launchAtLogin)
                Toggle("Keep in menu bar", isOn: $state.keepInMenuBar)
                    .help("When enabled, closing or quitting McClaw hides it to the menu bar instead of terminating")
                Toggle("Show dock icon", isOn: $state.showDockIcon)
                Toggle("Icon animations", isOn: $state.iconAnimationsEnabled)
            }

            Section("Chat") {
                LabeledContent("Font size") {
                    HStack(spacing: 12) {
                        Text("A")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Slider(value: $state.chatFontSize, in: 12...24, step: 1)
                            .frame(maxWidth: 200)
                        Text("A")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                        Text("\(Int(state.chatFontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Gateway") {
                LabeledContent("Connection", value: state.connectionMode.rawValue.capitalized)
                LabeledContent("Status", value: state.gatewayStatus.rawValue.capitalized)
            }

            Section("Updates") {
                LabeledContent("Version", value: "\(updater.currentVersion) (\(updater.currentBuild))")

                Toggle("Check automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))

                HStack {
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        if updater.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Check for Updates…")
                        }
                    }
                    .disabled(!updater.canCheckForUpdates || updater.isChecking)

                    Spacer()

                    if let lastCheck = updater.lastCheckDate {
                        Text("Last: \(lastCheck, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let status = updater.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: appState.voiceWakeEnabled) { _, _ in saveConfig() }
        .onChange(of: appState.connectionMode) { _, _ in saveConfig() }
        .onChange(of: appState.canvasEnabled) { _, _ in saveConfig() }
        .onChange(of: appState.chatFontSize) { _, _ in saveConfig() }
        .onChange(of: appState.keepInMenuBar) { _, _ in saveConfig() }
        .onChange(of: appState.userName) { _, _ in saveProfileDebounced() }
        .onChange(of: appState.userEmail) { _, newEmail in
            saveProfileDebounced()
            // Fetch Gravatar when email changes
            if let email = newEmail, !email.isEmpty, email.contains("@") {
                Task {
                    let updated = await GravatarService.shared.fetchAvatar(for: email)
                    if updated {
                        appState.userAvatarImage = GravatarService.shared.cachedImage
                    }
                }
            }
        }
        .onChange(of: appState.userDescription) { _, _ in saveProfileDebounced() }
    }

    private func saveConfig() {
        Task { await ConfigStore.shared.saveFromState() }
    }

    /// Save config and sync profile to CLI config files (debounced via task).
    private func saveProfileDebounced() {
        Task {
            await ConfigStore.shared.saveFromState()
            await ProfileSyncer.syncToCLIs(
                name: appState.userName,
                email: appState.userEmail,
                description: appState.userDescription
            )
        }
    }
}

struct CLIsSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var installingCLI: String?
    @State private var installLog: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Provider CLIs")
                .font(.headline)

            ForEach(appState.availableCLIs) { cli in
                HStack {
                    VStack(alignment: .leading) {
                        Text(cli.displayName)
                            .font(.body.weight(.medium))
                        if let version = cli.version {
                            Text("v\(version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if cli.isInstalled {
                        if cli.isAuthenticated {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("Not authenticated")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Button("Install") {
                            installCLI(cli)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(installingCLI != nil)
                    }

                    if installingCLI == cli.id {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if cli.id == appState.currentCLIIdentifier {
                        Text("Default")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                Divider()
            }

            if !installLog.isEmpty {
                ScrollView {
                    Text(installLog.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 80)
                .padding(6)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button("Rescan") {
                    Task {
                        let detector = CLIDetector()
                        appState.availableCLIs = await detector.scan()
                    }
                }
                Spacer()
            }
        }
        .padding()
        .task {
            // Auto-scan if list is empty (e.g. Settings opened before scan completed)
            if appState.availableCLIs.isEmpty {
                let detector = CLIDetector()
                appState.availableCLIs = await detector.scan()
            }
        }
    }

    private func installCLI(_ cli: CLIProviderInfo) {
        installingCLI = cli.id
        installLog = []

        Task {
            let installer = CLIInstaller()
            let stream = await installer.install(provider: cli)
            for await line in stream {
                installLog.append(line)
            }
            installingCLI = nil

            // Rescan after installation
            let detector = CLIDetector()
            appState.availableCLIs = await detector.scan()
        }
    }
}

struct ChannelsSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var store = ChannelsStore.shared
    @State private var selectedChannelId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Native channels (direct connections without Gateway)
            NativeChannelsSettingsTab()

            Divider()
                .padding(.vertical, 8)

            // Gateway channels
            Text("Gateway Channels")
                .font(.headline)

            let ids = store.orderedChannelIds()

            if ids.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No Gateway channels available.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Show channels as a simple list
                ForEach(ids, id: \.self) { id in
                    channelRow(id)
                }
            }
        }
        .onAppear {
            store.start()
            ensureSelection()
        }
        .onDisappear { store.stop() }
    }

    private func channelRow(_ id: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(channelTint(id))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.resolveChannelLabel(id))
                    .font(.body.weight(.medium))
                Text(channelSummary(id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let error = channelError(id) {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }

    private func detailHeader(for id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(store.resolveChannelDetailLabel(id),
                      systemImage: store.resolveChannelSystemImage(id))
                    .font(.title3.weight(.semibold))
                statusBadge(channelSummary(id), color: channelTint(id))
                Spacer()
                channelHeaderActions(id)
            }

            if let error = channelError(id) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func channelHeaderActions(_ id: String) -> some View {
        HStack(spacing: 8) {
            if id == "whatsapp" {
                Button("Logout") {
                    Task { await store.logoutWhatsApp() }
                }
                .buttonStyle(.bordered)
                .disabled(store.whatsappBusy)
            }
            if id == "telegram" {
                Button("Logout") {
                    Task { await store.logoutTelegram() }
                }
                .buttonStyle(.bordered)
                .disabled(store.telegramBusy)
            }
            Button {
                Task { await store.refresh(probe: true) }
            } label: {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Refresh")
                }
            }
            .buttonStyle(.bordered)
            .disabled(store.isRefreshing)
        }
        .controlSize(.small)
    }

    // MARK: - WhatsApp Section

    @ViewBuilder
    private var whatsAppSection: some View {
        GroupBox("Linking") {
            VStack(alignment: .leading, spacing: 10) {
                if let message = store.whatsappLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let qr = store.whatsappLoginQrDataUrl, let image = qrImage(from: qr) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 180, height: 180)
                        .cornerRadius(8)
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await store.startWhatsAppLogin(force: false) }
                    } label: {
                        if store.whatsappBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Show QR")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.whatsappBusy)

                    Button("Relink") {
                        Task { await store.startWhatsAppLogin(force: true) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.whatsappBusy)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        configEditorSection(channelId: "whatsapp")
    }

    // MARK: - Generic Channel Section

    private func genericChannelSection(_ id: String) -> some View {
        configEditorSection(channelId: id)
    }

    @ViewBuilder
    private func configEditorSection(channelId: String) -> some View {
        GroupBox("Configuration") {
            ChannelConfigFormView(store: store, channelId: channelId)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let status = store.configStatus {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 12) {
            Button {
                Task { await store.saveConfigDraft() }
            } label: {
                if store.isSavingConfig {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Save")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isSavingConfig || !store.configDirty)

            Button("Reload") {
                Task { await store.reloadConfigDraft() }
            }
            .buttonStyle(.bordered)
            .disabled(store.isSavingConfig)

            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Helpers

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func isChannelConfigured(_ id: String) -> Bool {
        guard let snap = store.snapshot else { return false }
        guard let channelData = snap.channels[id] else { return false }
        let data = try? JSONEncoder().encode(channelData)
        if let data, let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict["configured"] as? Bool ?? false
        }
        return false
    }

    private func channelTint(_ id: String) -> Color {
        guard let snap = store.snapshot, let channelData = snap.channels[id] else { return .gray }
        let data = try? JSONEncoder().encode(channelData)
        if let data, let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let running = dict["running"] as? Bool ?? false
            let connected = dict["connected"] as? Bool ?? running
            if connected { return .green }
            let configured = dict["configured"] as? Bool ?? false
            if configured { return .orange }
        }
        return .gray
    }

    private func channelSummary(_ id: String) -> String {
        guard let snap = store.snapshot, let channelData = snap.channels[id] else { return "Unknown" }
        let data = try? JSONEncoder().encode(channelData)
        if let data, let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let running = dict["running"] as? Bool ?? false
            let connected = dict["connected"] as? Bool ?? running
            let configured = dict["configured"] as? Bool ?? false
            if connected { return "Connected" }
            if running { return "Running" }
            if configured { return "Configured" }
        }
        return "Not configured"
    }

    private func channelError(_ id: String) -> String? {
        guard let snap = store.snapshot, let channelData = snap.channels[id] else { return nil }
        let data = try? JSONEncoder().encode(channelData)
        if let data, let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict["lastError"] as? String
        }
        return nil
    }

    private func ensureSelection() {
        let ids = store.orderedChannelIds()
        if selectedChannelId == nil || !ids.contains(selectedChannelId ?? "") {
            selectedChannelId = ids.first
        }
    }

    private func qrImage(from dataUrl: String) -> NSImage? {
        guard let commaIndex = dataUrl.firstIndex(of: ",") else { return nil }
        let base64 = String(dataUrl[dataUrl.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}

struct PluginsSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var runtime = PluginRuntime.shared
    @State private var showInstallSheet = false
    @State private var installPackageName = ""
    @State private var showConfirmUninstall: PluginInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusBanner

            if runtime.plugins.isEmpty && !runtime.isLoading {
                ContentUnavailableView(
                    "No plugins installed",
                    systemImage: "puzzlepiece",
                    description: Text("Install plugins from the plugin ecosystem")
                )
            } else {
                List(runtime.plugins) { plugin in
                    PluginRow(
                        plugin: plugin,
                        isBusy: runtime.isBusy(plugin: plugin),
                        onToggle: { enabled in
                            Task { await runtime.toggle(packageName: plugin.name, enabled: enabled) }
                        },
                        onUninstall: {
                            showConfirmUninstall = plugin
                        })
                }
                .listStyle(.inset)
            }
        }
        .padding()
        .task { await runtime.refreshPlugins() }
        .sheet(isPresented: $showInstallSheet) {
            PluginInstallSheet(packageName: $installPackageName) { name in
                Task { await runtime.install(packageName: name) }
            }
        }
        .alert("Uninstall Plugin?",
               isPresented: Binding(
                get: { showConfirmUninstall != nil },
                set: { if !$0 { showConfirmUninstall = nil } }
               )) {
            Button("Cancel", role: .cancel) { showConfirmUninstall = nil }
            Button("Uninstall", role: .destructive) {
                if let plugin = showConfirmUninstall {
                    Task { await runtime.uninstall(packageName: plugin.name) }
                }
                showConfirmUninstall = nil
            }
        } message: {
            if let plugin = showConfirmUninstall {
                Text("Remove \(plugin.name)? This cannot be undone.")
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Plugins")
                .font(.headline)
            Spacer()
            if runtime.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await runtime.refreshPlugins() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            Button {
                installPackageName = ""
                showInstallSheet = true
            } label: {
                Label("Install", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let error = runtime.error {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.orange)
        } else if let message = runtime.statusMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Plugin Row

private struct PluginRow: View {
    let plugin: PluginInfo
    let isBusy: Bool
    let onToggle: (Bool) -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(plugin.name)
                        .font(.body.weight(.medium))
                    Text("v\(plugin.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(plugin.kind.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                if let desc = plugin.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if isBusy {
                ProgressView().controlSize(.small)
            }

            Toggle("", isOn: Binding(
                get: { plugin.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(isBusy)

            Button(role: .destructive) {
                onUninstall()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(isBusy)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Plugin Install Sheet

private struct PluginInstallSheet: View {
    @Binding var packageName: String
    let onInstall: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Install Plugin")
                .font(.headline)
            Text("Enter the npm package name of a compatible plugin.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. mcclaw-plugin-memory-sqlite", text: $packageName)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Install") {
                    onInstall(packageName)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(packageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }
}

struct SecuritySettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var execApprovals = ExecApprovals.shared
    @State private var permissionManager = PermissionManager.shared
    @State private var newPattern = ""
    @State private var showAddPattern = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Execution Approvals
                GroupBox("Execution Approvals") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Security Mode", selection: Binding(
                            get: { execApprovals.securityMode },
                            set: { newValue in
                                execApprovals.securityMode = newValue
                                saveConfig()
                            }
                        )) {
                            Text("Deny all").tag(ExecSecurityMode.deny)
                            Text("Ask before executing").tag(ExecSecurityMode.ask)
                            Text("Allow all").tag(ExecSecurityMode.allow)
                        }
                        .pickerStyle(.segmented)

                        Text(securityModeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Allowlist
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Allowlist")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                showAddPattern = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.borderless)
                        }

                        if execApprovals.allowList.isEmpty {
                            Text("No patterns. Commands matching allowlist patterns are auto-approved.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(execApprovals.allowList) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.pattern)
                                            .font(.system(.caption, design: .monospaced))
                                        if let lastUsed = entry.lastUsedCommand {
                                            Text("Last: \(lastUsed)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        execApprovals.removeAllowlistEntry(id: entry.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Deny List
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deny List")
                            .font(.subheadline.weight(.semibold))

                        if execApprovals.denyList.isEmpty {
                            Text("No deny rules. Deny rules block commands even in Allow All mode.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(execApprovals.denyList) { rule in
                                HStack {
                                    Text(rule.command ?? rule.pattern ?? "—")
                                        .font(.system(.caption, design: .monospaced))
                                    if let reason = rule.reason {
                                        Text("(\(reason))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        execApprovals.removeDenyRule(id: rule.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Permissions (TCC)
                GroupBox("System Permissions") {
                    VStack(spacing: 8) {
                        ForEach(PermissionKind.allCases, id: \.self) { kind in
                            SecurityPermissionRow(kind: kind, manager: permissionManager)
                            if kind != PermissionKind.allCases.last {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .onAppear {
            permissionManager.refreshAll()
        }
        .sheet(isPresented: $showAddPattern) {
            AddPatternSheet(pattern: $newPattern) { pattern in
                execApprovals.addAllowlistEntry(pattern: pattern)
                newPattern = ""
            }
        }
    }

    private var securityModeDescription: String {
        switch execApprovals.securityMode {
        case .deny: "All command execution is blocked. The AI cannot run any system commands."
        case .ask: "You'll be asked to approve each command before it runs."
        case .allow: "All commands are allowed without prompting. Use with caution."
        }
    }

    private func saveConfig() {
        execApprovals.saveToFile()
        Task { await ConfigStore.shared.saveFromState() }
    }
}

// MARK: - Permission Row

private struct SecurityPermissionRow: View {
    let kind: PermissionKind
    @State var manager: PermissionManager

    var body: some View {
        HStack {
            Image(systemName: kind.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(kind.displayName)
                .font(.caption)
            Spacer()
            statusBadge
            actionButton
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let status = statusFor(kind)
        HStack(spacing: 4) {
            Circle()
                .fill(status == .granted ? .green : status == .denied ? .red : .gray)
                .frame(width: 6, height: 6)
            Text(status.rawValue.capitalized)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        let status = statusFor(kind)
        if status != .granted {
            if kind.canRequestDirectly && status == .notDetermined {
                Button("Request") {
                    Task {
                        switch kind {
                        case .microphone: _ = await manager.requestMicrophone()
                        case .camera: _ = await manager.requestCamera()
                        case .notifications: _ = await manager.requestNotifications()
                        default: break
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            } else {
                Button("Open Settings") {
                    manager.openSystemSettings(for: kind)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
    }

    private func statusFor(_ kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .microphone: manager.microphoneStatus
        case .camera: manager.cameraStatus
        case .accessibility: manager.accessibilityStatus
        case .screenRecording: manager.screenRecordingStatus
        case .notifications: manager.notificationsStatus
        }
    }
}

// MARK: - Add Pattern Sheet

private struct AddPatternSheet: View {
    @Binding var pattern: String
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Allowlist Pattern")
                .font(.headline)

            TextField("Pattern (e.g., /usr/bin/python*)", text: $pattern)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: pattern) { _, newValue in
                    if !newValue.isEmpty {
                        if case .invalid(let reason) = ExecApprovals.validateAllowlistPattern(newValue) {
                            validationError = reason
                        } else {
                            validationError = nil
                        }
                    } else {
                        validationError = nil
                    }
                }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Use glob patterns: * matches within a directory, ** matches across directories.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add") {
                    onAdd(pattern)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pattern.isEmpty || validationError != nil)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Diagnostics Tab

struct DiagnosticsSettingsTab: View {
    @State private var appState = AppState.shared
    @State private var logContent: String = ""
    @State private var logSize: String = ""
    @State private var showExportPanel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics")
                    .font(.headline)
                Spacer()
                Text(logSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Enable/disable toggle
            HStack(spacing: 12) {
                Toggle("Enable file logging", isOn: Binding(
                    get: { appState.fileLoggingEnabled },
                    set: { newValue in
                        appState.fileLoggingEnabled = newValue
                        DiagnosticsFileLogHandler.isEnabled = newValue
                        Task { await ConfigStore.shared.saveFromState() }
                        if newValue { refreshLog() }
                    }
                ))
                .toggleStyle(.switch)

                Text("Writes to ~/.mcclaw/logs/mcclaw.log")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !appState.fileLoggingEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("File logging is disabled. Enable it to capture diagnostics for debugging.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Log viewer
            ScrollView {
                if logContent.isEmpty || logContent == "(no log file)" {
                    Text(appState.fileLoggingEnabled ? "No log entries yet. Logs will appear here as McClaw runs." : "Enable logging above to start capturing diagnostics.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)
                } else {
                    Text(logContent)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Actions
            HStack(spacing: 12) {
                Button("Refresh") { refreshLog() }
                    .buttonStyle(.bordered)

                Button("Export Log…") { showExportPanel = true }
                    .buttonStyle(.bordered)
                    .disabled(logContent.isEmpty || logContent == "(no log file)")

                Button("Clear Log") {
                    DiagnosticsFileLogHandler.clearLog()
                    refreshLog()
                }
                .buttonStyle(.bordered)
                .disabled(logContent.isEmpty || logContent == "(no log file)")

                Spacer()

                Button("Open Log Folder") {
                    NSWorkspace.shared.open(DiagnosticsFileLogHandler.logsDir)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            // Sync the static flag with AppState on appear
            DiagnosticsFileLogHandler.isEnabled = appState.fileLoggingEnabled
            refreshLog()
        }
        .fileExporter(
            isPresented: $showExportPanel,
            document: LogFileDocument(content: logContent),
            contentType: .plainText,
            defaultFilename: "mcclaw-log-\(ISO8601DateFormatter().string(from: Date())).txt"
        ) { _ in }
    }

    private func refreshLog() {
        logContent = DiagnosticsFileLogHandler.readLog(lastLines: 500)
        let bytes = DiagnosticsFileLogHandler.totalLogSize
        if bytes > 1024 * 1024 {
            logSize = String(format: "%.1f MB", Double(bytes) / 1_048_576)
        } else if bytes > 1024 {
            logSize = String(format: "%.0f KB", Double(bytes) / 1024)
        } else {
            logSize = "\(bytes) bytes"
        }
    }
}

/// Document wrapper for log export via fileExporter.
struct LogFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let content: String

    init(content: String) { self.content = content }

    init(configuration: ReadConfiguration) throws {
        content = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}

struct AdvancedSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var nodeMode = NodeMode.shared

    var body: some View {
        @Bindable var state = appState
        Form {
            Toggle("Debug pane", isOn: $state.debugPaneEnabled)

            Section("Canvas & Node") {
                Toggle("Canvas panel", isOn: $state.canvasEnabled)
                Toggle("Camera capture", isOn: $state.cameraEnabled)
                Toggle("Screen recording", isOn: $state.screenEnabled)

                if !nodeMode.capabilities.isEmpty {
                    DisclosureGroup("Node Capabilities") {
                        ForEach(nodeMode.capabilities) { cap in
                            LabeledContent(cap.id, value: cap.description)
                                .font(.caption)
                        }
                    }
                }
            }

            Section("Gateway") {
                LabeledContent("Status", value: appState.gatewayStatus.rawValue.capitalized)
                if nodeMode.isActive {
                    LabeledContent("Node ID", value: nodeMode.nodeId)
                        .font(.caption)
                }
            }
        }
        .padding()
        .onChange(of: appState.cameraEnabled) { _, newValue in
            nodeMode.cameraEnabled = newValue
            saveConfig()
        }
        .onChange(of: appState.screenEnabled) { _, newValue in
            nodeMode.screenEnabled = newValue
            saveConfig()
        }
        .onChange(of: appState.canvasEnabled) { _, _ in
            saveConfig()
        }
    }

    private func saveConfig() {
        Task { await ConfigStore.shared.saveFromState() }
    }
}
