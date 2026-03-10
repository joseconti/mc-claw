import SwiftUI

/// Sheet form for adding or editing an MCP server configuration.
struct MCPServerEditor: View {
    let existingServer: MCPServerConfig?
    let provider: String
    let onCancel: () -> Void
    let onSave: (MCPServerFormData) async throws -> Void

    @State private var form = MCPServerFormData()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { existingServer != nil }
    private var availableTransports: [MCPTransport] {
        MCPProviderSupport.supportedTransports(for: provider)
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
        .frame(width: 480, height: 520)
        .onAppear {
            if let existingServer {
                form = MCPServerFormData.from(existingServer)
            } else {
                form.transport = availableTransports.first ?? .stdio
            }
        }
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
