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
    @Namespace private var cliSelectorNamespace

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
            }
            .onChange(of: viewModel.selectedPlatform) { _, _ in
                Task { await viewModel.loadRepos() }
            }
            .onChange(of: viewModel.gitContext) { _, newContext in
                chatViewModel.gitContext = newContext
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

            // Context chip + Input bar
            VStack(spacing: 4) {
                if let ctx = viewModel.gitContext {
                    HStack {
                        GitContextChip(context: ctx) {
                            viewModel.clearSelection()
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }

                ChatInputBar(
                    onSend: { text, attachments in
                        Task { await chatViewModel.send(text, attachments: attachments) }
                    },
                    onAbort: {
                        Task { await chatViewModel.abort() }
                    },
                    isWorking: chatViewModel.isStreaming,
                    compact: true
                )
                .environment(appState)
            }
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
                onCloseFile: { viewModel.closeFileViewer() }
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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chatViewModel.messages) { message in
                        MessageBubbleView(
                            message: message,
                            userAvatarImage: appState.userAvatarImage,
                            fontSize: appState.chatFontSize,
                            fontFamily: appState.chatFontFamily,
                            isLastMessage: message.id == chatViewModel.messages.last?.id
                        )
                        .id(message.id)
                    }
                }
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
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
