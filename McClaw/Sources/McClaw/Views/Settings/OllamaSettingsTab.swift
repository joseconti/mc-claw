import SwiftUI
import McClawKit

/// Settings tab for Ollama provider: server management, model installer, hardware recommendations.
struct OllamaSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var serverStatus: OllamaKit.ServerStatus = .unknown
    @State private var installedModels: [(id: String, name: String, size: String)] = []
    @State private var runningModels: [OllamaKit.RunningModel] = []
    @State private var isPulling = false
    @State private var pullModelName = ""
    @State private var pullLog: [String] = []
    @State private var pullError: String?
    @State private var hardwareInfo: OllamaKit.HardwareInfo?
    @State private var showDeleteConfirm = false
    @State private var modelToDelete: String?
    @State private var isStartingServer = false
    @State private var isRefreshing = false

    var body: some View {
        @Bindable var state = appState
        VStack(alignment: .leading, spacing: 0) {
            // Check if Ollama is installed
            if let ollamaProvider = appState.availableCLIs.first(where: { $0.id == "ollama" }),
               ollamaProvider.isInstalled {
                installedContent
            } else {
                notInstalledView
            }
        }
        .task {
            hardwareInfo = OllamaKit.detectHardware()
            await checkServerStatus()
            await refreshModels()
        }
    }

    // MARK: - Not Installed

    private var notInstalledView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(String(localized: "ollama_not_installed", bundle: .module))
                    .font(.callout)
            }

            Text(String(localized: "ollama_install_instructions", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                if let url = URL(string: "https://ollama.com/download") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(String(localized: "ollama_download_button", bundle: .module), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Installed Content

    private var installedContent: some View {
        @Bindable var state = appState
        return VStack(alignment: .leading, spacing: 0) {
            // Section 1: Server Status
            serverStatusSection

            sectionDivider()

            // Section 2: Server Mode
            serverModeSection

            sectionDivider()

            // Section 3: Model Library (unified grid)
            modelLibrarySection

            sectionDivider()

            // Section 4: Hardware Info
            hardwareSection
        }
    }

    // MARK: - Server Status Section

    private var serverStatusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(String(localized: "ollama_server_status_header", bundle: .module))

            HStack {
                Image(systemName: serverStatus == .running ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(serverStatus == .running ? .green : .red)
                Text(serverStatus == .running
                     ? String(localized: "ollama_server_running", bundle: .module)
                     : String(localized: "ollama_server_stopped", bundle: .module))
                    .font(.callout)
                Spacer()

                if serverStatus == .running {
                    Button(String(localized: "ollama_stop_server", bundle: .module)) {
                        stopServer()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                } else {
                    Button {
                        startServer()
                    } label: {
                        if isStartingServer {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Text(String(localized: "ollama_start_server", bundle: .module))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .disabled(isStartingServer)
                }
            }
            .padding(.vertical, 4)

            if !runningModels.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "ollama_loaded_models", bundle: .module))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(runningModels, id: \.name) { model in
                        HStack(spacing: 4) {
                            Text(model.name)
                                .font(.caption)
                            Text("\u{2022}")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(model.size)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\u{2022}")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(model.processor)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Server Mode Section

    private var serverModeSection: some View {
        @Bindable var state = appState
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "ollama_server_mode", bundle: .module))

            HStack {
                Text(String(localized: "ollama_mode_label", bundle: .module))
                    .frame(width: 120, alignment: .leading)
                Picker("", selection: $state.ollamaAlwaysOn) {
                    Text(String(localized: "ollama_always_on", bundle: .module))
                        .tag(true)
                    Text(String(localized: "ollama_on_demand", bundle: .module))
                        .tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            Text(String(localized: "ollama_server_mode_description", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(String(localized: "ollama_server_port", bundle: .module))
                    .frame(width: 120, alignment: .leading)
                TextField("", value: $state.ollamaServerPort, format: .number)
                    .mcclawTextField()
                    .frame(width: 80)
            }
        }
        .padding(.vertical, 8)
        .onChange(of: appState.ollamaAlwaysOn) { Task { await ConfigStore.shared.saveFromState() } }
        .onChange(of: appState.ollamaServerPort) { Task { await ConfigStore.shared.saveFromState() } }
    }

    // MARK: - Model Library Section (unified two-column grid)

    private var modelLibrarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeader(String(localized: "ollama_model_installer_header", bundle: .module))
                Spacer()
                Button {
                    Task { await refreshModels() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
            }

            if let hw = hardwareInfo {
                Text(String(localized: "ollama_recommended_for_mac", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                let groupedModels = OllamaKit.recommendedModelsByGroup(for: hw)
                let installedIds = Set(installedModels.map(\.id))

                ForEach(groupedModels, id: \.group) { entry in
                    // Group header — bigger, with icon and description
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: entry.group.icon)
                                .font(.body)
                                .foregroundColor(.accentColor)
                            Text(entry.group.displayName)
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.top, 12)

                        Text(entry.group.groupDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 6)
                    }

                    // Two-column grid of model cards
                    let columns = [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ]
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(entry.models) { model in
                            modelCard(model: model, isInstalled: installedIds.contains(model.modelId))
                        }
                    }
                }

                if groupedModels.allSatisfy({ entry in
                    entry.models.allSatisfy { installedIds.contains($0.modelId) }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text(String(localized: "ollama_all_recommended_installed", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }

            // Custom model install
            HStack {
                TextField(String(localized: "ollama_pull_custom_placeholder", bundle: .module), text: $pullModelName)
                    .mcclawTextField()
                    .frame(width: 200)
                    .disabled(isPulling)
                Button {
                    pullModel(pullModelName)
                } label: {
                    Label(String(localized: "ollama_install_button", bundle: .module), systemImage: "arrow.down.circle")
                }
                .disabled(pullModelName.isEmpty || isPulling)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 12)

            // Pull progress log
            if !pullLog.isEmpty {
                InstallLogTextView(lines: pullLog)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 8)

                if !isPulling && pullError == nil {
                    Button(String(localized: "ollama_dismiss_log", bundle: .module)) {
                        pullLog = []
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
                }
            }

            // Pull error
            if let pullError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(pullError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                    Button(String(localized: "ollama_dismiss_log", bundle: .module)) {
                        self.pullError = nil
                        pullLog = []
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .alert(String(localized: "ollama_delete_confirm_title", bundle: .module), isPresented: $showDeleteConfirm) {
            Button(String(localized: "ollama_cancel", bundle: .module), role: .cancel) {}
            Button(String(localized: "ollama_delete_confirm", bundle: .module), role: .destructive) {
                if let model = modelToDelete {
                    deleteModel(model)
                }
            }
        } message: {
            Text(String(localized: "ollama_delete_confirm_message", bundle: .module))
        }
    }

    // MARK: - Model Card

    private func modelCard(model: OllamaKit.OllamaModelInfo, isInstalled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: name + badges
            HStack(spacing: 4) {
                Text(model.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if model.qualityRank == 1 {
                    Text(String(localized: "ollama_best_badge", bundle: .module))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.green.opacity(0.2))
                        .clipShape(Capsule())
                }
                Spacer()
            }

            // Specs
            HStack(spacing: 4) {
                Text(model.parameterSize)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.12))
                    .clipShape(Capsule())
                Text("\(model.minimumRAMGB)GB+ RAM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Description
            Text(model.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            // Action button
            HStack {
                if isInstalled {
                    // Default badge or Set as Default
                    if appState.defaultModels["ollama"] == model.modelId {
                        Text(String(localized: "ollama_default_badge", bundle: .module))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.2))
                            .clipShape(Capsule())
                    } else {
                        Button {
                            appState.defaultModels["ollama"] = model.modelId
                            Task { await ConfigStore.shared.saveFromState() }
                        } label: {
                            Text(String(localized: "ollama_set_default", bundle: .module))
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }

                    Spacer()

                    // Uninstall button
                    Button(role: .destructive) {
                        modelToDelete = model.modelId
                        showDeleteConfirm = true
                    } label: {
                        Label(String(localized: "ollama_uninstall_button", bundle: .module), systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Spacer()

                    // Install button
                    if isPulling && pullModelName == model.modelId {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Button {
                            pullModel(model.modelId)
                        } label: {
                            Label(String(localized: "ollama_install_button", bundle: .module), systemImage: "arrow.down.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isPulling)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isInstalled ? Color.accentColor.opacity(0.06) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isInstalled ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Hardware Section

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "ollama_hardware_header", bundle: .module))

            if let hw = hardwareInfo {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "ollama_chip", bundle: .module))
                                .font(.caption.weight(.medium))
                            Text(hw.chipName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(String(localized: "ollama_ram", bundle: .module))
                                .font(.caption.weight(.medium))
                            Text("\(hw.totalRAMGB) GB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(String(localized: "ollama_cores", bundle: .module))
                                .font(.caption.weight(.medium))
                            Text("\(hw.cpuCores)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(OllamaKit.recommendationText(for: hw))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private var ollamaBinaryPath: String {
        appState.availableCLIs.first(where: { $0.id == "ollama" })?.binaryPath ?? "/opt/homebrew/bin/ollama"
    }

    private func checkServerStatus() async {
        let port = appState.ollamaServerPort
        let urlString = OllamaKit.healthURL(port: port)
        guard let url = URL(string: urlString) else {
            serverStatus = .unknown
            return
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                serverStatus = .running
                // Also check running models
                await refreshRunningModels()
            } else {
                serverStatus = .stopped
            }
        } catch {
            serverStatus = .stopped
        }
    }

    private func refreshRunningModels() async {
        let binary = ollamaBinaryPath
        guard FileManager.default.isExecutableFile(atPath: binary) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["ps"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                await MainActor.run {
                    runningModels = OllamaKit.parseOllamaPs(output)
                }
            }
        } catch {
            // Ignore
        }
    }

    private func refreshModels() async {
        isRefreshing = true
        let binary = ollamaBinaryPath
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            isRefreshing = false
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse the tabular output: NAME  ID  SIZE  MODIFIED
                let lines = output.components(separatedBy: .newlines)
                var models: [(id: String, name: String, size: String)] = []
                for line in lines.dropFirst() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }
                    let columns = trimmed.components(separatedBy: "  ")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    guard columns.count >= 3 else { continue }
                    let modelId = columns[0]
                    let size = columns[2]
                    models.append((id: modelId, name: modelId, size: size))
                }
                await MainActor.run {
                    installedModels = models
                }
            }
        } catch {
            // Ignore
        }

        isRefreshing = false
    }

    private func startServer() {
        isStartingServer = true
        let binary = ollamaBinaryPath

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["serve"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                // Wait a moment for the server to start
                try await Task.sleep(for: .seconds(2))
            } catch {
                // Ignore
            }

            await MainActor.run {
                isStartingServer = false
            }
            await checkServerStatus()
            await refreshModels()
        }
    }

    private func stopServer() {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            process.arguments = ["-f", "ollama serve"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()

            try? await Task.sleep(for: .seconds(1))
            await checkServerStatus()
        }
    }

    private func pullModel(_ modelName: String) {
        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isPulling = true
        pullLog = []
        pullError = nil
        pullModelName = name

        let binary = ollamaBinaryPath

        Task.detached {
            // Ensure server is running before pulling
            await ensureServerRunning()

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["pull", name]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let cleaned = stripANSI(text)
                let lines = cleaned.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard !lines.isEmpty else { return }
                Task { @MainActor in
                    pullLog.append(contentsOf: lines)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let cleaned = stripANSI(text)
                let lines = cleaned.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard !lines.isEmpty else { return }
                Task { @MainActor in
                    pullLog.append(contentsOf: lines)
                }
            }

            do {
                try process.run()
            } catch {
                await MainActor.run {
                    pullError = "Failed to start process: \(error.localizedDescription)"
                    isPulling = false
                }
                return
            }

            process.waitUntilExit()

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let exitCode = process.terminationStatus

            if exitCode == 0 {
                await MainActor.run {
                    pullLog.append("[\u{2713}] Model \(name) pulled successfully!")
                    isPulling = false
                    pullModelName = ""
                }
                await refreshModels()
            } else {
                await MainActor.run {
                    pullError = "ollama pull failed with exit code \(exitCode). See log above."
                    pullLog.append("[ERROR] Process exited with code \(exitCode)")
                    isPulling = false
                }
            }
        }
    }

    private func ensureServerRunning() async {
        let port = await MainActor.run { appState.ollamaServerPort }
        let urlString = OllamaKit.healthURL(port: port)
        guard let url = URL(string: urlString) else { return }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return // Already running
            }
        } catch {
            // Not running, start it
        }

        // Start server
        let binary = await MainActor.run { ollamaBinaryPath }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        try? await Task.sleep(for: .seconds(2))
    }

    private func deleteModel(_ modelId: String) {
        let binary = ollamaBinaryPath

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["rm", modelId]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()

            // Clear default if this was the selected model
            await MainActor.run {
                if appState.defaultModels["ollama"] == modelId {
                    appState.defaultModels.removeValue(forKey: "ollama")
                    Task { await ConfigStore.shared.saveFromState() }
                }
            }

            await refreshModels()
        }
    }
}

// MARK: - ANSI Escape Code Stripping

/// Strips ANSI escape sequences (colors, cursor control, etc.) from terminal output.
private func stripANSI(_ text: String) -> String {
    // Matches: ESC[ ... final byte, ESC] ... ST, ESC? sequences
    guard let regex = try? NSRegularExpression(
        pattern: "\\x1b\\[[0-9;?]*[A-Za-z]|\\x1b\\][^\u{07}]*\u{07}|\\x1b\\[\\?[0-9;]*[hl]|\\x1b[()][A-Za-z0-9]|\\r",
        options: []
    ) else { return text }
    return regex.stringByReplacingMatches(
        in: text,
        range: NSRange(text.startIndex..., in: text),
        withTemplate: ""
    )
}

// MARK: - Section Helpers (matching SettingsWindow style)

private func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.headline)
        .padding(.top, 16)
        .padding(.bottom, 4)
}

private func sectionDivider() -> some View {
    Divider()
        .padding(.vertical, 8)
}
