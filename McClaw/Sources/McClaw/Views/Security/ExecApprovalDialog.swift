import SwiftUI

/// Modal dialog that shows command details and allows the user to approve, deny,
/// or always-allow a command execution.
struct ExecApprovalDialog: View {
    let request: ExecApprovalRequest
    let onDecision: (ExecApprovalDecision) -> Void

    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield")
                    .font(.title)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow this command?")
                        .font(.headline)
                    Text("Review the command details before allowing execution.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Command display
            VStack(alignment: .leading, spacing: 10) {
                // Command
                VStack(alignment: .leading, spacing: 4) {
                    Text("Command")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(request.fullCommand)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Details toggle
                DisclosureGroup("Details", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let resolution = request.resolution {
                            DetailRow(label: "Executable", value: resolution.executableName)
                            if let resolved = resolution.resolvedPath {
                                DetailRow(label: "Resolved Path", value: resolved)
                            }
                        }

                        if !request.arguments.isEmpty {
                            DetailRow(
                                label: "Arguments",
                                value: request.arguments.joined(separator: " ")
                            )
                        }

                        DetailRow(label: "Host", value: Host.current().localizedName ?? "localhost")
                    }
                    .padding(.top, 4)
                }
                .font(.caption)

                // Warning footer
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("This command runs on this machine.")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Action buttons
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    onDecision(.deny)
                } label: {
                    Text("Don't Allow")
                        .frame(minWidth: 80)
                }

                Spacer()

                Button {
                    onDecision(.allowAlways)
                } label: {
                    Text("Always Allow")
                        .frame(minWidth: 80)
                }

                Button {
                    onDecision(.allowOnce)
                } label: {
                    Text("Allow Once")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
