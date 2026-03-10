import SwiftUI

/// List of issues for a repository.
struct GitIssueListView: View {
    let issues: [GitIssueInfo]
    var onSendToChat: ((String) -> Void)?

    var body: some View {
        if issues.isEmpty {
            Text("No issues", bundle: .module)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(issues) { issue in
                        issueRow(issue)
                            .contextMenu { issueContextMenu(issue) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func issueRow(_ issue: GitIssueInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: issue.state == "open" || issue.state == "opened"
                  ? "circle.circle" : "checkmark.circle")
                .font(.callout)
                .foregroundStyle(issue.state == "open" || issue.state == "opened" ? .green : .purple)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("#\(issue.number)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(issue.title)
                        .font(.body)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(issue.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(issue.labels, id: \.self) { label in
                        Text(label)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Text(issue.createdAt, style: .relative)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func issueContextMenu(_ issue: GitIssueInfo) -> some View {
        Button {
            onSendToChat?(GitPromptTemplates.analyzeIssue(issue))
        } label: {
            Label(String(localized: "git_action_analyze_issue", bundle: .module), systemImage: "magnifyingglass")
        }

        Button {
            onSendToChat?(GitPromptTemplates.suggestFixIssue(issue))
        } label: {
            Label(String(localized: "git_action_suggest_fix", bundle: .module), systemImage: "wrench")
        }

        Button {
            onSendToChat?(GitPromptTemplates.createBranchForIssue(issue))
        } label: {
            Label(String(localized: "git_action_create_branch_issue", bundle: .module), systemImage: "arrow.triangle.branch")
        }

        Divider()

        Button {
            onSendToChat?(GitPromptTemplates.closeIssue(issue))
        } label: {
            Label(String(localized: "git_action_close_issue", bundle: .module), systemImage: "xmark.circle")
        }

        Button {
            onSendToChat?(GitPromptTemplates.findRelatedIssues(issue))
        } label: {
            Label(String(localized: "git_action_find_related", bundle: .module), systemImage: "link")
        }
    }
}
