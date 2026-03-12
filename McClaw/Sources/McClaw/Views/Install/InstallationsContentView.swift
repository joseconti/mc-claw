import SwiftUI

/// Content view for the Installations sidebar section.
/// Shows all agent-installed packages with details and uninstall capability.
struct InstallationsContentView: View {
    @State private var installService = AgentInstallService.shared
    @State private var selectedRecordId: UUID?
    @State private var showUninstallConfirmation = false
    @State private var pendingUninstallId: UUID?
    @State private var showClearAllConfirmation = false

    private var selectedRecord: AgentInstallRecord? {
        installService.installRegistry.first { $0.id == selectedRecordId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Installations", bundle: .module))
                        .font(.title.weight(.bold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !installService.installRegistry.isEmpty {
                    Button(role: .destructive) {
                        showClearAllConfirmation = true
                    } label: {
                        Label(String(localized: "Clear History", bundle: .module), systemImage: "trash.slash")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 24)

            // Content
            if installService.installRegistry.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    // List
                    recordsList

                    Divider()

                    // Detail
                    if let record = selectedRecord {
                        recordDetail(record)
                    } else {
                        noSelectionView
                    }
                }
            }
        }
        .confirmationDialog(
            String(localized: "Clear Installation History", bundle: .module),
            isPresented: $showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear All", bundle: .module), role: .destructive) {
                installService.clearRegistry()
                selectedRecordId = nil
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: {
            Text(String(localized: "This will remove all installation records. The installed software will not be removed.", bundle: .module))
        }
        .confirmationDialog(
            String(localized: "Uninstall Package", bundle: .module),
            isPresented: $showUninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Uninstall", bundle: .module), role: .destructive) {
                if let id = pendingUninstallId {
                    Task { await installService.uninstallRecord(id: id) }
                    if selectedRecordId == id {
                        selectedRecordId = nil
                    }
                }
            }
            Button(String(localized: "Remove Record Only", bundle: .module)) {
                if let id = pendingUninstallId {
                    installService.removeRecord(id: id)
                    if selectedRecordId == id {
                        selectedRecordId = nil
                    }
                }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: {
            Text(String(localized: "Choose whether to run uninstall commands or just remove the record.", bundle: .module))
        }
    }

    // MARK: - Subtitle

    private var subtitle: String {
        let count = installService.installRegistry.count
        if count == 0 {
            return String(localized: "No packages installed yet.", bundle: .module)
        }
        return "\(count) " + String(localized: "package(s) installed by agent", bundle: .module)
    }

    // MARK: - Records List

    @ViewBuilder
    private var recordsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(installService.installRegistry.reversed()) { record in
                    recordRow(record)

                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(minWidth: 280, maxWidth: 320)
    }

    @ViewBuilder
    private func recordRow(_ record: AgentInstallRecord) -> some View {
        let isSelected = selectedRecordId == record.id
        Button {
            selectedRecordId = record.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(record.installedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Step count badge
                let completed = record.steps.filter { $0.status == .completed }.count
                let total = record.steps.count
                Text("\(completed)/\(total)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.sidebarSelection)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                pendingUninstallId = record.id
                showUninstallConfirmation = true
            } label: {
                Label(String(localized: "Uninstall", bundle: .module), systemImage: "trash")
            }
        }
    }

    // MARK: - Record Detail

    @ViewBuilder
    private func recordDetail(_ record: AgentInstallRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.name)
                            .font(.title2.weight(.bold))
                        Text(record.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Metadata
                HStack(spacing: 24) {
                    metadataItem(
                        label: String(localized: "Installed", bundle: .module),
                        value: record.installedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    metadataItem(
                        label: String(localized: "Provider", bundle: .module),
                        value: record.providerId.capitalized
                    )
                    metadataItem(
                        label: String(localized: "Steps", bundle: .module),
                        value: "\(record.steps.filter { $0.status == .completed }.count)/\(record.steps.count) " + String(localized: "completed", bundle: .module)
                    )
                }

                Divider()

                // Steps
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Installation Steps", bundle: .module))
                        .font(.headline)

                    ForEach(record.steps) { step in
                        stepDetailRow(step)
                    }
                }

                Divider()

                // Actions
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        pendingUninstallId = record.id
                        showUninstallConfirmation = true
                    } label: {
                        Label(String(localized: "Uninstall", bundle: .module), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func stepDetailRow(_ step: AgentInstallStep) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                stepStatusIcon(step.status)
                    .frame(width: 16)
                Text(step.description)
                    .font(.callout)
            }

            Text(step.command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if let output = step.output, !output.isEmpty {
                DisclosureGroup(String(localized: "Output", bundle: .module)) {
                    ScrollView {
                        Text(output)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func stepStatusIcon(_ status: AgentInstallStepStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .denied:
            Image(systemName: "shield.slash")
                .foregroundStyle(.red)
                .font(.caption)
        case .skipped:
            Image(systemName: "forward.fill")
                .foregroundStyle(.tertiary)
                .font(.caption)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func metadataItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.callout.weight(.medium))
        }
    }

    // MARK: - Empty & No Selection States

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(String(localized: "No Installations Yet", bundle: .module))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(String(localized: "Use the Install button in the chat to install software from agent prompts.", bundle: .module))
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sidebar.left")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(String(localized: "Select an installation to view details", bundle: .module))
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
