import SwiftUI

/// Main Git section layout: chat always on top (collapsible), repo browser below.
///
///   ┌─────────────────────────────────────────────┐
///   │  [CLI Selector]        [Platform Selector]  │  ← Top bar
///   ├─────────────────────────────────────────────┤
///   │  [✕ repo / branch]   Chat input + messages  │  ← Chat (collapsible)
///   ├─────────────────────────────────────────────┤
///   │  Repo list  OR  Repo detail (GitHub-style)  │  ← Bottom panel
///   └─────────────────────────────────────────────┘
struct GitPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = GitPanelViewModel()
    @State private var chatViewModel = ChatViewModel()
    @State private var projectStore = ProjectStore.shared
    @Namespace private var cliSelectorNamespace

    /// Callback to navigate to a project detail view.
    var onNavigateToProject: ((String) -> Void)?

    /// Whether the chat area is collapsed.
    @State private var isChatCollapsed: Bool = false

    var body: some View {
        if viewModel.availablePlatforms.isEmpty {
            GitEmptyStateView()
                .onAppear { viewModel.detectAvailablePlatforms() }
        } else {
            VStack(spacing: 0) {
                // ── Top bar: CLI selector + Platform selector ──
                topBar
                Divider()

                // ── Chat area (collapsible) ──
                if !isChatCollapsed {
                    chatArea
                        .frame(minHeight: 140)
                    resizeHandle
                    Divider()
                }

                // ── Bottom panel: repo list or repo detail ──
                bottomPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                viewModel.detectAvailablePlatforms()
                Task { await viewModel.loadRepos() }
                // Wire sendToChat: expand chat if collapsed, then send prompt
                viewModel.onSendToChat = { [self] prompt in
                    if isChatCollapsed {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isChatCollapsed = false
                        }
                    }
                    chatViewModel.sendPrefilled(prompt)
                }
                // Wire Git session callbacks
                viewModel.onSaveGitSession = { [self] in
                    guard let sessionId = viewModel.currentGitSessionId else { return }
                    chatViewModel.persistGitSession(sessionId: sessionId)
                    if let repo = viewModel.selectedRepo {
                        SessionStore.shared.assignToGitRepo(sessionId: sessionId, repoFullName: repo.fullName)
                    }
                }
                viewModel.onLoadGitSession = { [self] sessionId in
                    chatViewModel.loadGitSession(sessionId: sessionId)
                    chatViewModel.gitContext = viewModel.gitContext
                }
                viewModel.onNewGitSession = { [self] in
                    chatViewModel.messages = []
                    if let sessionId = viewModel.currentGitSessionId {
                        chatViewModel.overrideSessionId = sessionId
                    }
                    chatViewModel.gitContext = viewModel.gitContext
                }
            }
            .onDisappear {
                // Persist current Git session when leaving the panel
                if let sessionId = viewModel.currentGitSessionId {
                    chatViewModel.persistGitSession(sessionId: sessionId)
                    if let repo = viewModel.selectedRepo {
                        SessionStore.shared.assignToGitRepo(sessionId: sessionId, repoFullName: repo.fullName)
                    }
                }
            }
            .onChange(of: viewModel.selectedPlatform) { _, _ in
                Task { await viewModel.loadRepos() }
            }
            .onChange(of: viewModel.gitContext) { _, newContext in
                chatViewModel.gitContext = newContext
            }
            .onChange(of: chatViewModel.isStreaming) { oldValue, newValue in
                // Auto-save when streaming finishes
                if oldValue && !newValue,
                   let sessionId = viewModel.currentGitSessionId {
                    chatViewModel.persistGitSession(sessionId: sessionId)
                    if let repo = viewModel.selectedRepo {
                        SessionStore.shared.assignToGitRepo(sessionId: sessionId, repoFullName: repo.fullName)
                        viewModel.loadSessionsForRepo(repo.fullName)
                    }
                }
            }
        }
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 8) {
            // CLI selector (left)
            cliSelector

            Spacer()

            // Platform selector
            GitPlatformSelector(
                selectedPlatform: $viewModel.selectedPlatform,
                availablePlatforms: viewModel.availablePlatforms
            )

            // Quick actions menu (visible when a repo is selected)
            if let repo = viewModel.selectedRepo, viewModel.isShowingDetail {
                Menu {
                    Button {
                        viewModel.sendToChat(GitPromptTemplates.commitAssistant())
                    } label: {
                        Label(String(localized: "git_quick_commit", bundle: .module), systemImage: "checkmark.circle")
                    }
                    Button {
                        viewModel.sendToChat("Pull the latest changes from the remote for this repository.")
                    } label: {
                        Label(String(localized: "git_quick_pull", bundle: .module), systemImage: "arrow.down")
                    }
                    Button {
                        viewModel.sendToChat("Help me create a new branch. Ask me what feature or fix I'm working on and suggest a good branch name.")
                    } label: {
                        Label(String(localized: "git_quick_create_branch", bundle: .module), systemImage: "arrow.triangle.branch")
                    }
                    Divider()
                    Button {
                        viewModel.sendToChat("List all open PRs in \(repo.fullName) and give me a summary of each one. Flag any that need attention.")
                    } label: {
                        Label(String(localized: "git_quick_review_prs", bundle: .module), systemImage: "arrow.triangle.pull")
                    }
                    Button {
                        viewModel.sendToChat(GitPromptTemplates.generateChangelog(repo.fullName))
                    } label: {
                        Label(String(localized: "git_quick_changelog", bundle: .module), systemImage: "doc.plaintext")
                    }
                } label: {
                    Image(systemName: "bolt.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "git_quick_actions_title", bundle: .module))
            }

            // Refresh
            Button {
                Task { await viewModel.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoadingRepos)

            // Session history menu (visible when a repo is selected)
            if viewModel.selectedRepo != nil {
                GitSessionHistoryMenu(
                    sessions: viewModel.repoSessions,
                    currentSessionId: viewModel.currentGitSessionId,
                    onSelect: { session in
                        viewModel.switchToSession(session)
                    },
                    onNewSession: {
                        viewModel.startNewSession()
                    },
                    onDelete: { session in
                        viewModel.deleteSession(session)
                    }
                )
            }

            // Chat collapse toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isChatCollapsed.toggle()
                }
            } label: {
                Image(systemName: isChatCollapsed ? "chevron.down.circle" : "chevron.up.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isChatCollapsed
                  ? String(localized: "Show chat", bundle: .module)
                  : String(localized: "Hide chat", bundle: .module))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - CLI Selector

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
                    } label: {
                        Text(cli.displayName)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.35))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                                        )
                                        .matchedGeometryEffect(id: "gitCliPill", in: cliSelectorNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.quaternary.opacity(0.5))
            .clipShape(Capsule())
        } else if let cli = appState.currentCLI {
            Text(cli.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Chat Area

    @ViewBuilder
    private var chatArea: some View {
        VStack(spacing: 0) {
            if chatViewModel.messages.isEmpty {
                gitChatWelcome
            } else {
                gitMessagesArea
            }

            // Input bar with context chip embedded
            ChatInputBar(
                onSend: { text, attachments in
                    Task { await chatViewModel.send(text, attachments: attachments) }
                },
                onAbort: {
                    Task { await chatViewModel.abort() }
                },
                isWorking: chatViewModel.isStreaming,
                compact: true,
                contextChip: viewModel.gitContext.map { ctx in
                    AnyView(GitContextChip(context: ctx) {
                        viewModel.clearSelection()
                    })
                }
            )
            .environment(appState)
        }
    }

    // MARK: - Bottom Panel

    @ViewBuilder
    private var bottomPanel: some View {
        if viewModel.isShowingDetail, let repo = viewModel.selectedRepo {
            GitRepoDetailView(
                repo: repo,
                branches: viewModel.branches,
                pullRequests: viewModel.pullRequests,
                issues: viewModel.issues,
                commits: viewModel.recentCommits,
                selectedBranch: viewModel.selectedBranch,
                onSelectBranch: { viewModel.selectBranch($0) },
                onBack: { viewModel.hideDetail() },
                treeNodes: viewModel.treeNodes,
                onToggleDir: { viewModel.toggleDirectory($0) },
                onSelectFile: { viewModel.selectFile($0) },
                viewingFile: viewModel.viewingFile,
                fileContent: viewModel.fileContent,
                isLoadingFile: viewModel.isLoadingFile,
                onCloseFile: { viewModel.closeFileViewer() },
                onSendToChat: { prompt in viewModel.sendToChat(prompt) },
                associatedProject: viewModel.associatedProject,
                availableProjects: projectStore.projects,
                onAssociateProject: { project in
                    viewModel.associateRepo(repo, withProject: project)
                },
                onVisitProject: onNavigateToProject,
                platform: viewModel.selectedPlatform
            )
            .task { await viewModel.loadRepoDetail(repo) }
        } else {
            GitRepoListView(viewModel: viewModel)
        }
    }

    // MARK: - Git Chat Welcome

    @ViewBuilder
    private var gitChatWelcome: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)

            if viewModel.gitContext != nil {
                Text("Ask anything about this repository", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a repository below to start", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Messages Area

    @ViewBuilder
    private var gitMessagesArea: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(chatViewModel.messages) { message in
                            MessageBubbleView(
                                message: message,
                                userAvatarImage: appState.userAvatarImage,
                                fontSize: appState.chatFontSize,
                                fontFamily: appState.chatFontFamily,
                                isLastMessage: message.id == chatViewModel.messages.last?.id,
                                onConfirmGitAction: { msgId, actId in
                                    chatViewModel.confirmGitAction(messageId: msgId, actionId: actId)
                                },
                                onCancelGitAction: { msgId, actId in
                                    chatViewModel.cancelGitAction(messageId: msgId, actionId: actId)
                                }
                            )
                            .id(message.id)
                        }
                    }
                    .frame(maxWidth: 820, minHeight: geometry.size.height, alignment: .bottom)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
            }
            .onChange(of: chatViewModel.messages.count) { _, _ in
                if let last = chatViewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Resize Handle

    @ViewBuilder
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in }
            )
    }
}
