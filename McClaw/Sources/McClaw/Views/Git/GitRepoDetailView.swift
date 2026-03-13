import SwiftUI

/// GitHub-style repository detail view with Code, Issues, PRs, and Commits tabs.
/// Code tab shows split panel: expandable file tree (left) + file content viewer (right).
struct GitRepoDetailView: View {
    let repo: GitRepoInfo
    let branches: [GitBranch]
    let pullRequests: [GitPRInfo]
    let issues: [GitIssueInfo]
    let commits: [GitCommitInfo]
    let selectedBranch: GitBranch?
    let onSelectBranch: (GitBranch) -> Void
    let onBack: () -> Void

    // File tree
    let treeNodes: [FileTreeNode]
    let onToggleDir: (FileTreeNode) -> Void
    let onSelectFile: (GitFileEntry) -> Void

    // File viewer
    let viewingFile: GitFileEntry?
    let fileContent: String?
    let isLoadingFile: Bool
    let onCloseFile: () -> Void

    @State private var selectedTab: DetailTab = .code
    @State private var treePanelWidth: CGFloat = 240

    enum DetailTab: String, CaseIterable {
        case code
        case issues
        case pullRequests
        case commits

        var title: String {
            switch self {
            case .code: return String(localized: "Code", bundle: .module)
            case .issues: return String(localized: "Issues", bundle: .module)
            case .pullRequests: return String(localized: "Pull Requests", bundle: .module)
            case .commits: return String(localized: "Commits", bundle: .module)
            }
        }

        var icon: String {
            switch self {
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .issues: return "circle.circle"
            case .pullRequests: return "arrow.triangle.pull"
            case .commits: return "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: repo name + back button
            repoHeader
            Divider()

            // Branch selector + tab bar row
            HStack(spacing: 12) {
                branchSelector
                Spacer()
                tabBar
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()

            // Tab content
            tabContent
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var repoHeader: some View {
        HStack(spacing: 8) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if repo.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(repo.fullName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            if let lang = repo.language {
                Text(lang)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(Capsule())
            }

            Spacer()

            if repo.starCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "star")
                        .font(.caption2)
                    Text("\(repo.starCount)")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Branch Selector

    @ViewBuilder
    private var branchSelector: some View {
        Menu {
            ForEach(branches) { branch in
                Button {
                    onSelectBranch(branch)
                } label: {
                    HStack {
                        Text(branch.name)
                        if branch.isDefault {
                            Text("default")
                                .foregroundStyle(.secondary)
                        }
                        if branch.name == (selectedBranch?.name ?? repo.defaultBranch) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                Text(selectedBranch?.name ?? repo.defaultBranch)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.caption2)
                        Text(tab.title)
                            .font(.caption)
                        Text(countBadge(for: tab))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .code:
            codeTab
        case .issues:
            GitIssueListView(issues: issues)
        case .pullRequests:
            GitPRListView(pullRequests: pullRequests)
        case .commits:
            GitCommitListView(commits: commits)
        }
    }

    // MARK: - Code Tab (Split Panel)

    @ViewBuilder
    private var codeTab: some View {
        HStack(spacing: 0) {
            // Left: expandable file tree
            GitFileTreeView(
                nodes: treeNodes,
                selectedFilePath: viewingFile?.path,
                onToggleDir: onToggleDir,
                onSelectFile: onSelectFile
            )
            .frame(width: treePanelWidth)

            // Resize handle
            treeSplitHandle

            Divider()

            // Right: file content or welcome
            if let file = viewingFile {
                GitFileContentView(
                    file: file,
                    content: fileContent,
                    isLoading: isLoadingFile,
                    onClose: onCloseFile
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                codeWelcome
            }
        }
    }

    // MARK: - Code Welcome (no file selected)

    @ViewBuilder
    private var codeWelcome: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Select a file to view its contents", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tree Split Handle

    @ViewBuilder
    private var treeSplitHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newWidth = treePanelWidth + value.translation.width
                        treePanelWidth = max(160, min(400, newWidth))
                    }
            )
    }

    // MARK: - Helpers

    private func countBadge(for tab: DetailTab) -> String {
        let count: Int
        switch tab {
        case .code: return ""
        case .issues: count = issues.count
        case .pullRequests: count = pullRequests.count
        case .commits: count = commits.count
        }
        return count > 0 ? "\(count)" : ""
    }
}
