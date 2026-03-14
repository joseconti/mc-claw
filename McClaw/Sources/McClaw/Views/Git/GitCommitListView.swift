import SwiftUI

/// List of recent commits for a repository.
struct GitCommitListView: View {
    let commits: [GitCommitInfo]
    var onSendToChat: ((String) -> Void)?

    var body: some View {
        if commits.isEmpty {
            Text("No commits loaded", bundle: .module)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(commits) { commit in
                        commitRow(commit)
                            .contextMenu { commitContextMenu(commit) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func commitRow(_ commit: GitCommitInfo) -> some View {
        HStack(spacing: 8) {
            Text(commit.shortSha)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.message)
                    .font(.body)
                    .lineLimit(1)
                Text(commit.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(commit.date, style: .relative)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func commitContextMenu(_ commit: GitCommitInfo) -> some View {
        Button {
            onSendToChat?(GitPromptTemplates.explainCommit(commit))
        } label: {
            Label(String(localized: "git_action_explain_commit", bundle: .module), systemImage: "text.magnifyingglass")
        }

        Button {
            onSendToChat?(GitPromptTemplates.analyzeImpactCommit(commit))
        } label: {
            Label(String(localized: "git_action_analyze_impact", bundle: .module), systemImage: "waveform.path.ecg")
        }

        Divider()

        Button {
            onSendToChat?(GitPromptTemplates.revertCommit(commit))
        } label: {
            Label(String(localized: "git_action_revert_commit", bundle: .module), systemImage: "arrow.uturn.backward")
        }

        Button {
            onSendToChat?(GitPromptTemplates.cherryPickCommit(commit))
        } label: {
            Label(String(localized: "git_action_cherry_pick", bundle: .module), systemImage: "arrow.right.doc.on.clipboard")
        }
    }
}
