import SwiftUI

/// List of pull requests / merge requests for a repository.
struct GitPRListView: View {
    let pullRequests: [GitPRInfo]

    var body: some View {
        if pullRequests.isEmpty {
            Text("No pull requests", bundle: .module)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(pullRequests) { pr in
                        prRow(pr)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func prRow(_ pr: GitPRInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.pull")
                .font(.callout)
                .foregroundStyle(prColor(pr.state))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("#\(pr.number)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(pr.title)
                        .font(.body)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(pr.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(pr.sourceBranch) → \(pr.targetBranch)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let review = pr.reviewState {
                reviewBadge(review)
            }

            Text(pr.updatedAt, style: .relative)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func prColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "open", "opened": return .green
        case "merged": return .purple
        case "closed": return .red
        default: return .secondary
        }
    }

    @ViewBuilder
    private func reviewBadge(_ review: String) -> some View {
        let (icon, color): (String, Color) = {
            switch review.lowercased() {
            case "approved": return ("checkmark.circle.fill", .green)
            case "changes_requested": return ("exclamationmark.triangle.fill", .orange)
            default: return ("clock", .secondary)
            }
        }()

        Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(color)
    }
}
