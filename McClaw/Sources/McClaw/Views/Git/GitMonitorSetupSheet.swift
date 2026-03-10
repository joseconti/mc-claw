import SwiftUI
import McClawKit

/// Sheet for setting up a Git repository monitor from pre-defined templates.
/// Creates a CronJob linked to the repo's connector.
struct GitMonitorSetupSheet: View {
    let repoFullName: String
    let platform: GitPlatform
    let onDismiss: () -> Void

    @State private var selectedTemplate: GitMonitorTemplate?
    @State private var cronExpression: String = ""
    @State private var isCreating: Bool = false
    @State private var statusMessage: String?

    private let templates = GitMonitorTemplate.allTemplates

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Set Up Monitor", bundle: .module)
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Template grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(templates) { template in
                        templateCard(template)
                    }
                }
                .padding()
            }

            Divider()

            // Schedule + Create
            if let template = selectedTemplate {
                VStack(spacing: 12) {
                    HStack {
                        Text("Schedule:", bundle: .module)
                            .font(.callout.weight(.medium))
                        TextField("Cron expression", text: $cronExpression)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: 200)
                        Spacer()
                    }

                    if let status = statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.contains("Error") ? .red : .green)
                    }

                    HStack {
                        Spacer()
                        Button {
                            Task { await createMonitor(template: template) }
                        } label: {
                            HStack(spacing: 4) {
                                if isCreating {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text("Create Monitor", bundle: .module)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(cronExpression.isEmpty || isCreating)
                    }
                }
                .padding()
            }
        }
        .frame(width: 520, height: 480)
    }

    // MARK: - Template Card

    @ViewBuilder
    private func templateCard(_ template: GitMonitorTemplate) -> some View {
        let isSelected = selectedTemplate?.id == template.id
        Button {
            selectedTemplate = template
            cronExpression = template.defaultCronExpression
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: template.icon)
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Spacer()
                }
                Text(template.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create Monitor

    private func createMonitor(template: GitMonitorTemplate) async {
        isCreating = true
        statusMessage = nil

        let prompt = template.promptTemplate.replacingOccurrences(of: "{{repo}}", with: repoFullName)
        let connectorId = platform.connectorId
        let connectorStore = ConnectorStore.shared
        guard let instance = connectorStore.connectedInstances.first(where: { $0.definitionId == connectorId }) else {
            statusMessage = String(localized: "git_monitor_error_no_connector", bundle: .module)
            isCreating = false
            return
        }

        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let bindingObj: AnyCodableValue = .dictionary([
            "connectorInstanceId": .string(instance.id),
            "actionId": .string("list_prs"),
            "params": .dictionary([:]),
            "maxResultLength": .int(4000),
        ])

        let payload: [String: AnyCodableValue] = [
            "name": .string("\(template.name) — \(repoFullName)"),
            "description": .string(template.description),
            "enabled": .bool(true),
            "schedule": .dictionary([
                "kind": .string("cron"),
                "expr": .string(cronExpression),
            ]),
            "sessionTarget": .string("isolated"),
            "wakeMode": .string("now"),
            "payload": .dictionary([
                "kind": .string("agentTurn"),
                "message": .string(prompt),
                "connectorBindings": .array([bindingObj]),
            ]),
            "createdAtMs": .int(nowMs),
            "updatedAtMs": .int(nowMs),
        ]

        do {
            try await CronJobsStore.shared.upsertJob(id: nil, payload: payload)
            statusMessage = String(localized: "git_monitor_created", bundle: .module)
            // Auto-dismiss after a short delay
            try? await Task.sleep(for: .seconds(1))
            onDismiss()
        } catch {
            statusMessage = String(localized: "git_monitor_error_create", bundle: .module) + ": \(error.localizedDescription)"
        }

        isCreating = false
    }
}
