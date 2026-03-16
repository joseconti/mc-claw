import SwiftUI

/// Inline view displayed in chat messages to show installation progress.
/// Observes the AgentInstallService for live step updates.
struct InstallProgressView: View {
    let planId: UUID

    @State private var installService = AgentInstallService.shared
    @State private var expandedSteps: Set<UUID> = []

    private var plan: AgentInstallPlan? {
        installService.currentPlan?.id == planId ? installService.currentPlan : nil
    }

    var body: some View {
        if let plan {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name)
                            .font(.subheadline.weight(.semibold))
                        Text(statusSummary(for: plan))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isExecuting {
                        Button {
                            installService.abortExecution()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Stop Installation", bundle: .appModule))
                    }
                }

                // Progress bar
                progressBar(for: plan)

                // Steps
                ForEach(plan.steps) { step in
                    stepRow(step)
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.cardBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    }
            }
        } else {
            // Plan no longer active — show completed summary from registry
            completedSummary
        }
    }

    // MARK: - Step Row

    @ViewBuilder
    private func stepRow(_ step: AgentInstallStep) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                stepIcon(for: step.status)
                    .frame(width: 16, height: 16)

                Text(step.description)
                    .font(.caption)
                    .foregroundStyle(step.status == .pending ? .tertiary : .primary)

                Spacer()

                if step.output != nil {
                    Button {
                        toggleExpanded(step.id)
                    } label: {
                        Image(systemName: expandedSteps.contains(step.id) ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if expandedSteps.contains(step.id), let output = step.output, !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(6)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepIcon(for status: AgentInstallStepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .awaitingApproval:
            Image(systemName: "shield.lefthalf.filled")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "forward.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .denied:
            Image(systemName: "shield.slash")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private func progressBar(for plan: AgentInstallPlan) -> some View {
        let total = plan.steps.count
        let done = plan.steps.filter { $0.status == .completed }.count
        let failed = plan.steps.filter { $0.status == .failed || $0.status == .denied }.count

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)

                if total > 0 {
                    Capsule()
                        .fill(failed > 0 ? Color.red : Color.green)
                        .frame(width: geo.size.width * CGFloat(done) / CGFloat(total))
                }
            }
        }
        .frame(height: 4)
    }

    private var isExecuting: Bool {
        if case .executing = installService.phase { return true }
        return false
    }

    private func statusSummary(for plan: AgentInstallPlan) -> String {
        let total = plan.steps.count
        let done = plan.steps.filter { $0.status == .completed }.count
        let failed = plan.steps.filter { $0.status == .failed }.count
        let denied = plan.steps.filter { $0.status == .denied }.count

        if failed > 0 {
            return String(localized: "Failed at step \(failed) of \(total)", bundle: .appModule)
        }
        if denied > 0 {
            return String(localized: "Denied — \(done) of \(total) completed", bundle: .appModule)
        }
        if done == total {
            return String(localized: "Installation completed successfully.", bundle: .appModule)
        }
        return String(localized: "Step \(done + 1) of \(total)", bundle: .appModule)
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedSteps.contains(id) {
            expandedSteps.remove(id)
        } else {
            expandedSteps.insert(id)
        }
    }

    @ViewBuilder
    private var completedSummary: some View {
        if let record = installService.installRegistry.first(where: { $0.id == planId }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(record.name)
                        .font(.subheadline.weight(.semibold))
                }
                Text(record.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.cardBackground)
            }
        }
    }
}
