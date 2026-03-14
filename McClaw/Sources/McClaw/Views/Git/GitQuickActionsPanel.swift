import SwiftUI

/// Floating quick actions panel shown when a repo is selected and the chat is collapsed.
/// Provides common Git operations that expand the chat and send a prompt.
struct GitQuickActionsPanel: View {
    let repoName: String
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick Actions", bundle: .module)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                quickActionRow(
                    icon: "checkmark.circle",
                    label: String(localized: "git_quick_commit", bundle: .module),
                    prompt: GitPromptTemplates.commitAssistant()
                )
                quickActionRow(
                    icon: "arrow.down",
                    label: String(localized: "git_quick_pull", bundle: .module),
                    prompt: "Pull the latest changes from the remote for this repository."
                )
                quickActionRow(
                    icon: "arrow.triangle.branch",
                    label: String(localized: "git_quick_create_branch", bundle: .module),
                    prompt: "Help me create a new branch. Ask me what feature or fix I'm working on and suggest a good branch name."
                )
                quickActionRow(
                    icon: "arrow.triangle.pull",
                    label: String(localized: "git_quick_review_prs", bundle: .module),
                    prompt: "List all open PRs in \(repoName) and give me a summary of each one. Flag any that need attention."
                )
                quickActionRow(
                    icon: "doc.plaintext",
                    label: String(localized: "git_quick_changelog", bundle: .module),
                    prompt: GitPromptTemplates.generateChangelog(repoName)
                )
            }
        }
        .frame(width: 220)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    @ViewBuilder
    private func quickActionRow(icon: String, label: String, prompt: String) -> some View {
        Button {
            onAction(prompt)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.callout)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
