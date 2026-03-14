import SwiftUI

/// Horizontal scrollable action bar with AI-powered repo-level actions.
/// Placed between the repo header and the tab bar in GitRepoDetailView.
struct GitRepoActionBar: View {
    let repoName: String
    let onSendToChat: (String) -> Void
    var onSetupMonitor: (() -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                actionButton(
                    label: String(localized: "git_repo_explain", bundle: .module),
                    icon: "book",
                    prompt: GitPromptTemplates.explainRepo(repoName)
                )
                actionButton(
                    label: String(localized: "git_repo_what_broke", bundle: .module),
                    icon: "exclamationmark.triangle",
                    prompt: GitPromptTemplates.whatBroke(repoName)
                )
                actionButton(
                    label: String(localized: "git_repo_changelog", bundle: .module),
                    icon: "doc.plaintext",
                    prompt: GitPromptTemplates.generateChangelog(repoName)
                )
                actionButton(
                    label: String(localized: "git_repo_health", bundle: .module),
                    icon: "heart.text.square",
                    prompt: GitPromptTemplates.healthCheck(repoName)
                )
                actionButton(
                    label: String(localized: "git_repo_security", bundle: .module),
                    icon: "lock.shield",
                    prompt: GitPromptTemplates.securityAudit(repoName)
                )
                actionButton(
                    label: String(localized: "git_repo_todos", bundle: .module),
                    icon: "checklist",
                    prompt: GitPromptTemplates.findTodos(repoName)
                )
                actionButton(
                    label: String(localized: "git_repo_what_changed", bundle: .module),
                    icon: "clock.arrow.circlepath",
                    prompt: GitPromptTemplates.whatChangedThisWeek(repoName)
                )

                if onSetupMonitor != nil {
                    Button {
                        onSetupMonitor?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bell.badge")
                                .font(.caption2)
                            Text(String(localized: "git_repo_monitor", bundle: .module))
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actionButton(label: String, icon: String, prompt: String) -> some View {
        Button {
            onSendToChat(prompt)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
