import SwiftUI

/// Compact mini chat content for the floating panel, styled like Claude Desktop.
/// Shows a text input + "New Chat" dropdown + status indicator.
struct MenuContentView: View {
    @Environment(AppState.self) private var appState
    @State private var text: String = ""
    @State private var imageMode: Bool = false
    @State private var installMode: Bool = false
    @State private var planMode: Bool = false
    @State private var voiceMode = VoiceModeService.shared
    @State private var selectedModelId: String?
    @State private var projectStore = ProjectStore.shared

    var body: some View {
        VStack(spacing: 0) {
            inputBar
            quickActionsRow
        }
        .frame(width: 660)
        .preferredColorScheme(.dark)
        .onChange(of: appState.currentCLIIdentifier) { _, _ in
            selectedModelId = nil
        }
        .onChange(of: voiceMode.currentTranscript) { _, transcript in
            if voiceMode.isActive {
                text = transcript
            }
        }
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var inputBar: some View {
        HStack(spacing: 12) {
            // McClaw icon
            mcclawPanelIcon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            MultiLineTextInput(
                text: $text,
                placeholder: planMode
                    ? String(localized: "Describe what you want to analyze...", bundle: .appModule)
                    : voiceMode.isActive
                        ? String(localized: "Voice Mode active...", bundle: .appModule)
                        : imageMode
                            ? String(localized: "Describe the image you want to create...", bundle: .appModule)
                            : installMode
                                ? String(localized: "Paste the install prompt here...", bundle: .appModule)
                                : String(localized: "What can I help you with?", bundle: .appModule),
                font: .systemFont(ofSize: 16),
                minHeight: 36,
                maxHeight: 120,
                onSubmit: sendAndOpen
            )
            .fixedSize(horizontal: false, vertical: true)

            Button(action: sendAndOpen) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.accentColor : Color.white.opacity(0.12))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsRow: some View {
        HStack(spacing: 6) {
            Menu {
                Button {
                    startNewChat()
                } label: {
                    Label(String(localized: "New Chat", bundle: .appModule), systemImage: "bubble.left")
                }

                Button {
                    startNewPlanChat()
                } label: {
                    Label(String(localized: "New Plan Chat", bundle: .appModule), systemImage: "binoculars")
                }

                Menu {
                    if projectStore.projects.isEmpty {
                        Text(String(localized: "No Projects", bundle: .appModule))
                    } else {
                        ForEach(projectStore.projects) { project in
                            Button {
                                startNewChatInProject(project)
                            } label: {
                                Label(project.name, systemImage: "folder")
                            }
                        }
                    }
                } label: {
                    Label(String(localized: "New Chat in Project", bundle: .appModule), systemImage: "folder.badge.plus")
                }

                Divider()

                Button {
                    openScheduleCreation()
                } label: {
                    Label(String(localized: "New Schedule", bundle: .appModule), systemImage: "clock.badge.plus")
                }

                Divider()

                Button {
                    openMainWindow()
                } label: {
                    Label(String(localized: "Open Chat Window", bundle: .appModule), systemImage: "macwindow")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "New Chat", bundle: .appModule))
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                    Image(systemName: "chevron.down")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
                .liquidGlassCapsule(interactive: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // Voice toggle (available in all modes including Plan)
            floatingVoiceButton

            if !planMode {
                // Image generation toggle (only if an image-capable CLI is installed)
                if hasImageCapableCLI {
                    floatingToggleButton(
                        icon: imageMode ? "photo.fill" : "photo",
                        label: String(localized: "Image", bundle: .appModule),
                        isActive: imageMode
                    ) {
                        imageMode.toggle()
                        if imageMode { installMode = false; planMode = false }
                    }
                }

                // Install toggle
                floatingToggleButton(
                    icon: installMode ? "square.and.arrow.down.fill" : "square.and.arrow.down",
                    label: String(localized: "Install", bundle: .appModule),
                    isActive: installMode
                ) {
                    installMode.toggle()
                    if installMode { imageMode = false; planMode = false }
                }
            }

            // Plan Mode toggle
            floatingToggleButton(
                icon: planMode ? "binoculars.fill" : "binoculars",
                label: String(localized: "Plan", bundle: .appModule),
                isActive: planMode,
                activeColor: .orange
            ) {
                planMode.toggle()
                if planMode { imageMode = false; installMode = false }
            }

            Spacer()

            // Model picker
            floatingModelPicker

            // CLI provider selector
            cliSelector
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 2)
    }

    // MARK: - Actions

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasImageCapableCLI: Bool {
        appState.availableCLIs.contains {
            $0.isInstalled && $0.isAuthenticated && $0.capabilities.supportsImageGeneration
        }
    }

    private func sendAndOpen() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newId = UUID().uuidString
        appState.currentSessionId = newId

        // Apply model override if selected
        if let modelId = selectedModelId {
            appState.chatModelOverride = modelId
        }

        // Set plan mode on AppState before opening chat
        if planMode {
            appState.planModeActive = true
            appState.pendingMessage = trimmed
        } else if imageMode {
            appState.pendingImagePrompt = trimmed
        } else if installMode {
            appState.pendingInstallPrompt = trimmed
        } else {
            appState.pendingMessage = trimmed
        }
        text = ""
        imageMode = false
        installMode = false
        planMode = false
        selectedModelId = nil

        dismissAndOpenChat()
    }

    private func startNewChat() {
        appState.currentSessionId = UUID().uuidString
        appState.pendingMessage = nil
        appState.planModeActive = false
        text = ""
        dismissAndOpenChat()
    }

    private func startNewPlanChat() {
        appState.currentSessionId = UUID().uuidString
        appState.planModeActive = true
        appState.pendingMessage = nil
        text = ""
        dismissAndOpenChat()
    }

    private func startNewChatInProject(_ project: ProjectInfo) {
        let sessionId = UUID().uuidString
        appState.currentSessionId = sessionId
        appState.pendingProjectIdForNewChat = project.id
        dismissAndOpenChat()
    }

    private func openScheduleCreation() {
        appState.pendingNavigationSection = .schedules
        dismissAndOpenChat()
    }

    private func openMainWindow() {
        dismissAndOpenChat()
    }

    private func dismissAndOpenChat() {
        appState.dismissMenuBarPanel?()
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        appState.openChatWindowAction?()
    }

    // MARK: - Panel Icon

    private var mcclawPanelIcon: Image {
        let bundle = Bundle.appModule
        // Direct path access (SPM may not resolve @2x via forResource)
        let url2x = bundle.bundleURL.appendingPathComponent("mcclaw-white@2x.png")
        if FileManager.default.fileExists(atPath: url2x.path),
           let nsImage = NSImage(contentsOf: url2x) {
            return Image(nsImage: nsImage)
        }
        if let url = bundle.url(forResource: "mcclaw-white", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "brain")
    }

    // MARK: - Voice Button

    @ViewBuilder
    private var floatingVoiceButton: some View {
        Button {
            voiceMode.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: voiceModeIcon)
                    .font(.subheadline)
                    .foregroundStyle(voiceMode.isActive ? .white : .white.opacity(0.6))
                    .symbolEffect(.pulse, isActive: voiceMode.state == .listening)
                Text(String(localized: "Voice", bundle: .appModule))
                    .font(.callout.weight(voiceMode.isActive ? .semibold : .regular))
                    .foregroundStyle(voiceMode.isActive ? .white : .white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if voiceMode.isActive {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.35))
                        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
                } else {
                    Capsule().fill(.white.opacity(0.08))
                }
            }
            .clipShape(Capsule())
            .liquidGlassCapsule(interactive: false)
        }
        .buttonStyle(.plain)
    }

    private var voiceModeIcon: String {
        switch voiceMode.state {
        case .off: "mic"
        case .listening: "mic.fill"
        case .speaking: "speaker.wave.2.fill"
        case .processing: "ellipsis"
        }
    }

    // MARK: - Toggle Button Helper

    @ViewBuilder
    private func floatingToggleButton(icon: String, label: String, isActive: Bool, activeColor: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(isActive ? .white : .white.opacity(0.6))
                Text(label)
                    .font(.callout.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if isActive {
                    Capsule()
                        .fill(activeColor.opacity(0.35))
                        .overlay(Capsule().strokeBorder(activeColor.opacity(0.5), lineWidth: 1))
                } else {
                    Capsule().fill(.white.opacity(0.08))
                }
            }
            .clipShape(Capsule())
            .liquidGlassCapsule(interactive: false)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Model Picker

    @ViewBuilder
    private var floatingModelPicker: some View {
        let models = appState.currentCLI?.supportedModels ?? []
        if !models.isEmpty {
            Menu {
                ForEach(models) { model in
                    Button {
                        selectedModelId = model.modelId
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if isActiveModel(model) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button(String(localized: "Use Default", bundle: .appModule)) {
                    selectedModelId = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(currentModelDisplay)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
                .liquidGlassCapsule(interactive: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var currentModelDisplay: String {
        let models = appState.currentCLI?.supportedModels ?? []
        if let overrideId = selectedModelId,
           let model = models.first(where: { $0.modelId == overrideId }) {
            return model.displayName
        }
        if let providerId = appState.currentCLIIdentifier,
           let defaultId = appState.defaultModels[providerId],
           let model = models.first(where: { $0.modelId == defaultId }) {
            return model.displayName
        }
        return models.first(where: { _ in true })?.displayName ?? String(localized: "Default", bundle: .appModule)
    }

    private func isActiveModel(_ model: ModelInfo) -> Bool {
        if let overrideId = selectedModelId {
            return model.modelId == overrideId
        }
        if let providerId = appState.currentCLIIdentifier,
           let defaultId = appState.defaultModels[providerId] {
            return model.modelId == defaultId
        }
        return false
    }

    // MARK: - CLI Selector

    @ViewBuilder
    private var cliSelector: some View {
        let installed = appState.installedAIProviders

        if installed.count > 1 {
            // Multiple CLIs: show as dropdown
            Menu {
                ForEach(installed) { cli in
                    Button {
                        appState.currentCLIIdentifier = cli.id
                        Task { await ConfigStore.shared.saveFromState() }
                    } label: {
                        HStack {
                            Text(cli.displayName)
                            if cli.id == appState.currentCLIIdentifier {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(appState.currentCLI?.displayName ?? "CLI")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
                .liquidGlassCapsule(interactive: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        } else if let cli = appState.currentCLI {
            // Single CLI: just show the name
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text(cli.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
