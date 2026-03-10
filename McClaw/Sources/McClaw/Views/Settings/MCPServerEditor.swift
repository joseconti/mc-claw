import SwiftUI

/// Sheet form for adding or editing an MCP server configuration.
struct MCPServerEditor: View {
    let existingServer: MCPServerConfig?
    let provider: String
    let onCancel: () -> Void
    let onSave: (MCPServerFormData) async throws -> Void

    @State private var form: MCPServerFormData
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { existingServer != nil }
    private var availableTransports: [MCPTransport] {
        MCPProviderSupport.supportedTransports(for: provider)
    }

    init(
        existingServer: MCPServerConfig?,
        provider: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (MCPServerFormData) async throws -> Void
    ) {
        self.existingServer = existingServer
        self.provider = provider
        self.onCancel = onCancel
        self.onSave = onSave

        if let existingServer {
            self._form = State(initialValue: MCPServerFormData.from(existingServer))
        } else {
            var newForm = MCPServerFormData()
            newForm.transport = MCPProviderSupport.supportedTransports(for: provider).first ?? .stdio
            self._form = State(initialValue: newForm)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(isEditing ? "Edit MCP Server" : "Add MCP Server")
                    .font(.headline)
                Spacer()
                Text(provider.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary)
                    .clipShape(Capsule())
                    .liquidGlassCapsule(interactive: false)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Server") {
                    TextField("Name", text: $form.name)
                        .disabled(isEditing)

                    if availableTransports.count > 1 {
                        Picker("Transport", selection: $form.transport) {
                            ForEach(availableTransports) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                    } else {
                        LabeledContent("Transport", value: form.transport.displayName)
                    }
                }

                if form.transport == .stdio {
                    Section("Command") {
                        TextField("Command (e.g. npx, uvx, node)", text: $form.command)
                        TextField("Arguments (one per line)", text: $form.argsText, axis: .vertical)
                            .lineLimit(2...5)
                    }
                } else {
                    Section("Endpoint") {
                        TextField("URL", text: $form.url)
                    }
                }

                if MCPProviderSupport.supportsScope(provider) {
                    Section("Scope") {
                        Picker("Scope", selection: $form.scope) {
                            Text("User (global)").tag(MCPScope.user)
                            Text("Project (local)").tag(MCPScope.project)
                        }
                    }
                }

                Section("Environment Variables") {
                    ForEach($form.envVars) { $entry in
                        HStack(spacing: 8) {
                            TextField("KEY", text: $entry.key)
                                .frame(maxWidth: 150)
                            Text("=")
                                .foregroundStyle(.secondary)
                            TextField("value", text: $entry.value)
                            Button {
                                form.envVars.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Add Variable") {
                        form.envVars.append(EnvVarEntry())
                    }
                    .font(.caption)
                }

                // Auth section (only for HTTP transports)
                if form.transport != .stdio {
                    Section("Authentication") {
                        Picker("Auth Type", selection: $form.authType) {
                            ForEach(MCPAuthType.allCases) { authType in
                                Text(authType.displayName).tag(authType)
                            }
                        }

                        switch form.authType {
                        case .none:
                            EmptyView()

                        case .headers:
                            Text("Add HTTP headers (e.g. Authorization: Bearer token or Basic user:pass)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach($form.headers) { $entry in
                                HStack(spacing: 8) {
                                    TextField("Header", text: $entry.key)
                                        .frame(maxWidth: 150)
                                    Text(":")
                                        .foregroundStyle(.secondary)
                                    TextField("value", text: $entry.value)
                                    Button {
                                        form.headers.removeAll { $0.id == entry.id }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Button("Add Header") {
                                form.headers.append(HeaderEntry())
                            }
                            .font(.caption)

                        case .oauth:
                            TextField("Client ID", text: $form.oauthClientId)
                            TextField("Client Secret (optional)", text: $form.oauthClientSecret)
                                .textContentType(.none)
                            TextField("Callback Port (optional)", text: $form.oauthCallbackPort)
                                .help("Local port for OAuth callback (e.g. 8080)")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Actions
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Add Server") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || form.validationError != nil)
            }
            .padding()
        }
        .frame(width: 480, height: 580)
    }

    private func save() {
        if let error = form.validationError {
            errorMessage = error
            return
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await onSave(form)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
