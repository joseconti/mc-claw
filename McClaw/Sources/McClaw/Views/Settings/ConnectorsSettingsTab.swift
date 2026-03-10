import McClawKit
import SwiftUI

/// Settings tab for managing external service connectors.
struct ConnectorsSettingsTab: View {
    @State private var store = ConnectorStore.shared
    @State private var expandedCategories: Set<ConnectorCategory> = Set(ConnectorCategory.allCases)
    @State private var selectedDefinition: ConnectorDefinition?
    @State private var selectedInstance: ConnectorInstance?
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            connectorsListView
        }
        .sheet(isPresented: $showDetail) {
            if let def = selectedDefinition {
                ConnectorDetailView(
                    definition: def,
                    instance: $selectedInstance
                )
                .frame(minWidth: 500, minHeight: 400)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect external services to enrich AI prompts with real data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if store.connectedCount > 0 {
                Text("\(store.connectedCount) connector(s) active")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            connectorsVsChannelsNote
        }
    }

    /// Informational note explaining the difference between Connectors and Channels.
    private var connectorsVsChannelsNote: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Label("Connectors vs Channels", systemImage: "info.circle")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Text("Connectors READ data from services to give context to the AI. Channels (in the Channels section) SEND messages as responses. They are complementary — you can have Slack as both a connector and a channel.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(4)
        }
    }

    // MARK: - Connectors List

    private var connectorsListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ConnectorRegistry.categories, id: \.self) { category in
                categorySection(category)
            }
        }
    }

    private func categorySection(_ category: ConnectorCategory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            categoryHeader(category)

            if expandedCategories.contains(category) {
                let defs = ConnectorRegistry.definitions(for: category)
                VStack(spacing: 2) {
                    ForEach(defs) { definition in
                        connectorRow(definition)
                    }
                }
                .padding(.leading, 8)

                if category == .wordpress {
                    wpModulesList
                    wpRequirementNote
                }
            }
        }
    }

    // MARK: - WordPress Modules & Note

    /// List of all WordPress modules included with MCP Content Manager (same visual style as connectorRow).
    private var wpModulesList: some View {
        VStack(spacing: 2) {
            ForEach(MCMAbilitiesCatalog.subConnectors, id: \.id) { sub in
                HStack(spacing: 10) {
                    Image(systemName: sub.icon)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(sub.name)
                            .font(.body)

                        Text(sub.description)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(sub.abilities.count) abilities")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
        }
        .padding(.leading, 8)
    }

    /// Informational note shown under the WordPress modules list.
    private var wpRequirementNote: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Label("Requires MCP Content Manager", systemImage: "puzzlepiece.extension")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Text("All modules above are included with a single connection. Install the MCP Content Manager plugin on your WordPress site and configure the MCP server in Settings → MCP.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Link("Get MCP Content Manager",
                     destination: URL(string: "https://plugins.joseconti.com/en/product/mcp-content-manager-for-wordpress/")!)
                    .font(.caption2)
            }
            .padding(4)
        }
        .padding(.leading, 8)
    }

    private func categoryHeader(_ category: ConnectorCategory) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedCategories.contains(category) {
                    expandedCategories.remove(category)
                } else {
                    expandedCategories.insert(category)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: expandedCategories.contains(category) ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)

                Image(systemName: category.icon)
                    .font(.caption)
                    .frame(width: 16)

                Text(category.title)
                    .font(.headline)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func connectorRow(_ definition: ConnectorDefinition) -> some View {
        let existingInstance = store.instances.first { $0.definitionId == definition.id }

        return HStack(spacing: 10) {
            Image(systemName: definition.icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(definition.name)
                    .font(.body)

                Text(definition.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let instance = existingInstance {
                statusBadge(instance)
                configureButton(definition: definition, instance: instance)
                connectButton(definition: definition, instance: instance)
                removeButton(instance: instance)
            } else {
                addButton(definition: definition)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            store.selectedInstanceId == existingInstance?.id
                ? Color.accentColor.opacity(0.1)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            store.selectedInstanceId = existingInstance?.id
        }
    }

    // MARK: - Badges & Buttons

    private func statusBadge(_ instance: ConnectorInstance) -> some View {
        Circle()
            .fill(instance.isConnected ? Color.green : Color.gray)
            .frame(width: 8, height: 8)
    }

    private func configureButton(definition: ConnectorDefinition, instance: ConnectorInstance) -> some View {
        Button {
            selectedDefinition = definition
            selectedInstance = instance
            showDetail = true
        } label: {
            Image(systemName: "gear")
        }
        .controlSize(.small)
        .buttonStyle(.borderless)
    }

    private func connectButton(definition: ConnectorDefinition, instance: ConnectorInstance) -> some View {
        Group {
            if instance.isConnected {
                Button("Disconnect") {
                    store.setConnected(id: instance.id, connected: false)
                    Task {
                        await KeychainService.shared.deleteCredentials(instanceId: instance.id)
                    }
                }
                .controlSize(.small)
                .foregroundStyle(.red)
            } else {
                Button("Connect") {
                    selectedDefinition = definition
                    selectedInstance = instance
                    showDetail = true
                }
                .controlSize(.small)
            }
        }
    }

    private func addButton(definition: ConnectorDefinition) -> some View {
        Group {
            if definition.authType == .mcpBridge {
                mcpBridgeButton(definition)
            } else {
                Button("Add") {
                    let inst = store.addInstance(definitionId: definition.id)
                    if let inst {
                        selectedDefinition = definition
                        selectedInstance = inst
                        showDetail = true
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func removeButton(instance: ConnectorInstance) -> some View {
        Button {
            if instance.isConnected {
                store.setConnected(id: instance.id, connected: false)
                Task {
                    await KeychainService.shared.deleteCredentials(instanceId: instance.id)
                }
            }
            store.removeInstance(id: instance.id)
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(.red.opacity(0.7))
        }
        .controlSize(.small)
        .buttonStyle(.borderless)
        .help("Remove connector")
    }

    private func mcpBridgeButton(_ definition: ConnectorDefinition) -> some View {
        Button("Add") {
            let inst = store.addInstance(definitionId: definition.id)
            selectedDefinition = definition
            selectedInstance = inst
            showDetail = true
        }
        .controlSize(.small)
    }
}
