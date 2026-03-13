import SwiftUI

/// List of recent commits for a repository.
struct GitCommitListView: View {
    let commits: [GitCommitInfo]

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
}
