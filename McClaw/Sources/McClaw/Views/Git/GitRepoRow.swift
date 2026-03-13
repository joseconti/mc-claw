import SwiftUI

/// A single repository row in the Git repo list.
struct GitRepoRow: View {
    let repo: GitRepoInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if repo.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if repo.isFork {
                        Image(systemName: "tuningfork")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    if let lang = repo.language {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(languageColor(lang))
                                .frame(width: 8, height: 8)
                            Text(lang)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if repo.starCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                            Text("\(repo.starCount)")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }

                    Text(repo.updatedAt, style: .relative)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if repo.openPRCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.pull")
                        .font(.caption2)
                    Text("\(repo.openPRCount)")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
