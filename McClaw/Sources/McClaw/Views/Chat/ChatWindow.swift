import SwiftUI
import McClawKit

/// Main chat window with sidebar + content area, styled like Claude Desktop.
struct ChatWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    /// Active view model for the current session.
    @State private var viewModel = ChatViewModel()
    /// Keeps view models alive per session so streaming continues in background.
    @State private var viewModels: [String: ChatViewModel] = [:]
    @State private var voiceMode = VoiceModeService.shared
    @State private var sessionStore = SessionStore.shared
    @State private var showSidebar = true
    @State private var currentSection: SidebarSection = .chats
    @State private var overlayImage: GeneratedImage?
    @State private var imageIndexStore = ImageIndexStore.shared
    @State private var installService = AgentInstallService.shared

    var body: some View {
        // Access themeManager to observe theme changes without destroying view hierarchy
        let _ = themeManager.selectedPreset
        let _ = themeManager.customColors

        ZStack {
            HStack(spacing: 0) {
                // Sidebar (collapsible, hidden in settings)
                if showSidebar && currentSection != .settings && currentSection != .help {
                    ChatSidebar(
                        currentSection: $currentSection,
                        onNewChat: newChat,
                        onSelectSession: selectSession,
                        onDeleteSession: deleteSession
                    )
                    .environment(appState)
                    .frame(width: 260)
                    .transition(.move(edge: .leading))

                    Divider()
                }

                // Main content — depends on current section
                mainContentForSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
            .environment(\.showImageOverlay, { image in
                withAnimation(.easeOut(duration: 0.25)) {
                    overlayImage = image
                }
            })

            // Full-screen image overlay
            if let image = overlayImage {
                ImageOverlayView(image: image) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        overlayImage = nil
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(minWidth: 700, minHeight: 550)
        .font(.system(size: 14))
        .animation(.easeInOut(duration: 0.2), value: showSidebar)
        .sheet(isPresented: Bindable(appState).showOnboarding) {
            OnboardingWizard()
                .environment(appState)
        }
        .sheet(item: Binding(
            get: { ExecApprovals.shared.pendingApproval },
            set: { _ in }
        )) { request in
            ExecApprovalDialog(request: request) { decision in
                CLIBridge.resolveApproval(decision)
            }
        }
        .sheet(isPresented: Binding(
            get: { installService.reviewingPlan != nil },
            set: { _ in }
        )) {
            if let plan = installService.reviewingPlan {
                InstallPlanReviewSheet(
                    plan: plan,
                    onApprove: {
                        Task { await viewModel.executeInstallPlan(plan) }
                    },
                    onCancel: {
                        installService.cancel()
                    }
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.pendingArtifactSave != nil },
            set: { _ in }
        )) {
            if let pending = viewModel.pendingArtifactSave {
                ArtifactSaveSheet(pending: pending) {
                    viewModel.pendingArtifactSave = nil
                }
                .environment(appState)
            }
        }
        .onAppear {
            viewModel.loadCurrentSession()
            if let sessionId = appState.currentSessionId {
                viewModels[sessionId] = viewModel
            }
            sessionStore.refreshIndex()
            imageIndexStore.loadCachedIndex()
            setupVoiceMode()
            processPendingMessage()
        }
        .onChange(of: appState.currentSessionId) { _, newId in
            guard let newId else { return }
            // Switch to the new session's view model
            if let cached = viewModels[newId] {
                viewModel = cached
            } else {
                let newVM = ChatViewModel()
                appState.currentSessionId = newId
                newVM.loadCurrentSession()
                viewModels[newId] = newVM
                viewModel = newVM
            }
            // Re-wire voice callbacks to the new viewModel
            wireVoiceCallbacks()
            // Process any pending message from menu bar
            processPendingMessage()
        }
        .onChange(of: appState.showSettingsInMainWindow) { _, show in
            if show {
                currentSection = .settings
                appState.showSettingsInMainWindow = false
            }
        }
        .onChange(of: appState.pendingNavigationSection) { _, section in
            if let section {
                currentSection = section
                appState.pendingNavigationSection = nil
            }
        }
        .onChange(of: appState.pendingProjectIdForNewChat) { _, projectId in
            if let projectId {
                appState.pendingProjectIdForNewChat = nil
                let sessionId = appState.currentSessionId ?? UUID().uuidString
                Task {
                    await SessionStore.shared.assignToProject(sessionId: sessionId, projectId: projectId)
                    await ProjectStore.shared.addSession(sessionId, toProject: projectId)
                }
                currentSection = .projectDetail(projectId)
            }
        }
        .task {
            let detector = CLIDetector()
            let detected = await detector.scan()
            appState.availableCLIs = detected
            if appState.currentCLI == nil,
               let first = detected.first(where: { $0.isAuthenticated }) {
                appState.currentCLIIdentifier = first.id
            }
        }
    }

    // MARK: - Main Content Router

    @ViewBuilder
    private var mainContentForSection: some View {
        switch currentSection {
        case .chats:
            HStack(spacing: 0) {
                chatContent

                // Plan detail panel (right side)
                if let planPath = appState.openPlanFilePath {
                    Divider()
                    PlanDetailPanel(filePath: planPath)
                        .environment(appState)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.snappy(duration: 0.25), value: appState.openPlanFilePath)
        case .projects, .projectDetail:
            HStack(spacing: 0) {
                ProjectsContentView(
                    currentSection: $currentSection,
                    onSelectSession: selectSession,
                    onDeleteSession: deleteSession,
                    onNewChatInProject: newChatInProject
                )

                // Plan/artifact detail panel (right side)
                if let planPath = appState.openPlanFilePath {
                    Divider()
                    PlanDetailPanel(filePath: planPath)
                        .environment(appState)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.snappy(duration: 0.25), value: appState.openPlanFilePath)
        case .schedules:
            SchedulesContentView()
        case .notifications:
            NotificationsContentView()
        case .trash:
            TrashContentView()
        case .installations:
            InstallationsContentView()
        case .git:
            GitPanelView(onNavigateToProject: { projectId in
                currentSection = .projectDetail(projectId)
            })
        case .multimedia:
            MultimediaContentView(
                onNavigateToChat: { sessionId in
                    currentSection = .chats
                    if let session = sessionStore.sessions.first(where: { $0.id == sessionId }) {
                        selectSession(session)
                    }
                },
                onShowOverlay: { image in
                    withAnimation(.easeOut(duration: 0.25)) {
                        overlayImage = image
                    }
                }
            )
        case .help:
            helpContent
        case .settings:
            settingsContent
        }
    }

    /// Settings embedded in the main window, styled like Claude Desktop.
    private var settingsContent: some View {
        VStack(spacing: 0) {
            // Back header
            HStack(spacing: 6) {
                Button {
                    currentSection = .chats
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                        Text(String(localized: "Settings"))
                            .font(.title2.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            SettingsWindow()
                .environment(appState)
        }
    }

    /// Help guide embedded in the main window.
    private var helpContent: some View {
        VStack(spacing: 0) {
            // Back header
            HStack(spacing: 6) {
                Button {
                    currentSection = .chats
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                        Text(String(localized: "help_title", bundle: .module))
                            .font(.title2.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            HelpContentView()
        }
    }

    @ViewBuilder
    private var chatContent: some View {
        VStack(spacing: 0) {
            // Top bar
            chatTopBar

            Divider()

            if viewModel.messages.isEmpty {
                // Welcome view includes its own centered input bar
                WelcomeView(
                    onSend: { text, attachments in
                        Task { await viewModel.send(text, attachments: attachments) }
                    },
                    onAbort: {
                        Task { await viewModel.abort() }
                    },
                    isWorking: viewModel.isStreaming,
                    onImageGenerate: { prompt in
                        Task { await viewModel.sendImageGeneration(prompt: prompt) }
                    },
                    onInstallPrompt: { prompt in
                        Task { await viewModel.sendInstallPrompt(prompt) }
                    }
                )
                .environment(appState)
            } else {
                // Conversation mode: messages + input at bottom
                messagesArea

                // Voice overlay
                if voiceMode.isActive {
                    Divider()
                    VoiceOverlayView()
                }

                // Input bar at bottom (compact mode)
                ChatInputBar(
                    onSend: { text, attachments in
                        Task { await viewModel.send(text, attachments: attachments) }
                    },
                    onAbort: {
                        Task { await viewModel.abort() }
                    },
                    isWorking: viewModel.isStreaming,
                    compact: true,
                    onImageGenerate: { prompt in
                        Task { await viewModel.sendImageGeneration(prompt: prompt) }
                    },
                    onInstallPrompt: { prompt in
                        Task { await viewModel.sendInstallPrompt(prompt) }
                    }
                )
                .environment(appState)
            }
        }
    }

    // MARK: - Top Bar (pill segmented control like Claude)

    @ViewBuilder
    private var chatTopBar: some View {
        HStack(spacing: 0) {
            // Sidebar toggle (with space for traffic lights when sidebar is hidden)
            Button {
                showSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Toggle sidebar")
            .padding(.leading, showSidebar ? 12 : 78) // Leave space for traffic lights

            Spacer()

            // CLI selector as pill segmented control
            cliSelector

            Spacer()

            Spacer()
                .frame(width: 16)
        }
        .padding(.vertical, 8)
    }

    @Namespace private var cliSelectorNamespace

    @ViewBuilder
    private var cliSelector: some View {
        let installedCLIs = appState.installedAIProviders
        if installedCLIs.count > 1 {
            HStack(spacing: 0) {
                ForEach(installedCLIs) { cli in
                    let isSelected = cli.id == appState.currentCLIIdentifier
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            appState.currentCLIIdentifier = cli.id
                        }
                        Task { await ConfigStore.shared.saveFromState() }
                        // Auto-start BitNet server when selected (on-demand mode)
                        if cli.id == "bitnet", !appState.bitnetAlwaysOn {
                            Task {
                                let server = BitNetServerManager.shared
                                if await !server.isRunning {
                                    let model = appState.bitnetDefaultModel ?? BitNetKit.defaultModel?.modelId ?? "BitNet-b1.58-2B-4T"
                                    let serverConfig = BitNetKit.ServerConfig(
                                        port: appState.bitnetServerPort,
                                        threads: appState.bitnetThreads,
                                        contextSize: appState.bitnetContextSize,
                                        maxTokens: appState.bitnetMaxTokens,
                                        temperature: appState.bitnetTemperature
                                    )
                                    try? await server.start(model: model, config: serverConfig, trackIdle: true)
                                } else {
                                    await server.touch()
                                }
                            }
                        }
                    } label: {
                        Text(cli.displayName)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.35))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                                        )
                                        .matchedGeometryEffect(id: "cliPill", in: cliSelectorNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.quaternary.opacity(0.5))
            .clipShape(Capsule())
            .liquidGlassCapsule()
        } else if let cli = appState.currentCLI {
            Text(cli.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(
                                message: message,
                                userAvatarImage: appState.userAvatarImage,
                                fontSize: appState.chatFontSize,
                                fontFamily: appState.chatFontFamily,
                                isLastMessage: message.id == viewModel.messages.last?.id
                            )
                            .id(message.id)
                        }
                    }
                    .frame(maxWidth: 820)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func newChat() {
        if let currentId = appState.currentSessionId {
            viewModels[currentId] = viewModel
            Task { await viewModel.flushMemoryUpdate() }
        }
        let newId = UUID().uuidString
        appState.currentSessionId = newId
        appState.planModeActive = false
        appState.openPlanFilePath = nil
        let newVM = ChatViewModel()
        viewModels[newId] = newVM
        viewModel = newVM
        wireVoiceCallbacks()
    }

    /// Create a new chat that's already assigned to a project.
    /// The pending message is already set in AppState by ProjectsContentView.
    private func newChatInProject(_ sessionId: String) {
        // Save current VM before switching
        if let currentId = appState.currentSessionId, currentId != sessionId {
            viewModels[currentId] = viewModel
            Task { await viewModel.flushMemoryUpdate() }
        }
        // Create and activate the new VM
        let newVM = ChatViewModel()
        viewModels[sessionId] = newVM
        viewModel = newVM
        wireVoiceCallbacks()
        // Set session ID last — onChange may fire but the VM is already set
        appState.currentSessionId = sessionId
        // Explicitly process the pending message (don't rely on onChange)
        processPendingMessage()
    }

    private func deleteSession(_ sessionId: String) {
        // Remove cached view model
        viewModels.removeValue(forKey: sessionId)
        // If this was the active session, switch to a new chat
        if appState.currentSessionId == sessionId {
            newChat()
        }
    }

    private func selectSession(_ session: SessionInfo) {
        if let currentId = appState.currentSessionId {
            viewModels[currentId] = viewModel
            // Flush pending memory update when switching away from a project chat
            Task { await viewModel.flushMemoryUpdate() }
        }
        appState.currentSessionId = session.id
        if let cached = viewModels[session.id] {
            viewModel = cached
        } else {
            let restored = ChatViewModel()
            appState.currentSessionId = session.id
            restored.loadCurrentSession()
            viewModels[session.id] = restored
            viewModel = restored
        }
        wireVoiceCallbacks()
    }

    // MARK: - Setup

    private func setupVoiceMode() {
        wireVoiceCallbacks()

        VoiceWakeRuntime.shared.onWakeWordDetected = {
            Task { @MainActor in
                if !VoiceModeService.shared.isActive {
                    VoiceModeService.shared.activate()
                }
            }
        }
    }

    /// Wire voice callbacks to the current viewModel.
    /// Must be called again whenever viewModel is replaced (session switch, new chat).
    private func wireVoiceCallbacks() {
        let vm = viewModel
        voiceMode.onFinalTranscript = { text in
            Task { @MainActor in
                await vm.send(text)
            }
        }

        PushToTalkService.shared.onTranscript = { text in
            Task { @MainActor in
                await vm.send(text)
            }
        }
    }

    /// Check for a pending message queued from the menu bar mini chat and send it.
    private func processPendingMessage() {
        if let imagePrompt = appState.pendingImagePrompt {
            appState.pendingImagePrompt = nil
            Task { await viewModel.sendImageGeneration(prompt: imagePrompt) }
            return
        }
        if let installPrompt = appState.pendingInstallPrompt {
            appState.pendingInstallPrompt = nil
            Task { await viewModel.sendInstallPrompt(installPrompt) }
            return
        }
        guard let message = appState.pendingMessage else { return }
        appState.pendingMessage = nil
        Task { await viewModel.send(message) }
    }

}
