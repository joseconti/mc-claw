import SwiftUI

/// Settings tab for managing MCP server configurations.
struct MCPSettingsTab: View {
    @Environment(AppState.self) private var appState
    /// Identifies the editor sheet mode to ensure SwiftUI recreates it properly.
    enum EditorMode: Identifiable {
        case add
        case edit(MCPServerConfig)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let server): "edit-\(server.id)"
            }
        }

        var existingServer: MCPServerConfig? {
            if case .edit(let server) = self { return server }
            return nil
        }
    }

    @State private var manager = MCPConfigManager.shared
    @State private var editorMode: EditorMode?
    @State private var confirmDelete: MCPServerConfig?
    @State private var selectedServerId: String?
    @State private var selectedProvider: String = "claude"
    @State private var showPresetBrowser = false
    @Namespace private var mcpProviderNamespace

    private var currentProvider: String {
        appState.currentCLIIdentifier ?? "claude"
    }

    private var mcpProviders: [CLIProviderInfo] {
        appState.availableCLIs.filter { MCPProviderSupport.isSupported($0.id) }
    }

    private var serversForSelectedProvider: [MCPServerConfig] {
        manager.servers.filter { $0.provider == selectedProvider }
    }

    private var selectedServer: MCPServerConfig? {
        guard let id = selectedServerId else { return nil }
        return manager.servers.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if mcpProviders.isEmpty {
                unsupportedView
            } else {
                HStack(spacing: 0) {
                    serverList
                    Divider()
                    detailPane
                }
            }
        }
        .onAppear {
            selectedProvider = currentProvider
            Task { await manager.refreshServers() }
        }
        .sheet(item: $editorMode) { mode in
            MCPServerEditor(
                existingServer: mode.existingServer,
                provider: selectedProvider,
                onCancel: {
                    editorMode = nil
                },
                onSave: { form in
                    if let existing = mode.existingServer {
                        // Remove old then add new
                        try await manager.removeServer(existing)
                    }
                    try await manager.addServer(form, provider: selectedProvider)
                    editorMode = nil
                }
            )
        }
        .sheet(isPresented: $showPresetBrowser) {
            MCPPresetBrowser(
                provider: selectedProvider,
                installedServerNames: Set(serversForSelectedProvider.map(\.name)),
                onCancel: { showPresetBrowser = false },
                onInstall: { form in
                    try await manager.addServer(form, provider: selectedProvider)
                    showPresetBrowser = false
                }
            )
        }
        .alert(
            "Remove MCP Server?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let server = confirmDelete {
                    Task {
                        try? await manager.removeServer(server)
                        if selectedServerId == server.id {
                            selectedServerId = nil
                        }
                    }
                }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            if let server = confirmDelete {
                Text("Remove \"\(server.name)\" from \(server.provider.capitalized)?")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MCP Servers")
                    .font(.headline)
                Text("Configure Model Context Protocol servers for your AI CLIs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if mcpProviders.count > 1 {
                HStack(spacing: 0) {
                    ForEach(mcpProviders) { cli in
                        let isSelected = cli.id == selectedProvider
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                selectedProvider = cli.id
                            }
                        } label: {
                            Text(cli.displayName)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .white : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background {
                                    if isSelected {
                                        Capsule()
                                            .fill(Color.accentColor.opacity(0.35))
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                                            )
                                            .matchedGeometryEffect(id: "mcpProviderPill", in: mcpProviderNamespace)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(.quaternary.opacity(0.5))
                .clipShape(Capsule())
                .liquidGlassCapsule()
            }

            Button {
                Task { await manager.refreshServers() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(manager.isLoading)

            Menu {
                Button {
                    editorMode = .add
                } label: {
                    Label(
                        String(localized: "preset.menu.manual", bundle: .appModule),
                        systemImage: "plus"
                    )
                }

                Button {
                    showPresetBrowser = true
                } label: {
                    Label(
                        String(localized: "preset.menu.browse", bundle: .appModule),
                        systemImage: "square.grid.2x2"
                    )
                }
            } label: {
                Image(systemName: "plus")
            }
            .disabled(!MCPProviderSupport.isSupported(selectedProvider))
        }
        .padding()
    }

    // MARK: - Server List

    private var serverList: some View {
        VStack(spacing: 0) {
            if manager.isLoading && serversForSelectedProvider.isEmpty {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else if serversForSelectedProvider.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No MCP Servers",
                    systemImage: "server.rack",
                    description: Text("Add an MCP server to extend your AI's capabilities")
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(serversForSelectedProvider) { server in
                            Button {
                                selectedServerId = server.id
                            } label: {
                                serverRow(server)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedServerId == server.id ? Theme.sidebarSelection : .clear)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if server.id != serversForSelectedProvider.last?.id {
                                Divider()
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }

            if let error = manager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .padding(8)
                .background(.orange.opacity(0.1))
            }
        }
        .frame(minWidth: 220, maxWidth: 260)
    }

    private func serverRow(_ server: MCPServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(server.name)
                .font(.body.weight(.medium))

            HStack(spacing: 6) {
                Text(server.transport.displayName)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.blue.opacity(0.15))
                    .clipShape(Capsule())
                    .liquidGlassCapsule(interactive: false)

                if MCPProviderSupport.supportsScope(server.provider) {
                    Text(server.scope.rawValue)
                        .font(.system(.caption))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.green.opacity(0.15))
                        .clipShape(Capsule())
                        .liquidGlassCapsule(interactive: false)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        Group {
            if let server = selectedServer {
                serverDetail(server)
            } else {
                ContentUnavailableView(
                    "Select a Server",
                    systemImage: "sidebar.left",
                    description: Text("Choose an MCP server from the list to view its configuration")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func serverDetail(_ server: MCPServerConfig) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Name & Provider
                HStack {
                    Text(server.name)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(server.provider.capitalized)
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary)
                        .clipShape(Capsule())
                        .liquidGlassCapsule(interactive: false)
                }

                Divider()

                // Transport
                detailRow("Transport", value: server.transport.displayName)

                // Scope (Claude only)
                if MCPProviderSupport.supportsScope(server.provider) {
                    detailRow("Scope", value: server.scope.rawValue.capitalized)
                }

                // Command + Args (stdio)
                if server.transport == .stdio {
                    if let command = server.command {
                        detailRow("Command", value: command)
                    }
                    if !server.args.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Arguments")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(server.args.joined(separator: " "))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                // URL (sse/streamable-http)
                if let url = server.url, server.transport != .stdio {
                    detailRow("URL", value: url)
                }

                // Env vars
                if !server.envVars.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Environment Variables")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(server.envVars.keys.sorted(), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                Text("=")
                                    .foregroundStyle(.secondary)
                                Text(server.envVars[key] ?? "")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }

                // Auth info
                if server.authType != .none {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Authentication")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        switch server.authType {
                        case .headers:
                            ForEach(server.headers.keys.sorted(), id: \.self) { key in
                                HStack {
                                    Text(key)
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.medium)
                                    Text(":")
                                        .foregroundStyle(.secondary)
                                    Text("••••••••")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        case .oauth:
                            if let clientId = server.oauthClientId {
                                detailRow("Client ID", value: clientId)
                            }
                            if let port = server.oauthCallbackPort {
                                detailRow("Callback Port", value: String(port))
                            }
                        case .none:
                            EmptyView()
                        }
                    }
                }

                Divider()

                // Actions
                HStack {
                    Button("Edit") {
                        editorMode = .edit(server)
                    }
                    Button("Remove", role: .destructive) {
                        confirmDelete = server
                    }
                    Spacer()
                }
            }
            .padding()
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    // MARK: - Unsupported

    private var unsupportedView: some View {
        ContentUnavailableView(
            "MCP Not Available",
            systemImage: "server.rack",
            description: Text("Install Claude CLI or Gemini CLI to configure MCP servers.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
