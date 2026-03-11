import SwiftUI

/// Settings tab for remote Gateway connection configuration.
struct RemoteSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var testStatus: TestConnectionStatus = .idle
    @State private var testMessage: String?

    var body: some View {
        @Bindable var state = appState
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Connection Mode
                GroupBox("Connection Mode") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Mode", selection: $state.connectionMode) {
                            Text("Unconfigured").tag(ConnectionMode.unconfigured)
                            Text("Local").tag(ConnectionMode.local)
                            Text("Remote").tag(ConnectionMode.remote)
                        }
                        .pickerStyle(.segmented)

                        Text(connectionModeDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Gateway Port
                GroupBox("Gateway") {
                    LabeledContent("Port") {
                        TextField("3577", value: $state.gatewayPort, format: .number)
                            .mcclawTextField()
                            .frame(width: 80)
                    }
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(state.gatewayStatus.rawValue.capitalized)
                                .font(.subheadline)
                        }
                    }
                }

                // Remote Configuration (only visible in remote mode)
                if state.connectionMode == .remote {
                    remoteConfigSection
                }

                // Test Connection
                GroupBox("Connection Test") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button {
                                testConnection()
                            } label: {
                                if testStatus == .testing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Test Connection")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(testStatus == .testing)

                            Button("Apply") {
                                applyConnection()
                            }
                            .buttonStyle(.bordered)
                        }

                        if let message = testMessage {
                            HStack(spacing: 6) {
                                Image(systemName: testStatus == .success ? "checkmark.circle" : "xmark.circle")
                                    .foregroundStyle(testStatus == .success ? .green : .red)
                                Text(message)
                                    .font(.subheadline)
                                    .foregroundStyle(testStatus == .success ? .green : .red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .onChange(of: appState.connectionMode) { _, _ in saveConfig() }
        .onChange(of: appState.remoteTransport) { _, _ in saveConfig() }
    }

    // MARK: - Remote Config

    @ViewBuilder
    private var remoteConfigSection: some View {
        @Bindable var state = appState

        GroupBox("Remote Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Transport", selection: $state.remoteTransport) {
                    Text("SSH Tunnel").tag(RemoteTransport.ssh)
                    Text("Direct").tag(RemoteTransport.direct)
                }
                .pickerStyle(.segmented)

                if state.remoteTransport == .ssh {
                    sshConfigFields
                } else {
                    directConfigFields
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var sshConfigFields: some View {
        @Bindable var state = appState

        LabeledContent("Target") {
            TextField("user@host:port", text: Binding(
                get: { state.remoteTarget ?? "" },
                set: { state.remoteTarget = $0.isEmpty ? nil : $0 }
            ))
            .mcclawTextField()
            .font(.system(.body, design: .monospaced))
        }

        LabeledContent("SSH Key") {
            HStack {
                TextField("~/.ssh/id_rsa", text: Binding(
                    get: { state.remoteIdentity ?? "" },
                    set: { state.remoteIdentity = $0.isEmpty ? nil : $0 }
                ))
                .mcclawTextField()
                .font(.system(.body, design: .monospaced))

                Button("Browse") {
                    browseSSHKey()
                }
                .controlSize(.small)
            }
        }

        Text("SSH tunnel forwards the remote gateway port to localhost.\nRequires SSH key-based auth (BatchMode=yes, no password prompt).")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var directConfigFields: some View {
        @Bindable var state = appState

        LabeledContent("URL") {
            TextField("wss://gateway.example.com:443/ws", text: Binding(
                get: { state.remoteUrl ?? "" },
                set: { state.remoteUrl = $0.isEmpty ? nil : $0 }
            ))
            .mcclawTextField()
            .font(.system(.body, design: .monospaced))
        }

        if let urlStr = state.remoteUrl, !urlStr.isEmpty {
            if GatewayRemoteConfig.normalizeGatewayUrl(urlStr) == nil {
                Text("Invalid URL. Must be wss:// for remote or ws:// for loopback only.")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }

        Text("Direct WebSocket connection. Use wss:// (TLS) for non-loopback hosts.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private var connectionModeDescription: String {
        switch appState.connectionMode {
        case .unconfigured:
            "No Gateway connection. Chat uses local CLI only."
        case .local:
            "Connect to Gateway on localhost (127.0.0.1)."
        case .remote:
            "Connect to Gateway on a remote host via SSH tunnel or direct URL."
        }
    }

    private var statusColor: Color {
        switch appState.gatewayStatus {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .gray
        case .error: .red
        }
    }

    private func browseSSHKey() {
        let panel = NSOpenPanel()
        panel.title = "Select SSH Key"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            AppState.shared.remoteIdentity = url.path
            saveConfig()
        }
    }

    private func testConnection() {
        testStatus = .testing
        testMessage = nil

        Task {
            do {
                switch appState.connectionMode {
                case .unconfigured:
                    testStatus = .success
                    testMessage = "No connection needed in unconfigured mode."

                case .local:
                    let discovery = GatewayDiscovery()
                    if let endpoint = await discovery.discoverLocal(port: appState.gatewayPort) {
                        testStatus = .success
                        testMessage = "Gateway found at \(endpoint.host):\(endpoint.port)"
                    } else {
                        testStatus = .failed
                        testMessage = "No Gateway found on port \(appState.gatewayPort)"
                    }

                case .remote:
                    if appState.remoteTransport == .ssh {
                        guard let target = appState.remoteTarget,
                              SSHTarget.parse(target) != nil else {
                            testStatus = .failed
                            testMessage = "Invalid SSH target"
                            return
                        }
                        // Test SSH connectivity
                        let result = await testSSH(target: target, identity: appState.remoteIdentity)
                        testStatus = result.0 ? .success : .failed
                        testMessage = result.1
                    } else {
                        guard let urlStr = appState.remoteUrl,
                              GatewayRemoteConfig.normalizeGatewayUrl(urlStr) != nil else {
                            testStatus = .failed
                            testMessage = "Invalid remote URL"
                            return
                        }
                        testStatus = .success
                        testMessage = "URL valid: \(urlStr)"
                    }
                }
            }
        }
    }

    private func testSSH(target: String, identity: String?) async -> (Bool, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new",
        ]
        if let identity = identity?.trimmingCharacters(in: .whitespacesAndNewlines),
           !identity.isEmpty {
            args += ["-i", (identity as NSString).expandingTildeInPath]
        }
        args += [target, "echo", "mcclaw-test-ok"]
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if output.contains("mcclaw-test-ok") {
                    return (true, "SSH connection successful")
                }
                return (true, "SSH connected (unexpected output)")
            } else {
                return (false, "SSH connection failed (exit code \(process.terminationStatus))")
            }
        } catch {
            return (false, "SSH test error: \(error.localizedDescription)")
        }
    }

    private func applyConnection() {
        Task {
            await ConnectionModeCoordinator.shared.apply(mode: appState.connectionMode)
        }
        saveConfig()
    }

    private func saveConfig() {
        Task { await ConfigStore.shared.saveFromState() }
    }
}

// MARK: - Test Status

private enum TestConnectionStatus {
    case idle
    case testing
    case success
    case failed
}

// MARK: - Import Discovery

import McClawDiscovery
