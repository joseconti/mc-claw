import SwiftUI
import McClawKit

/// Settings tab for BitNet (Experimental) provider.
struct BitNetSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var prerequisiteStatuses: [(name: String, displayName: String, present: Bool)] = []
    @State private var installedModels: [String] = []
    @State private var isInstalling = false
    @State private var installLog: [String] = []
    @State private var isUninstalling = false
    @State private var showUninstallConfirm = false
    @State private var manifest: BitNetKit.InstallManifest?
    @State private var prereqsToRemove: Set<String> = []
    @State private var isDownloadingModel = false
    @State private var downloadModelId: String?
    @State private var downloadLog: [String] = []
    @State private var downloadError: String?

    private let installer = CLIInstaller()

    var body: some View {
        @Bindable var state = appState
        VStack(alignment: .leading, spacing: 0) {
            // Experimental badge
            HStack {
                Image(systemName: "flask")
                    .foregroundStyle(.orange)
                Text(String(localized: "bitnet_experimental_badge", bundle: .appModule))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .padding(.bottom, 8)

            // Enable toggle
            Toggle(isOn: $state.showExperimentalProviders) {
                Text(String(localized: "bitnet_show_experimental", bundle: .appModule))
            }
            .onChange(of: appState.showExperimentalProviders) {
                Task { await ConfigStore.shared.saveFromState() }
            }

            if appState.showExperimentalProviders {
                sectionDivider()

                if BitNetKit.isInstalled {
                    installedView
                } else {
                    notInstalledView
                }
            }
        }
    }

    // MARK: - Not Installed

    private var notInstalledView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(String(localized: "bitnet_prerequisites_header", bundle: .appModule))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(BitNetKit.prerequisites, id: \.name) { prereq in
                    let status = prerequisiteStatuses.first(where: { $0.name == prereq.name })
                    HStack {
                        Image(systemName: status?.present == true ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(status?.present == true ? .green : .red)
                        Text(prereq.displayName)
                        if let minVer = prereq.minVersion {
                            Text("(\(minVer)+)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .font(.callout)
                }
            }
            .padding(.vertical, 8)

            if isInstalling {
                installProgressView
            } else {
                Button {
                    startInstallation()
                } label: {
                    Label(String(localized: "bitnet_install_button", bundle: .appModule), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)

                Text(String(localized: "bitnet_install_time_estimate", bundle: .appModule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .task {
            await checkPrerequisites()
        }
    }

    // MARK: - Installed

    private var installedView: some View {
        @Bindable var state = appState
        return VStack(alignment: .leading, spacing: 0) {
            // Status
            sectionHeader(String(localized: "bitnet_status_header", bundle: .appModule))
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(String(localized: "bitnet_status_ready", bundle: .appModule))
                Spacer()
            }
            .padding(.vertical, 4)

            sectionDivider()

            // Models
            sectionHeader(String(localized: "bitnet_models_header", bundle: .appModule))

            VStack(alignment: .leading, spacing: 6) {
                // Installed models
                ForEach(installedModels, id: \.self) { modelId in
                    let info = BitNetKit.registryModel(for: modelId)
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing: 4) {
                                Text(info?.displayName ?? modelId)
                                    .font(.callout.weight(.medium))
                                if info?.isInstruct == false {
                                    Text(String(localized: "bitnet_base_no_chat", bundle: .appModule))
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.orange.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(info?.parameters ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if info?.isInstruct == false {
                            // Base models cannot be set as default for chat
                            Text(String(localized: "bitnet_base_only", bundle: .appModule))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if state.bitnetDefaultModel == modelId || (state.bitnetDefaultModel == nil && info?.isDefault == true) {
                            Text(String(localized: "bitnet_model_default_badge", bundle: .appModule))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.2))
                                .clipShape(Capsule())
                        } else {
                            Button(String(localized: "bitnet_set_default", bundle: .appModule)) {
                                state.bitnetDefaultModel = modelId
                                Task { await ConfigStore.shared.saveFromState() }
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                        // Delete model button (always available)
                        Button(role: .destructive) {
                            deleteModel(modelId)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "bitnet_delete_model_help", bundle: .appModule))
                    }
                }

                // Available to download
                let notInstalled = BitNetKit.modelRegistry.filter { model in
                    !installedModels.contains(model.modelId)
                }
                if !notInstalled.isEmpty {
                    Text(String(localized: "bitnet_available_models", bundle: .appModule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    ForEach(notInstalled) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                HStack(spacing: 4) {
                                    Text(model.displayName)
                                        .font(.callout)
                                    if !model.isInstruct {
                                        Text(String(localized: "bitnet_base_no_chat", bundle: .appModule))
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(.orange.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text("\(model.parameters) \u{2022} \(model.sizeOnDisk)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isDownloadingModel && downloadModelId == model.modelId {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Button(String(localized: "bitnet_download_button", bundle: .appModule)) {
                                    downloadModel(model)
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                // Download progress log (stays visible after completion/failure)
                if !downloadLog.isEmpty {
                    InstallLogTextView(lines: downloadLog)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 8)

                    if !isDownloadingModel && downloadError == nil {
                        Button(String(localized: "bitnet_dismiss_log", bundle: .appModule)) {
                            downloadLog = []
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
                    }
                }

                // Download error
                if let downloadError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(downloadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                        Spacer()
                        Button(String(localized: "bitnet_dismiss_log", bundle: .appModule)) {
                            self.downloadError = nil
                            downloadLog = []
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)

            sectionDivider()

            // Inference Settings
            sectionHeader(String(localized: "bitnet_inference_header", bundle: .appModule))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "bitnet_threads", bundle: .appModule))
                        .frame(width: 120, alignment: .leading)
                    TextField("", value: $state.bitnetThreads, format: .number)
                        .mcclawTextField()
                        .frame(width: 80)
                    Text("(\(ProcessInfo.processInfo.activeProcessorCount) \(String(localized: "bitnet_available_cores", bundle: .appModule)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(String(localized: "bitnet_context_size", bundle: .appModule))
                        .frame(width: 120, alignment: .leading)
                    TextField("", value: $state.bitnetContextSize, format: .number)
                        .mcclawTextField()
                        .frame(width: 80)
                    Text(String(localized: "bitnet_tokens_label", bundle: .appModule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(String(localized: "bitnet_max_tokens", bundle: .appModule))
                        .frame(width: 120, alignment: .leading)
                    TextField("", value: $state.bitnetMaxTokens, format: .number)
                        .mcclawTextField()
                        .frame(width: 80)
                    Text(String(localized: "bitnet_tokens_label", bundle: .appModule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(String(localized: "bitnet_temperature", bundle: .appModule))
                        .frame(width: 120, alignment: .leading)
                    TextField("", value: $state.bitnetTemperature, format: .number)
                        .mcclawTextField()
                        .frame(width: 80)
                }

                HStack {
                    Text(String(localized: "bitnet_server_port", bundle: .appModule))
                        .frame(width: 120, alignment: .leading)
                    TextField("", value: $state.bitnetServerPort, format: .number)
                        .mcclawTextField()
                        .frame(width: 80)
                }

                HStack {
                    Text(String(localized: "bitnet_server_mode", bundle: .appModule))
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $state.bitnetAlwaysOn) {
                        Text(String(localized: "bitnet_server_always_on", bundle: .appModule))
                            .tag(true)
                        Text(String(localized: "bitnet_server_on_demand", bundle: .appModule))
                            .tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                Text(String(localized: "bitnet_server_mode_description", bundle: .appModule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .onChange(of: appState.bitnetThreads) { Task { await ConfigStore.shared.saveFromState() } }
            .onChange(of: appState.bitnetContextSize) { Task { await ConfigStore.shared.saveFromState() } }
            .onChange(of: appState.bitnetMaxTokens) { Task { await ConfigStore.shared.saveFromState() } }
            .onChange(of: appState.bitnetTemperature) { Task { await ConfigStore.shared.saveFromState() } }
            .onChange(of: appState.bitnetServerPort) { Task { await ConfigStore.shared.saveFromState() } }
            .onChange(of: appState.bitnetAlwaysOn) { Task { await ConfigStore.shared.saveFromState() } }

            sectionDivider()

            // Uninstall
            Button(role: .destructive) {
                loadManifestForUninstall()
            } label: {
                Label(String(localized: "bitnet_uninstall_button", bundle: .appModule), systemImage: "trash")
            }
            .padding(.top, 8)
            .sheet(isPresented: $showUninstallConfirm) {
                uninstallConfirmSheet
            }
        }
        .task {
            refreshInstalledModels()
        }
    }

    // MARK: - Install Progress

    private var installProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text(String(localized: "bitnet_installing", bundle: .appModule))
                    .font(.callout)
            }

            InstallLogTextView(lines: installLog)
                .frame(height: 400)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 8)
    }

    // MARK: - Uninstall Confirm Sheet

    private var uninstallConfirmSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "bitnet_uninstall_title", bundle: .appModule))
                .font(.headline)

            Text(String(localized: "bitnet_uninstall_description", bundle: .appModule))
                .font(.callout)
                .foregroundStyle(.secondary)

            // Always removed
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "bitnet_will_remove", bundle: .appModule))
                    .font(.caption.weight(.semibold))
                Text("\u{2022} BitNet repository (~/.mcclaw/bitnet)")
                    .font(.caption)
                Text("\u{2022} Conda environment (mcclaw-bitnet)")
                    .font(.caption)
                Text("\u{2022} \(String(localized: "bitnet_all_models", bundle: .appModule)) (\(installedModels.count))")
                    .font(.caption)
                Text("\u{2022} \(String(localized: "bitnet_compiled_kernels", bundle: .appModule))")
                    .font(.caption)
                if FileManager.default.fileExists(atPath: BitNetKit.Paths.cmakeBin) {
                    Text("\u{2022} CMake (~/.mcclaw/tools/cmake)")
                        .font(.caption)
                }
                if FileManager.default.fileExists(atPath: BitNetKit.Paths.hfCliBin) {
                    Text("\u{2022} HuggingFace CLI (~/.hf-cli)")
                        .font(.caption)
                }
            }

            // Prerequisites installed by McClaw
            if let manifest, !manifest.mcclawInstalledPrerequisites.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "bitnet_optional_remove", bundle: .appModule))
                        .font(.caption.weight(.semibold))
                    Text(String(localized: "bitnet_optional_remove_warning", bundle: .appModule))
                        .font(.caption)
                        .foregroundStyle(.orange)

                    ForEach(manifest.mcclawInstalledPrerequisites, id: \.name) { item in
                        Toggle(isOn: Binding(
                            get: { prereqsToRemove.contains(item.name) },
                            set: { if $0 { prereqsToRemove.insert(item.name) } else { prereqsToRemove.remove(item.name) } }
                        )) {
                            Text("\(item.name) (\(item.record.installMethod ?? "brew"))")
                                .font(.caption)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button(String(localized: "bitnet_cancel", bundle: .appModule)) {
                    showUninstallConfirm = false
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "bitnet_uninstall_confirm", bundle: .appModule), role: .destructive) {
                    performUninstall()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    // MARK: - Actions

    private func checkPrerequisites() async {
        var searchPaths = [
            BitNetKit.Paths.cmakeBinDir, // McClaw-installed CMake
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
            "\(NSHomeDirectory())/miniforge3/bin",
            "\(NSHomeDirectory())/miniconda3/bin",
            "\(NSHomeDirectory())/anaconda3/bin",
            "\(NSHomeDirectory())/.local/bin",
        ]
        var results: [(name: String, displayName: String, present: Bool)] = []
        for prereq in BitNetKit.prerequisites {
            let found = searchPaths.contains(where: { dir in
                FileManager.default.isExecutableFile(atPath: "\(dir)/\(prereq.name)")
            })
            results.append((prereq.name, prereq.displayName, found))
        }
        prerequisiteStatuses = results
    }

    private func startInstallation() {
        isInstalling = true
        installLog = []

        // Create a dummy provider info for the installer
        let bitnetProvider = CLIProviderInfo(
            id: "bitnet",
            displayName: "BitNet",
            binaryPath: nil,
            version: nil,
            isInstalled: false,
            isAuthenticated: false,
            installMethod: .multiStep(steps: []),  // Will be filled by CLIDetector
            supportedModels: [],
            capabilities: CLICapabilities(
                supportsStreaming: false, supportsToolUse: false, supportsVision: false,
                supportsThinking: false, supportsConversation: true, maxContextTokens: 2048
            ),
            isExperimental: true
        )

        Task {
            // Re-detect to get the actual install steps
            let detector = CLIDetector()
            let allCLIs = await detector.scan()
            let bitnet = allCLIs.first(where: { $0.id == "bitnet" }) ?? bitnetProvider

            let stream = await installer.install(provider: bitnet)
            for await line in stream {
                await MainActor.run {
                    installLog.append(line)
                }
            }
            // Re-scan CLIs so BitNet appears as installed everywhere
            let updatedCLIs = await detector.scan()
            await MainActor.run {
                appState.availableCLIs = updatedCLIs
                isInstalling = false
                refreshInstalledModels()
            }
        }
    }

    private func refreshInstalledModels() {
        installedModels = BitNetKit.listInstalledModels()
    }

    private func downloadModel(_ model: BitNetKit.ModelInfo) {
        isDownloadingModel = true
        downloadModelId = model.modelId
        downloadLog = []
        downloadError = nil

        Task.detached { [installer] in
            let home = BitNetKit.Paths.home
            let fm = FileManager.default

            // --- 1. Find conda ---
            let condaPaths = [
                "\(NSHomeDirectory())/miniforge3/bin/conda",
                "\(NSHomeDirectory())/miniconda3/bin/conda",
                "\(NSHomeDirectory())/anaconda3/bin/conda",
                "/opt/homebrew/bin/conda",
                "/usr/local/bin/conda",
            ]
            guard let conda = condaPaths.first(where: { fm.isExecutableFile(atPath: $0) }) else {
                await MainActor.run {
                    downloadError = "conda not found. Install miniforge first."
                    isDownloadingModel = false
                    downloadModelId = nil
                }
                return
            }
            let condaBinDir = URL(fileURLWithPath: conda).deletingLastPathComponent().path

            await MainActor.run {
                downloadLog.append("[\u{2713}] Found conda at \(conda)")
            }

            // --- 2. Ensure Homebrew, cmake, and llvm@18 are available ---
            let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            var brew = brewPaths.first(where: { fm.isExecutableFile(atPath: $0) })

            if brew == nil {
                // Homebrew requires sudo, so we open Terminal for the user to install it
                await MainActor.run {
                    downloadLog.append("[ERROR] Homebrew is required but not installed.")
                    downloadLog.append("    A Terminal window will open to install it.")
                    downloadLog.append("    After installation, click the download button again.")
                    downloadError = String(localized: "bitnet_brew_not_found", bundle: .appModule)
                    isDownloadingModel = false
                    downloadModelId = nil
                }
                // Open Terminal with the Homebrew install command
                let osascript = Process()
                osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                osascript.arguments = [
                    "-e",
                    "tell application \"Terminal\" to do script \"/bin/bash -c \\\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\\"\"",
                    "-e",
                    "tell application \"Terminal\" to activate",
                ]
                try? osascript.run()
                return
            } else {
                await MainActor.run {
                    downloadLog.append("[\u{2713}] Found Homebrew at \(brew!)")
                }
            }

            // At this point brew is guaranteed non-nil (we either found it or installed it)
            let brewPath = brew!
            let brewBinDir = URL(fileURLWithPath: brewPath).deletingLastPathComponent().path

            // cmake
            let cmakePath = "\(brewBinDir)/cmake"
            if !fm.isExecutableFile(atPath: cmakePath) {
                await MainActor.run {
                    downloadLog.append("[\u{25B6}] Installing cmake via Homebrew...")
                }
                let cmakeInstall = Process()
                cmakeInstall.executableURL = URL(fileURLWithPath: brewPath)
                cmakeInstall.arguments = ["install", "cmake"]
                cmakeInstall.standardOutput = FileHandle.nullDevice
                cmakeInstall.standardError = FileHandle.nullDevice
                try? cmakeInstall.run()
                cmakeInstall.waitUntilExit()
                if cmakeInstall.terminationStatus == 0 {
                    await MainActor.run {
                        downloadLog.append("[\u{2713}] cmake installed")
                    }
                } else {
                    await MainActor.run {
                        downloadError = "Failed to install cmake via Homebrew"
                        isDownloadingModel = false
                        downloadModelId = nil
                    }
                    return
                }
            } else {
                await MainActor.run {
                    downloadLog.append("[\u{2713}] cmake already installed")
                }
            }

            // llvm@18
            let llvmBinDir = "\(brewBinDir)/../opt/llvm@18/bin"
            let clangPath = "\(llvmBinDir)/clang"
            if !fm.isExecutableFile(atPath: clangPath) {
                await MainActor.run {
                    downloadLog.append("[\u{25B6}] Installing LLVM 18 via Homebrew...")
                }
                let llvmInstall = Process()
                llvmInstall.executableURL = URL(fileURLWithPath: brewPath)
                llvmInstall.arguments = ["install", "llvm@18"]
                llvmInstall.standardOutput = FileHandle.nullDevice
                llvmInstall.standardError = FileHandle.nullDevice
                try? llvmInstall.run()
                llvmInstall.waitUntilExit()
                if llvmInstall.terminationStatus == 0 {
                    await MainActor.run {
                        downloadLog.append("[\u{2713}] LLVM 18 installed")
                    }
                } else {
                    await MainActor.run {
                        downloadError = "Failed to install llvm@18 via Homebrew"
                        isDownloadingModel = false
                        downloadModelId = nil
                    }
                    return
                }
            } else {
                await MainActor.run {
                    downloadLog.append("[\u{2713}] LLVM 18 already installed")
                }
            }

            // --- 3. Ensure conda env exists ---
            let condaEnv = BitNetKit.condaEnvironment
            let condaEnvPath = URL(fileURLWithPath: conda)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("envs/\(condaEnv)").path

            if !fm.fileExists(atPath: condaEnvPath) {
                await MainActor.run {
                    downloadLog.append("[\u{25B6}] Creating conda environment '\(condaEnv)'...")
                }
                let createProcess = Process()
                createProcess.executableURL = URL(fileURLWithPath: conda)
                createProcess.arguments = ["create", "-n", condaEnv, "python=\(BitNetKit.pythonVersion)", "-y"]
                createProcess.standardOutput = FileHandle.nullDevice
                createProcess.standardError = FileHandle.nullDevice
                try? createProcess.run()
                createProcess.waitUntilExit()

                if createProcess.terminationStatus == 0 {
                    await MainActor.run {
                        downloadLog.append("[\u{2713}] Conda environment created")
                    }
                } else {
                    await MainActor.run {
                        downloadError = "Failed to create conda environment '\(condaEnv)'"
                        isDownloadingModel = false
                        downloadModelId = nil
                    }
                    return
                }
            }

            // --- 4. Ensure pip dependencies are installed ---
            let requirementsFile = BitNetKit.Paths.requirements
            if fm.fileExists(atPath: requirementsFile) {
                await MainActor.run {
                    downloadLog.append("[\u{25B6}] Installing Python dependencies...")
                }
                let pipProcess = Process()
                pipProcess.executableURL = URL(fileURLWithPath: conda)
                pipProcess.arguments = ["run", "-n", condaEnv, "pip", "install", "-r", requirementsFile, "-q"]
                pipProcess.currentDirectoryURL = URL(fileURLWithPath: home)
                pipProcess.standardOutput = FileHandle.nullDevice
                pipProcess.standardError = FileHandle.nullDevice
                try? pipProcess.run()
                pipProcess.waitUntilExit()
                await MainActor.run {
                    downloadLog.append("[\u{2713}] Python dependencies ready")
                }
            }

            // --- 5. Ensure huggingface-cli is installed ---
            let hfCheck = Process()
            hfCheck.executableURL = URL(fileURLWithPath: conda)
            hfCheck.arguments = ["run", "-n", condaEnv, "pip", "show", "huggingface-hub"]
            hfCheck.standardOutput = FileHandle.nullDevice
            hfCheck.standardError = FileHandle.nullDevice
            try? hfCheck.run()
            hfCheck.waitUntilExit()
            if hfCheck.terminationStatus != 0 {
                await MainActor.run {
                    downloadLog.append("[\u{25B6}] Installing HuggingFace CLI...")
                }
                let hfInstall = Process()
                hfInstall.executableURL = URL(fileURLWithPath: conda)
                hfInstall.arguments = ["run", "-n", condaEnv, "pip", "install", "huggingface-hub", "-q"]
                hfInstall.standardOutput = FileHandle.nullDevice
                hfInstall.standardError = FileHandle.nullDevice
                try? hfInstall.run()
                hfInstall.waitUntilExit()
                await MainActor.run {
                    downloadLog.append("[\u{2713}] HuggingFace CLI installed")
                }
            }

            // --- 6. Download model + build kernels ---
            await MainActor.run {
                downloadLog.append("[\u{25B6}] Downloading \(model.huggingFaceRepo)...")
                downloadLog.append("    This may take several minutes...")
            }

            let repo = model.huggingFaceRepo
            let modelDir = "models/\(model.modelId)"
            let setupPy = BitNetKit.Paths.setupScript

            // Resolve llvm@18 paths (tutorial: export PATH="/opt/homebrew/opt/llvm@18/bin:$PATH")
            let llvmOptDir = "/opt/homebrew/opt/llvm@18"
            let llvmBinPath = "\(llvmOptDir)/bin"
            let extraPaths = [llvmBinPath, brewBinDir, condaBinDir, "/opt/homebrew/bin", "/usr/local/bin"]
            let pathEnv = (extraPaths + [ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
            // Use login shell with conda hook (exactly like the tutorial)
            // Step 1: Download model
            // Step 2: Build kernels
            let fullShellCommand = """
            eval "$(\(conda) shell.zsh hook)" && \
            conda activate \(condaEnv) && \
            cd \(home) && \
            huggingface-cli download \(repo) --local-dir \(modelDir) && \
            python \(setupPy) -md \(modelDir) -q i2_s
            """
            await MainActor.run {
                downloadLog.append("    Running: conda activate + download + build")
            }

            // Single process: download + build (exactly like the tutorial)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", fullShellCommand]
            process.currentDirectoryURL = URL(fileURLWithPath: home)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
                Task { @MainActor in
                    downloadLog.append(contentsOf: lines)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
                Task { @MainActor in
                    downloadLog.append(contentsOf: lines)
                }
            }

            do {
                try process.run()
            } catch {
                await MainActor.run {
                    downloadError = "Failed to start process: \(error.localizedDescription)"
                    isDownloadingModel = false
                    downloadModelId = nil
                }
                return
            }

            process.waitUntilExit()

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let exitCode = process.terminationStatus

            if exitCode == 0 {
                // Update manifest
                if var manifest = BitNetKit.InstallManifest.load() {
                    manifest.addModel(model.modelId)
                    try? manifest.save()
                }
                await MainActor.run {
                    downloadLog.append("[\u{2713}] Model \(model.displayName) installed successfully!")
                    isDownloadingModel = false
                    downloadModelId = nil
                    refreshInstalledModels()
                }
            } else {
                await MainActor.run {
                    downloadError = "setup_env.py failed with exit code \(exitCode). See log above."
                    downloadLog.append("[ERROR] Process exited with code \(exitCode)")
                    isDownloadingModel = false
                    downloadModelId = nil
                }
            }
        }
    }

    private func deleteModel(_ modelId: String) {
        Task {
            let modelDir = BitNetKit.Paths.modelDir(modelId)
            try? FileManager.default.removeItem(atPath: modelDir)

            // Update manifest
            if var manifest = BitNetKit.InstallManifest.load() {
                manifest.removeModel(modelId)
                try? manifest.save()
            }

            // If this was the default model, clear the selection
            await MainActor.run {
                if appState.bitnetDefaultModel == modelId {
                    appState.bitnetDefaultModel = nil
                    Task { await ConfigStore.shared.saveFromState() }
                }
                refreshInstalledModels()
            }
        }
    }

    private func loadManifestForUninstall() {
        manifest = BitNetKit.InstallManifest.load()
        // Pre-select cmake for removal if McClaw installed it
        prereqsToRemove = []
        if let manifest {
            for item in manifest.mcclawInstalledPrerequisites {
                prereqsToRemove.insert(item.name)
            }
        }
        // Also check for McClaw-installed CMake in tools dir
        if FileManager.default.fileExists(atPath: BitNetKit.Paths.cmakeBin) {
            prereqsToRemove.insert("cmake")
        }
        // Also check for HuggingFace CLI standalone
        if FileManager.default.fileExists(atPath: BitNetKit.Paths.hfCliBin) {
            prereqsToRemove.insert("hf-cli")
        }
        showUninstallConfirm = true
    }

    private func performUninstall() {
        showUninstallConfirm = false
        isUninstalling = true

        Task {
            // Uninstall prerequisites user chose to remove
            for name in prereqsToRemove {
                if name == "cmake" && FileManager.default.fileExists(atPath: BitNetKit.Paths.cmakeBin) {
                    // Remove McClaw-installed CMake from tools dir
                    try? FileManager.default.removeItem(atPath: BitNetKit.Paths.toolsDir + "/cmake")
                } else if name == "hf-cli" && FileManager.default.fileExists(atPath: BitNetKit.Paths.hfCliBin) {
                    // Remove HuggingFace CLI standalone (venv + symlink)
                    try? FileManager.default.removeItem(atPath: BitNetKit.Paths.hfCliHome)
                    try? FileManager.default.removeItem(atPath: BitNetKit.Paths.hfCliBin)
                } else if let record = manifest?.prerequisites[name],
                   let method = record.installMethod {
                    let stream = await installer.uninstallPrerequisite(name: name, installMethod: method)
                    for await _ in stream {}
                }
            }

            // Uninstall core (repo + conda env)
            let bitnetProvider = CLIProviderInfo(
                id: "bitnet",
                displayName: "BitNet",
                binaryPath: nil,
                version: nil,
                isInstalled: true,
                isAuthenticated: false,
                installMethod: .multiStep(steps: []),
                supportedModels: [],
                capabilities: CLICapabilities(
                    supportsStreaming: false, supportsToolUse: false, supportsVision: false,
                    supportsThinking: false, supportsConversation: true, maxContextTokens: 2048
                ),
                isExperimental: true
            )

            let stream = await installer.uninstall(provider: bitnetProvider)
            for await _ in stream {}

            // Stop server if running
            await BitNetServerManager.shared.stop()

            // Re-scan CLIs so BitNet is removed from available providers
            let detector = CLIDetector()
            let updated = await detector.scan()
            await MainActor.run {
                appState.availableCLIs = updated
                isUninstalling = false
                refreshInstalledModels()
            }
        }
    }
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

// MARK: - Install Log NSViewRepresentable

/// Native NSScrollView + NSTextView for the install log.
/// Bypasses SwiftUI nested ScrollView issues — always shows correct height and autoscrolls.
struct InstallLogTextView: NSViewRepresentable {
    let lines: [String]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.backgroundNS

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = NSColor.secondaryLabelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.layer?.masksToBounds = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let newText = lines.joined(separator: "\n")
        let currentText = textView.string

        if newText != currentText {
            textView.string = newText

            // Autoscroll to bottom
            DispatchQueue.main.async {
                let range = NSRange(location: textView.string.count, length: 0)
                textView.scrollRangeToVisible(range)
            }
        }
    }
}
