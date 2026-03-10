import SwiftUI

/// Modal sheet that shows a parsed install plan for user review before execution.
/// Displays plan name, description, steps with commands, warnings, and action buttons.
struct InstallPlanReviewSheet: View {
    let plan: AgentInstallPlan
    let onApprove: () -> Void
    let onCancel: () -> Void

    @State private var expandedSteps: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Install Plan Review", bundle: .module))
                        .font(.headline)
                    Text(plan.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Description
                    Text(plan.description)
                        .font(.body)
                        .foregroundStyle(.primary)

                    // Warnings
                    if !plan.warnings.isEmpty {
                        warningsSection
                    }

                    // Steps
                    stepsSection

                    // Security note
                    HStack(spacing: 6) {
                        Image(systemName: "shield.checkered")
                            .font(.caption)
                        Text(String(localized: "Each command will be checked against your security rules.", bundle: .module))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
                .padding()
            }
            .frame(maxHeight: 400)

            Divider()

            // Action buttons
            HStack(spacing: 10) {
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Text(String(localized: "Cancel", bundle: .module))
                        .frame(minWidth: 80)
                }

                Spacer()

                Button {
                    onApprove()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text(String(localized: "Execute Plan", bundle: .module))
                    }
                    .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Sections

    @ViewBuilder
    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(String(localized: "Warnings", bundle: .module))
                    .font(.subheadline.weight(.semibold))
            }

            ForEach(plan.warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Steps", bundle: .module))
                .font(.subheadline.weight(.semibold))

            ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.accentColor)
                            .clipShape(Circle())

                        Text(step.description)
                            .font(.callout)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(step.command)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    if let dir = step.workingDirectory {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text(dir)
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
