import SwiftUI
import UniformTypeIdentifiers

// MARK: - McClaw Text Field Modifier

/// Custom ViewModifier matching the chat input bar appearance.
/// Applies `.plain` style first to remove default bezel, then adds dark background with subtle border.
struct McClawTextFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func mcclawTextField() -> some View {
        modifier(McClawTextFieldModifier())
    }
}

/// Settings window with sidebar navigation, styled like Claude Desktop.
struct SettingsWindow: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSection: SettingsSection = .general

    /// Main sections filtered by hidden cloud providers.
    private var visibleMainSections: [SettingsSection] {
        SettingsSection.mainSections.filter { section in
            switch section {
            case .dashscope: !appState.hiddenProviders.contains("dashscope")
            case .ollama: !appState.hiddenProviders.contains("ollama")
            default: true
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            settingsDetail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let tab = appState.pendingSettingsTab,
               let section = SettingsSection(rawValue: tab) {
                selectedSection = section
                appState.pendingSettingsTab = nil
            }
        }
        .onChange(of: appState.pendingSettingsTab) {
            if let tab = appState.pendingSettingsTab,
               let section = SettingsSection(rawValue: tab) {
                selectedSection = section
                appState.pendingSettingsTab = nil
            }
        }
    }

    // MARK: - Sidebar

    private var settingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(visibleMainSections, id: \.self) { section in
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

                sidebarHeader("Experimental")
                ForEach(SettingsSection.experimentalSections, id: \.self) { section in
                    sidebarRow(section)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .frame(width: 200)
        .background(.ultraThinMaterial)
        .liquidGlass(cornerRadius: 0)
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
            .font(.subheadline)
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
        case .ollama:
            OllamaSettingsTab()
                .environment(appState)
        case .dashscope:
            DashScopeSettingsTab()
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
        case .nativeChannels:
            NativeChannelsSettingsTab()
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
        case .backup:
            BackupSettingsTab()
        case .advanced:
            AdvancedSettingsTab()
                .environment(appState)
        case .bitnet:
            BitNetSettingsTab()
                .environment(appState)
        }
    }
}

// MARK: - Settings Sections

enum SettingsSection: String, Hashable, CaseIterable {
    case general, clis, ollama, dashscope, mcp, security
    case connectors, channels, nativeChannels, plugins, skills, voice, cron, remote
    case logs, backup, advanced
    case bitnet

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .clis: String(localized: "CLIs")
        case .mcp: String(localized: "MCP")
        case .security: String(localized: "Security")
        case .connectors: String(localized: "Connectors")
        case .channels: String(localized: "Channels")
        case .nativeChannels: String(localized: "Native Channels")
        case .plugins: String(localized: "Plugins")
        case .skills: String(localized: "Skills")
        case .voice: String(localized: "Voice")
        case .cron: String(localized: "Cron")
        case .remote: String(localized: "Remote")
        case .logs: String(localized: "Logs")
        case .backup: String(localized: "Backup", bundle: .module)
        case .advanced: String(localized: "Advanced")
        case .ollama: String(localized: "Ollama")
        case .dashscope: String(localized: "DashScope")
        case .bitnet: String(localized: "BitNet")
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
        case .nativeChannels: "bubble.left.and.bubble.right"
        case .plugins: "puzzlepiece"
        case .skills: "sparkles"
        case .voice: "waveform"
        case .cron: "clock.arrow.2.circlepath"
        case .remote: "network"
        case .logs: "doc.text.magnifyingglass"
        case .backup: "externaldrive.badge.timemachine"
        case .advanced: "wrench.and.screwdriver"
        case .ollama: "cpu.fill"
        case .dashscope: "cloud.fill"
        case .bitnet: "cpu"
        }
    }

    static let mainSections: [SettingsSection] = [.general, .clis, .ollama, .dashscope, .mcp, .security]
    static let integrationSections: [SettingsSection] = [.connectors, .nativeChannels, .skills, .voice]
    static let advancedSections: [SettingsSection] = [.logs, .backup]
    static let experimentalSections: [SettingsSection] = [.bitnet]

    /// Map a CLI provider id to its dedicated settings section (for cloud providers).
    static func settingsSection(for providerId: String) -> SettingsSection? {
        switch providerId {
        case "dashscope": .dashscope
        case "ollama": .ollama
        default: nil
        }
    }
}

