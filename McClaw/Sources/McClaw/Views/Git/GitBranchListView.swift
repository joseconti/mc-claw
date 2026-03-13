import SwiftUI

/// List of branches for a repository.
struct GitBranchListView: View {
    let branches: [GitBranch]
    let selectedBranch: GitBranch?
    let onSelect: (GitBranch) -> Void

    var body: some View {
        if branches.isEmpty {
            Text("No branches loaded", bundle: .module)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(branches) { branch in
                        branchRow(branch)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func branchRow(_ branch: GitBranch) -> some View {
        let isSelected = selectedBranch?.name == branch.name
        Button {
            onSelect(branch)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: branch.isDefault ? "circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(branch.isDefault ? .green : .secondary)

                Text(branch.name)
                    .font(.body)
                    .lineLimit(1)

                if branch.isDefault {
                    Text("default")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                if branch.isProtected {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Spacer()

                if let ab = branch.aheadBehind {
                    HStack(spacing: 4) {
                        if ab.ahead > 0 {
                            Text("↑\(ab.ahead)")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                        if ab.behind > 0 {
                            Text("↓\(ab.behind)")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
