import SwiftUI

/// A single repository row in the Git repo list — card-like modern style.
struct GitRepoRow: View {
    let repo: GitRepoInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Repo icon
            Image(systemName: repo.isPrivate ? "lock.fill" : "arrow.triangle.branch")
                .font(.callout)
                .foregroundStyle(repo.isPrivate ? .orange : .blue)
                .frame(width: 36, height: 36)
                .background(repo.isPrivate ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Repo info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if repo.isFork {
                        Image(systemName: "tuningfork")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Metadata row
                HStack(spacing: 10) {
                    if let lang = repo.language {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(languageColor(lang))
                                .frame(width: 7, height: 7)
                            Text(lang)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if repo.starCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                            Text(verbatim: "\(repo.starCount)")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }

                    if repo.openIssueCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 8))
                            Text(verbatim: "\(repo.openIssueCount)")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }

                    Text(repo.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            // Right indicators
            VStack(alignment: .trailing, spacing: 4) {
                if repo.localPath != nil {
                    Image(systemName: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if repo.openPRCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.pull")
                            .font(.system(size: 9))
                        Text(verbatim: "\(repo.openPRCount)")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.6))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private func languageColor(_ language: String) -> Color {
        switch language.lowercased() {
        case "swift": return .orange
        case "python": return .blue
        case "javascript", "typescript": return .yellow
        case "rust": return .brown
        case "go": return .cyan
        case "ruby": return .red
        case "java", "kotlin": return .purple
        case "c", "c++", "c#": return .gray
        case "php": return .indigo
        case "html", "css": return .pink
        default: return .secondary
        }
    }
}