// MARK: - Settings Tabs

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var updater = UpdaterService.shared

    var body: some View {
        @Bindable var state = appState
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Profile

            sectionHeader("Profile")

            HStack(spacing: 16) {
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 12)

            TextField("Name", text: Binding(
                get: { state.userName ?? "" },
                set: { state.userName = $0.isEmpty ? nil : $0 }
            ), prompt: Text("Your name"))
                .mcclawTextField()
                .padding(.bottom, 8)

            TextField("Email", text: Binding(
                get: { state.userEmail ?? "" },
                set: { state.userEmail = $0.isEmpty ? nil : $0 }
            ), prompt: Text("your@email.com (used for Gravatar)"))
                .mcclawTextField()
                .padding(.bottom, 8)

            TextField("About you", text: Binding(
                get: { state.userDescription ?? "" },
                set: { state.userDescription = $0.isEmpty ? nil : $0 }
            ), prompt: Text("Brief description of your work and goals"), axis: .vertical)
                .mcclawTextField()
                .lineLimit(2...4)

            sectionDivider()

            // MARK: - Appearance

            sectionHeader("Appearance")

            // Theme preset selector
            Text(String(localized: "Theme"))
                .font(.callout.weight(.medium))
                .padding(.bottom, 8)

            // Dark themes
            Text(String(localized: "Dark Themes"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            HStack(spacing: 12) {
                ForEach(ThemePresetId.darkPresets, id: \.self) { preset in
                    themePresetCard(preset, selected: ThemeManager.shared.selectedPreset == preset)
                        .onTapGesture {
                            ThemeManager.shared.selectedPreset = preset
                            saveConfig()
                        }
                }
            }
            .padding(.bottom, 12)

            // Light themes
            Text(String(localized: "Light Themes"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            HStack(spacing: 12) {
                ForEach(ThemePresetId.lightPresets, id: \.self) { preset in
                    themePresetCard(preset, selected: ThemeManager.shared.selectedPreset == preset)
                        .onTapGesture {
                            ThemeManager.shared.selectedPreset = preset
                            saveConfig()
                        }
                }
            }
            .padding(.bottom, 12)

            // Custom theme
            HStack(spacing: 12) {
                themePresetCard(.custom, selected: ThemeManager.shared.selectedPreset == .custom)
                    .onTapGesture {
                        ThemeManager.shared.selectedPreset = .custom
                        saveConfig()
                    }
                Spacer()
            }
            .padding(.bottom, 16)

            // Custom color editor (only visible when custom is selected)
            if ThemeManager.shared.selectedPreset == .custom {
                customThemeEditor()
                    .padding(.bottom, 16)
            }


            // Chat font
            Text("Chat font")
                .font(.callout.weight(.medium))
                .padding(.bottom, 8)

            HStack(spacing: 16) {
                ForEach(ChatFontFamily.allCases, id: \.self) { family in
                    fontFamilyCard(family, selected: state.chatFontFamily == family)
                        .onTapGesture { state.chatFontFamily = family }
                }
            }
            .padding(.bottom, 16)

            // Font size slider
            HStack(spacing: 12) {
                Text("Font size")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("A")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(value: $state.chatFontSize, in: 12...24, step: 1)
                    .frame(maxWidth: 180)
                Text("A")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                Text("\(Int(state.chatFontSize)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.bottom, 16)

            // Font preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("McClaw — Your AI assistant")
                        .font(state.chatFontFamily.font(size: state.chatFontSize))
                    Text("The quick brown fox jumps over the lazy dog. 0123456789")
                        .font(state.chatFontFamily.font(size: state.chatFontSize))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                if state.chatFontFamily == .dyslexic {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.subheadline)
                            .foregroundStyle(.pink.opacity(0.7))
                        Text("Font: [OpenDyslexic](https://opendyslexic.org) — Thanks to Abbie Gonzalez for making reading more accessible for everyone.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
                }
            }

            sectionDivider()

            // MARK: - Behavior

            sectionHeader("Behavior")

            settingsToggleRow(
                title: "Launch at login",
                description: "Start McClaw automatically when you log in to your Mac.",
                isOn: $state.launchAtLogin
            )
            settingsToggleRow(
                title: "Keep in menu bar",
                description: "When closing the window, McClaw stays in the menu bar instead of quitting.",
                isOn: $state.keepInMenuBar
            )
            settingsToggleRow(
                title: "Show dock icon",
                description: "Display the McClaw icon in the Dock.",
                isOn: $state.showDockIcon
            )
            settingsToggleRow(
                title: "Icon animations",
                description: "Animate the menu bar icon when the AI is working.",
                isOn: $state.iconAnimationsEnabled
            )

            sectionDivider()

            // MARK: - Features

            sectionHeader("Features")

            settingsToggleRow(
                title: "Canvas panel",
                description: "Enable the Canvas panel for visual AI interactions.",
                isOn: $state.canvasEnabled
            )
            settingsToggleRow(
                title: "Camera capture",
                description: "Allow the AI to capture photos via the camera when requested.",
                isOn: $state.cameraEnabled
            )
            settingsToggleRow(
                title: "Screen recording",
                description: "Allow the AI to capture the screen when requested.",
                isOn: $state.screenEnabled
            )
            settingsToggleRow(
                title: String(localized: "Git section", bundle: .module),
                description: String(localized: "Show a Git section in the sidebar to browse repositories from GitHub and GitLab.", bundle: .module),
                isOn: $state.gitSectionEnabled
            )

            sectionDivider()

            // MARK: - Project Memory

            sectionHeader(String(localized: "Project Memory", bundle: .module))

            Text("McClaw can automatically maintain a memory file for each project, capturing the project description, rules, decisions, and context from your conversations. The selected AI will read and update this memory after each conversation, so every new chat starts with full project knowledge.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Memory provider", bundle: .module)
                    .font(.callout.weight(.medium))

                Picker(selection: Binding(
                    get: { state.memoryProviderId ?? "__disabled__" },
                    set: { state.memoryProviderId = $0 == "__disabled__" ? nil : $0 }
                )) {
                    Text("Disabled", bundle: .module).tag("__disabled__")
                    ForEach(appState.installedAIProviders) { cli in
                        Text(cli.displayName).tag(cli.id)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 250)
            }
            .padding(.bottom, 8)

            settingsToggleRow(
                title: String(localized: "Auto-update memory", bundle: .module),
                description: String(localized: "Automatically update project memory after each conversation. Uses tokens from the selected provider.", bundle: .module),
                isOn: $state.projectMemoryAutoUpdate
            )

            sectionDivider()

            // MARK: - Updates

            sectionHeader("Updates")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(updater.currentVersion) (\(updater.currentBuild))")
                        .font(.body)
                }
                Spacer()
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
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!updater.canCheckForUpdates || updater.isChecking)
            }
            .padding(.bottom, 8)

            settingsToggleRow(
                title: "Check automatically",
                description: "Periodically check for new McClaw versions in the background.",
                isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                )
            )

            if let lastCheck = updater.lastCheckDate {
                Text("Last checked: \(lastCheck, format: .relative(presentation: .named))")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }

            if let status = updater.statusMessage {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .onChange(of: appState.voiceWakeEnabled) { _, _ in saveConfig() }
        .onChange(of: appState.canvasEnabled) { _, _ in saveConfig() }
        .onChange(of: appState.gitSectionEnabled) { _, _ in saveConfig() }
        .onChange(of: appState.cameraEnabled) { _, newValue in
            NodeMode.shared.cameraEnabled = newValue
            saveConfig()
        }
        .onChange(of: appState.screenEnabled) { _, newValue in
            NodeMode.shared.screenEnabled = newValue
            saveConfig()
        }
        .onChange(of: appState.chatFontSize) { _, _ in saveConfig() }
        .onChange(of: appState.chatFontFamily) { _, _ in saveConfig() }
        .onChange(of: appState.appColorScheme) { _, _ in saveConfig() }
        .onChange(of: appState.keepInMenuBar) { _, _ in saveConfig() }
        .onChange(of: appState.userName) { _, _ in saveProfileDebounced() }
        .onChange(of: appState.userEmail) { _, newEmail in
            saveProfileDebounced()
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

    // MARK: - Layout Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.bottom, 12)
    }

    private func sectionDivider() -> some View {
        Divider()
            .padding(.vertical, 20)
    }

    /// A toggle row with title, description, and a small switch on the trailing side.
    private func settingsToggleRow(title: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 6)
    }

    // MARK: - Color Scheme Card

    @ViewBuilder
    private func colorSchemeCard(_ scheme: AppColorScheme, selected: Bool) -> some View {
        VStack(spacing: 8) {
            // Preview card — larger like Claude
            RoundedRectangle(cornerRadius: 10)
                .fill(colorSchemePreviewBackground(scheme))
                .frame(width: 110, height: 72)
                .overlay {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colorSchemePreviewForeground(scheme))
                            .frame(width: 60, height: 7)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colorSchemePreviewForeground(scheme).opacity(0.5))
                            .frame(width: 44, height: 7)
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(colorSchemePreviewForeground(scheme).opacity(0.3))
                                .frame(width: 28, height: 14)
                            Circle()
                                .fill(.orange.opacity(0.7))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 1.5 : 1)
                }

            Text(scheme.displayName)
                .font(.subheadline)
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(scheme.displayName)
    }

    private func colorSchemePreviewBackground(_ scheme: AppColorScheme) -> Color {
        switch scheme {
        case .light: return Color(nsColor: NSColor(white: 0.95, alpha: 1.0))
        case .dark: return Color(nsColor: NSColor(white: 0.15, alpha: 1.0))
        case .auto: return Color(nsColor: NSColor(white: 0.15, alpha: 1.0))
        }
    }

    private func colorSchemePreviewForeground(_ scheme: AppColorScheme) -> Color {
        switch scheme {
        case .light: return Color(nsColor: NSColor(white: 0.2, alpha: 1.0))
        case .dark: return Color(nsColor: NSColor(white: 0.85, alpha: 1.0))
        case .auto: return Color(nsColor: NSColor(white: 0.85, alpha: 1.0))
        }
    }

    // MARK: - Font Family Card

    @ViewBuilder
    private func fontFamilyCard(_ family: ChatFontFamily, selected: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.controlBackgroundColor))
                    .frame(width: 110, height: 72)

                Text("Aa")
                    .font(fontCardPreviewFont(family))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 1.5 : 1)
            }

            Text(family.displayName)
                .font(.subheadline)
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(family.displayName)
    }

    private func fontCardPreviewFont(_ family: ChatFontFamily) -> Font {
        switch family {
        case .default:
            return .system(size: 26)
        case .serif:
            return .system(size: 26, design: .serif)
        case .mono:
            return .system(size: 26, design: .monospaced)
        case .dyslexic:
            if NSFont(name: "OpenDyslexic", size: 26) != nil {
                return .custom("OpenDyslexic", size: 26)
            }
            return .system(size: 26, design: .rounded)
        }
    }

    // MARK: - Theme Preset Card

    @ViewBuilder
    private func themePresetCard(_ preset: ThemePresetId, selected: Bool) -> some View {
        let previewColors = preset == .custom ? ThemeManager.shared.customColors : ThemePresets.colors(for: preset)

        VStack(spacing: 8) {
            // Preview card showing theme colors
            RoundedRectangle(cornerRadius: 10)
                .fill(previewColors.background.color)
                .frame(width: 110, height: 72)
                .overlay {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(previewColors.foreground.color)
                            .frame(width: 60, height: 7)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(previewColors.foreground.color.opacity(0.5))
                            .frame(width: 44, height: 7)
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(previewColors.cardBackground.color)
                                .frame(width: 28, height: 14)
                            Circle()
                                .fill(previewColors.accent.color)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            selected ? previewColors.accent.color : Color.secondary.opacity(0.25),
                            lineWidth: selected ? 2 : 1
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(previewColors.accent.color)
                            .padding(4)
                    }
                }

            HStack(spacing: 4) {
                Image(systemName: preset.iconName)
                    .font(.caption2)
                Text(preset.displayName)
                    .font(.subheadline)
            }
            .foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(preset.displayName)
    }

    // MARK: - Custom Theme Editor

    @ViewBuilder
    private func customThemeEditor() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Custom Colors"))
                .font(.callout.weight(.medium))

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 12) {
                customColorRow(String(localized: "Accent"), keyPath: \.accent)
                customColorRow(String(localized: "Background"), keyPath: \.background)
                customColorRow(String(localized: "Sidebar"), keyPath: \.sidebarBackground)
                customColorRow(String(localized: "Card"), keyPath: \.cardBackground)
                customColorRow(String(localized: "User Bubble"), keyPath: \.userBubble)
                customColorRow(String(localized: "Border"), keyPath: \.border)
                customColorRow(String(localized: "Hover"), keyPath: \.hoverBackground)
                customColorRow(String(localized: "Selection"), keyPath: \.sidebarSelection)
                customColorRow(String(localized: "Foreground"), keyPath: \.foreground)
                customColorRow(String(localized: "Secondary Text"), keyPath: \.secondaryForeground)
            }

            Button {
                ThemeManager.shared.customColors = ThemePresets.mcclawDark
                saveConfig()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text(String(localized: "Reset to Default"))
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardBackground.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func customColorRow(_ label: String, keyPath: WritableKeyPath<ThemeColors, CodableColor>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ColorPicker("", selection: Binding(
                get: {
                    ThemeManager.shared.customColors[keyPath: keyPath].color
                },
                set: { newColor in
                    if let nsColor = NSColor(newColor).usingColorSpace(.sRGB) {
                        ThemeManager.shared.customColors[keyPath: keyPath] = CodableColor(nsColor: nsColor)
                        saveConfig()
                    }
                }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 28, height: 28)

            Text(ThemeManager.shared.customColors[keyPath: keyPath].hex)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
        }
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
    @State private var uninstallingCLI: String?
    @State private var installLog: [String] = []

    private var aiProviders: [CLIProviderInfo] {
        appState.availableCLIs.filter { !$0.isToolCLI }
    }

    private var toolCLIs: [CLIProviderInfo] {
        appState.availableCLIs.filter { $0.isToolCLI }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Provider CLIs")
                .font(.headline)

            ForEach(aiProviders) { cli in
                cliRow(cli)
                Divider()
            }

            if !toolCLIs.isEmpty {
                Text("Optional Tools")
                    .font(.headline)
                    .padding(.top, 8)

                Text("Extend McClaw capabilities. These are not AI providers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(toolCLIs) { cli in
                    cliRow(cli)
                    Divider()
                }
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

    private func cliRow(_ cli: CLIProviderInfo) -> some View {
        HStack {
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text(cli.displayName)
                        .font(.body.weight(.medium))
                    if cli.isToolCLI {
                        Text("Tool")
                            .font(.subheadline)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                            .liquidGlassCapsule(interactive: false)
                    }
                }
                if let version = cli.version {
                    Text("v\(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if cli.isToolCLI && !cli.isInstalled {
                    Text("Enhances web browsing for all AI providers")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isCloudProvider(cli) {
                // Cloud providers: Install / Configure+✕ based on hiddenProviders
                if appState.hiddenProviders.contains(cli.id) {
                    // Not installed → "Install" activates and navigates to settings tab
                    Button(String(localized: "cli_install_button", bundle: .module)) {
                        activateCloudProvider(cli)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    // Installed → Configure + ✕
                    if cli.isAuthenticated {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    Button(String(localized: "cli_configure_button", bundle: .module)) {
                        appState.pendingSettingsTab = cli.id
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        deactivateCloudProvider(cli)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(String(localized: "cli_deactivate_help", bundle: .module))
                }
            } else if cli.isInstalled {
                // Regular CLI providers
                if !cli.isToolCLI {
                    if cli.isAuthenticated {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Not authenticated")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button {
                    uninstallCLI(cli)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Uninstall \(cli.displayName)")
                .disabled(installingCLI != nil || uninstallingCLI != nil)
            } else {
                Button(String(localized: "cli_install_button", bundle: .module)) {
                    installCLI(cli)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(installingCLI != nil || uninstallingCLI != nil)
            }

            if installingCLI == cli.id || uninstallingCLI == cli.id {
                ProgressView()
                    .controlSize(.small)
            }

            if !cli.isToolCLI && cli.isInstalled {
                if cli.id == appState.currentCLIIdentifier {
                    Text(String(localized: "cli_default_badge", bundle: .module))
                        .font(.subheadline)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .clipShape(Capsule())
                        .liquidGlassCapsule(interactive: false)
                } else if cli.isAuthenticated {
                    Button(String(localized: "cli_set_default_button", bundle: .module)) {
                        appState.currentCLIIdentifier = cli.id
                        Task { await ConfigStore.shared.saveFromState() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
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

    private func isCloudProvider(_ cli: CLIProviderInfo) -> Bool {
        if case .manual = cli.installMethod {
            return SettingsSection.settingsSection(for: cli.id) != nil
        }
        return false
    }

    private func activateCloudProvider(_ cli: CLIProviderInfo) {
        appState.hiddenProviders.remove(cli.id)
        Task { await ConfigStore.shared.saveFromState() }
        appState.pendingSettingsTab = cli.id
    }

    private func deactivateCloudProvider(_ cli: CLIProviderInfo) {
        // Remove stored credentials
        switch cli.id {
        case "dashscope":
            _ = DashScopeKeychainHelper.deleteAPIKey()
            appState.dashscopeAPIKeyStored = false
        default:
            break
        }
        // Hide provider tab from sidebar
        appState.hiddenProviders.insert(cli.id)
        Task { await ConfigStore.shared.saveFromState() }
    }

    private func uninstallCLI(_ cli: CLIProviderInfo) {
        uninstallingCLI = cli.id
        installLog = []

        Task {
            let installer = CLIInstaller()
            let stream = await installer.uninstall(provider: cli)
            for await line in stream {
                installLog.append(line)
            }
            uninstallingCLI = nil

            // Rescan after uninstall
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let error = channelError(id) {
                Text(error)
                    .font(.subheadline)
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
                    .font(.subheadline)
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
                        .font(.subheadline)
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
                .font(.subheadline)
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
                .font(.subheadline)
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
        .font(.subheadline)
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
            .liquidGlassCapsule(interactive: false)
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(plugin.kind.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                        .liquidGlassCapsule(interactive: false)
                }
                if let desc = plugin.description {
                    Text(desc)
                        .font(.subheadline)
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
                    .font(.subheadline)
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("e.g. mcclaw-plugin-memory-sqlite", text: $packageName)
                .mcclawTextField()
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Allowlist
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Allowlist")
                                .font(.callout.weight(.semibold))
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
                                .font(.subheadline)
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
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        execApprovals.removeAllowlistEntry(id: entry.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.subheadline)
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
                            .font(.callout.weight(.semibold))

                        if execApprovals.denyList.isEmpty {
                            Text("No deny rules. Deny rules block commands even in Allow All mode.")
                                .font(.subheadline)
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
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        execApprovals.removeDenyRule(id: rule.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.subheadline)
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
                GroupBox {
                    VStack(spacing: 8) {
                        HStack {
                            Text(String(localized: "security_system_permissions", bundle: .module))
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Button {
                                permissionManager.refreshAll()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .help(String(localized: "security_refresh_permissions_hint", bundle: .module))
                        }

                        ForEach(PermissionKind.allCases, id: \.self) { kind in
                            SecurityPermissionRow(kind: kind, manager: permissionManager)
                            if kind != PermissionKind.allCases.last {
                                Divider()
                            }
                        }

                        Text(String(localized: "security_permissions_hint", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
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
                .font(.subheadline)
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
                .font(.subheadline)
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
                .mcclawTextField()
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
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Text("Use glob patterns: * matches within a directory, ** matches across directories.")
                .font(.subheadline)
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
                    .font(.subheadline)
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
                    .font(.subheadline)
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
                                .font(.subheadline)
                        }
                    }
                }
            }

            Section("Gateway") {
                LabeledContent("Status", value: appState.gatewayStatus.rawValue.capitalized)
                if nodeMode.isActive {
                    LabeledContent("Node ID", value: nodeMode.nodeId)
                        .font(.subheadline)
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
