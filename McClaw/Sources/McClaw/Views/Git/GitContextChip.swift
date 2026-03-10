import SwiftUI

/// Context chip shown in the ChatInputBar when a Git repo/branch is selected.
/// Displays `repo-name / branch` with a dismiss button.
struct GitContextChip: View {
    let context: GitContext
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\(repoShortName) / \(context.branch)")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            if context.localPath != nil {
                Image(systemName: "internaldrive")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .help(String(localized: "Cloned locally", bundle: .module))
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var repoShortName: String {
        // Show only repo name, not full owner/repo
        context.repoFullName.components(separatedBy: "/").last ?? context.repoFullName
    }
}
