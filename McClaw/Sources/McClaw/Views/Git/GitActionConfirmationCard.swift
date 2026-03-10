import SwiftUI

/// Confirmation card shown in chat when the AI wants to execute a write Git action.
/// Renders different states: pending confirmation, executing, completed, failed, cancelled.
struct GitActionConfirmationCard: View {
    let action: PendingGitAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: headerIcon)
                    .font(.callout)
                    .foregroundStyle(headerColor)
                Text(action.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(headerTextColor)
            }

            switch action.status {
            case .pendingConfirmation:
                pendingContent

            case .executing:
                executingContent

            case .completed(let output):
                completedContent(output: output)

            case .failed(let error):
                failedContent(error: error)

            case .cancelled:
                cancelledContent
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor.opacity(0.3), lineWidth: 1)
        )
        .frame(maxWidth: 400)
    }

    // MARK: - Pending Confirmation

    private var pendingContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Destructive warning
            if action.isDestructive {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(String(localized: "git_action_destructive_warning", bundle: .module))
                        .font(.caption)
                }
                .foregroundStyle(.orange)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Details
            detailsView

            // Actions
            HStack {
                Spacer()
                Button(String(localized: "git_action_cancel", bundle: .module)) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(String(localized: "git_action_confirm", bundle: .module)) {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Executing

    private var executingContent: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "git_action_executing", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Completed

    private func completedContent(output: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(String(localized: "git_action_completed", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

            if !output.isEmpty && output != "(no output)" {
                Text(output)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Failed

    private func failedContent(error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(String(localized: "git_action_failed", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Text(error)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Cancelled

    private var cancelledContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "minus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(localized: "git_action_cancelled", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared Components

    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(action.sortedDetails, id: \.label) { detail in
                HStack(alignment: .top, spacing: 8) {
                    Text(detail.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Text(detail.value)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(3)
                }
            }
        }
    }

    // MARK: - Computed Styling

    private var headerIcon: String {
        switch action.status {
        case .pendingConfirmation: return "gearshape"
        case .executing: return "gearshape"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle"
        }
    }

    private var headerColor: Color {
        switch action.status {
        case .pendingConfirmation: return .orange
        case .executing: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    private var headerTextColor: Color {
        switch action.status {
        case .cancelled: return .secondary
        default: return .primary
        }
    }

    private var borderColor: Color {
        switch action.status {
        case .pendingConfirmation: return .orange
        case .executing: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }
}
