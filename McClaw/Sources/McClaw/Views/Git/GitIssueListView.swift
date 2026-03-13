import SwiftUI

/// List of issues for a repository.
struct GitIssueListView: View {
    let issues: [GitIssueInfo]

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
}
