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
                    prompt: GitPromptTemplates.pullLatest()
                )
                quickActionRow(
                    icon: "arrow.triangle.branch",
                    label: String(localized: "git_quick_create_branch", bundle: .module),
                    prompt: GitPromptTemplates.createBranch()
                )
                quickActionRow(
                    icon: "arrow.triangle.pull",
                    label: String(localized: "git_quick_review_prs", bundle: .module),
                    prompt: GitPromptTemplates.reviewOpenPRs(repoName)
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
