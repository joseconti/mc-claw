import SwiftUI

/// Confirmation card shown in chat when the AI wants to execute a write Git action.
struct GitActionConfirmationCard: View {
    let title: String
    let details: [(label: String, value: String)]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.callout.weight(.semibold))
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                ForEach(details, id: \.label) { detail in
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

            // Actions
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module)) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(String(localized: "Confirm", bundle: .module)) {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .frame(maxWidth: 400)
    }
}
