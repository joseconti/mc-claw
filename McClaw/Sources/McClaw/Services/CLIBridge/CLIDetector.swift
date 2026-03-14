import Foundation
import Logging
import McClawKit

/// Detects AI provider CLIs installed on the system.
actor CLIDetector {
    private let logger = Logger(label: "ai.mcclaw.cli-detector")

    /// Known CLI providers to scan for.
    private let knownProviders: [CLIProviderDefinition] = [
        CLIProviderDefinition(
            id: "claude",
            displayName: "Claude CLI",
            binaryNames: ["claude"],
            versionFlag: "--version",
            authCheckCommand: ["claude", "auth", "status"],
            installMethod: .npm,
            capabilities: CLICapabilities(
                supportsStreaming: true,
                supportsToolUse: true,
                supportsVision: true,
                supportsThinking: true,
                supportsConversation: true,
                supportsPlanMode: true,
                maxContextTokens: 200_000
            )
        ),
        CLIProviderDefinition(
            id: "chatgpt",
            displayName: "ChatGPT CLI",
            binaryNames: ["chatgpt"],
            versionFlag: "--version",
            authCheckCommand: nil,
            installMethod: .homebrew,
            capabilities: CLICapabilities(
                supportsStreaming: true,
                supportsToolUse: true,
                supportsVision: true,
                supportsThinking: false,
                supportsConversation: true,
                supportsImageGeneration: true,
                supportsPlanMode: true,
                maxContextTokens: 128_000
            )
        ),
        CLIProviderDefinition(
            id: "gemini",
            displayName: "Gemini CLI",
            binaryNames: ["gemini"],
            versionFlag: "--version",
            authCheckCommand: nil,
            installMethod: .npm,
            capabilities: CLICapabilities(
                supportsStreaming: true,
                supportsToolUse: true,
                supportsVision: true,
                supportsThinking: true,
                supportsConversation: true,
                supportsImageGeneration: true,
                supportsPlanMode: true,
                maxContextTokens: 1_000_000
            )
        ),
        CLIProviderDefinition(
            id: "ollama",
            displayName: "Ollama",
            binaryNames: ["ollama"],
            versionFlag: "--version",
            authCheckCommand: nil,
            installMethod: .homebrew,
            capabilities: CLICapabilities(
                supportsStreaming: true,
                supportsToolUse: true,
                supportsVision: true,
                supportsThinking: false,
                supportsConversation: true,
                maxContextTokens: nil
            )
        ),
        CLIProviderDefinition(
            id: "copilot",
            displayName: "GitHub Copilot CLI",
            binaryNames: ["gh"],
            versionFlag: "--version",
            authCheckCommand: nil,
            installMethod: .multiStep(steps: CLIDetector.copilotInstallSteps),
            capabilities: CLICapabilities(
                supportsStreaming: true,
                supportsToolUse: true,
                supportsVision: false,
                supportsThinking: false,
                supportsConversation: true,
                supportsPlanMode: true,
                maxContextTokens: 128_000
            )
        ),
        CLIProviderDefinition(
            id: "agent-browser",
            displayName: "Agent Browser",
            binaryNames: ["agent-browser"],
            versionFlag: "--version",
            authCheckCommand: nil,
            installMethod: .npm,
            capabilities: CLICapabilities(
                supportsStreaming: false,
                supportsToolUse: false,
                supportsVision: false,
                supportsThinking: false,
                supportsConversation: false,
                maxContextTokens: nil
            ),
            isToolCLI: true
        ),
    ]

    /// Write debug info to a log file for diagnosing GUI app issues.
    private nonisolated func debugLog(_ message: String) {
        let logFile = NSHomeDirectory() + "/.mcclaw/cli-detector.log"
        let line = "\(Date()): \(message)\n"
        if let handle = FileHandle(forWritingAtPath: logFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logFile, contents: line.data(using: .utf8))
        }
    }

    /// Scan the system for installed AI CLIs.
    func scan() async -> [CLIProviderInfo] {
        debugLog("scan() starting, knownProviders=\(knownProviders.count)")
        debugLog("NSHomeDirectory=\(NSHomeDirectory())")
        debugLog("commonPaths=\(Self.commonPaths)")
        var results: [CLIProviderInfo] = []

        for provider in knownProviders {
            debugLog("scanning provider '\(provider.id)'...")
            let info = await detectProvider(provider)
            debugLog("provider '\(provider.id)' done - installed=\(info.isInstalled), path=\(info.binaryPath ?? "nil")")
            results.append(info)
        }

        // DashScope: cloud provider, no binary — checks Keychain for API key
        let dashscopeInfo = await detectDashScope()
        debugLog("provider 'dashscope' done - installed=\(dashscopeInfo.isInstalled)")
        results.append(dashscopeInfo)

        // BitNet: custom detection (no binary to scan, checks directory structure)
        let bitnetInfo = await detectBitNet()
        debugLog("provider 'bitnet' done - installed=\(bitnetInfo.isInstalled)")
        results.append(bitnetInfo)

        debugLog("scan() complete: \(results.count) total, \(results.filter(\.isInstalled).count) installed")
        return results
    }

    /// Detect a single CLI provider.
    private func detectProvider(_ definition: CLIProviderDefinition) async -> CLIProviderInfo {
        // GitHub Copilot CLI: binary is `gh` but we need the copilot extension installed
        if definition.id == "copilot" {
            return await detectCopilot(definition)
        }

        // Check if binary exists
        print("[DEBUG]   findBinary for '\(definition.id)'...")
        let binaryPath = await findBinary(names: definition.binaryNames)
        print("[DEBUG]   findBinary result: \(binaryPath ?? "nil")")
        let isInstalled = binaryPath != nil

        // Get version if installed
        var version: String?
        if let path = binaryPath {
            print("[DEBUG]   getVersion for '\(definition.id)'...")
            version = await getVersion(binary: path, flag: definition.versionFlag)
            print("[DEBUG]   version: \(version ?? "nil")")
        }

        // If binary exists and version was retrieved, assume authenticated.
        // Auth-check commands like `claude auth status` can hang without a TTY.
        let isAuthenticated = isInstalled

        // Populate supported models from registry (+ dynamic discovery for Ollama)
        var models = ModelRegistry.models(for: definition.id).map { reg in
            ModelInfo(
                modelId: reg.modelId,
                displayName: reg.displayName,
                provider: reg.provider,
                contextWindow: nil,
                pricing: nil
            )
        }
        if definition.id == "ollama", let path = binaryPath {
            let dynamicModels = await discoverOllamaModels(binaryPath: path)
            let staticIds = Set(models.map(\.modelId))
            let newModels = dynamicModels.filter { !staticIds.contains($0.modelId) }
            models.append(contentsOf: newModels)
        }

        return CLIProviderInfo(
            id: definition.id,
            displayName: definition.displayName,
            binaryPath: binaryPath,
            version: version,
            isInstalled: isInstalled,
            isAuthenticated: isAuthenticated,
            installMethod: definition.installMethod,
            supportedModels: models,
            capabilities: definition.capabilities,
            isToolCLI: definition.isToolCLI,
            isExperimental: definition.isExperimental
        )
    }

    /// Common binary paths that GUI apps may not find via `which` alone.
    private static let commonPaths: [String] = {
        var paths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(NSHomeDirectory())/.npm-global/bin",
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.nvm/current/bin",
        ]
        // Add nvm versioned directories (GUI apps don't inherit shell nvm setup)
        let nvmVersionsDir = "\(NSHomeDirectory())/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsDir) {
            // Sort descending so newest version is checked first
            for version in versions.sorted().reversed() {
                paths.append("\(nvmVersionsDir)/\(version)/bin")
            }
        }
        return paths
    }()

    /// Find a binary by checking common paths first, then falling back to login shell.
    private func findBinary(names: [String]) async -> String? {
        for name in names {
            // 1. Check common hardcoded paths (fast, no shell needed)
            for dir in Self.commonPaths {
                let fullPath = "\(dir)/\(name)"
                let exists = FileManager.default.fileExists(atPath: fullPath)
                let executable = FileManager.default.isExecutableFile(atPath: fullPath)
                if exists || executable {
                    debugLog("  findBinary: checking \(fullPath) exists=\(exists) executable=\(executable)")
                }
                if executable {
                    return fullPath
                }
            }

            // 2. Fallback: run via login shell to inherit full PATH
            debugLog("  findBinary: falling back to 'which \(name)' via login shell")
            if let path = await runCommand("/bin/zsh", arguments: ["-lc", "which \(name)"]) {
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                debugLog("  findBinary: which returned '\(trimmed)'")
                if !trimmed.isEmpty && FileManager.default.isExecutableFile(atPath: trimmed) {
                    return trimmed
                }
            } else {
                debugLog("  findBinary: which returned nil (failed or timeout)")
            }
        }
        return nil
    }

    /// Get version string from a CLI.
    private func getVersion(binary: String, flag: String) async -> String? {
        guard let output = await runCommand(binary, arguments: [flag]) else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n").first
    }

    /// Check authentication status (with short timeout to avoid hanging).
    private func checkAuth(command: [String]) async -> Bool {
        guard let binary = command.first else { return false }
        let args = Array(command.dropFirst())
        let output = await runCommand(binary, arguments: args, timeout: 5)
        // Simple heuristic: if the command succeeds, we're authenticated
        return output != nil
    }

    // MARK: - Ollama Model Discovery

    /// Discover locally installed Ollama models by running `ollama list`.
    private func discoverOllamaModels(binaryPath: String) async -> [ModelInfo] {
        guard let output = await runCommand(binaryPath, arguments: ["list"], timeout: 10) else {
            debugLog("  ollama: failed to run 'ollama list'")
            return []
        }
        let registered = ModelRegistry.parseOllamaList(output)
        debugLog("  ollama: discovered \(registered.count) model(s)")
        return registered.map { reg in
            ModelInfo(
                modelId: reg.modelId,
                displayName: reg.displayName,
                provider: "ollama",
                contextWindow: nil,
                pricing: nil
            )
        }
    }

    // MARK: - GitHub Copilot CLI Detection

    /// Detect GitHub Copilot CLI by checking for `gh` binary and the copilot extension.
    private func detectCopilot(_ definition: CLIProviderDefinition) async -> CLIProviderInfo {
        // 1. Find the `gh` binary
        let ghPath = await findBinary(names: ["gh"])
        debugLog("  copilot: gh binary = \(ghPath ?? "nil")")

        guard let ghPath else {
            debugLog("  copilot: gh not found")
            return copilotProviderInfo(ghPath: nil, installed: false, version: nil, authenticated: false)
        }

        // 2. Check if copilot extension is installed: `gh extension list` should contain "copilot"
        let extList = await runCommand(ghPath, arguments: ["extension", "list"], timeout: 10)
        let hasCopilot = extList?.contains("copilot") ?? false
        debugLog("  copilot: extension installed = \(hasCopilot)")

        guard hasCopilot else {
            debugLog("  copilot: gh found but copilot extension not installed")
            return copilotProviderInfo(ghPath: ghPath, installed: false, version: "gh found, copilot extension missing", authenticated: false)
        }

        // 3. Get gh version
        let version = await getVersion(binary: ghPath, flag: "--version")
        debugLog("  copilot: version = \(version ?? "nil")")

        // 4. Check auth: `gh auth status` succeeds if logged in
        let authOutput = await runCommand(ghPath, arguments: ["auth", "status"], timeout: 5)
        let isAuthenticated = authOutput != nil
        debugLog("  copilot: authenticated = \(isAuthenticated)")

        return copilotProviderInfo(ghPath: ghPath, installed: true, version: version, authenticated: isAuthenticated)
    }

    /// Build CLIProviderInfo for GitHub Copilot CLI.
    private func copilotProviderInfo(ghPath: String?, installed: Bool, version: String?, authenticated: Bool) -> CLIProviderInfo {
        let models = ModelRegistry.models(for: "copilot").map { reg in
            ModelInfo(
                modelId: reg.modelId,
                displayName: reg.displayName,
                provider: "copilot",
                contextWindow: nil,
                pricing: nil
            )
        }

        return CLIProviderInfo(
            id: "copilot",
            displayName: "GitHub Copilot CLI",
            binaryPath: ghPath,
            version: version,
            isInstalled: installed,
            isAuthenticated: authenticated,
            installMethod: .multiStep(steps: Self.copilotInstallSteps),
            supportedModels: models,
            capabilities: CLICapabilities(
                supportsStreaming: true,
                supportsToolUse: true,
                supportsVision: false,
                supportsThinking: false,
                supportsConversation: true,
                supportsPlanMode: true,
                maxContextTokens: 128_000
            )
        )
    }

    /// Multi-step installation for GitHub Copilot CLI.
    /// Step 1: Install GitHub CLI via Homebrew.
    /// Step 2: Install the copilot extension.
    /// Step 3: Authenticate with GitHub.
    static let copilotInstallSteps: [InstallStep] = [
        InstallStep(
            id: "install-gh",
            description: "Install GitHub CLI",
            command: ["/opt/homebrew/bin/brew", "install", "gh"],
            estimatedDuration: 60
        ),
        InstallStep(
            id: "gh-auth",
            description: "Authenticate with GitHub",
            command: ["/opt/homebrew/bin/gh", "auth", "login"],
            estimatedDuration: 30
        ),
        InstallStep(
            id: "install-copilot-ext",
            description: "Install Copilot extension",
            command: ["/opt/homebrew/bin/gh", "extension", "install", "github/gh-copilot"],
            estimatedDuration: 30
        ),
        InstallStep(
            id: "verify-copilot",
            description: "Verify Copilot CLI",
            command: ["/opt/homebrew/bin/gh", "copilot", "--help"],
            estimatedDuration: 5,
            canRetry: false
        ),
    ]

    // MARK: - DashScope Detection

    /// Detect DashScope (Alibaba Cloud) by checking if an API key is stored in Keychain.
    private func detectDashScope() async -> CLIProviderInfo {
        let hasKey = await MainActor.run { AppState.shared.dashscopeAPIKeyStored }

        let models = ModelRegistry.models(for: "dashscope").map { reg in
            ModelInfo(
                modelId: reg.modelId,
                displayName: reg.displayName,
                provider: "dashscope",
                contextWindow: nil,
                pricing: nil
            )
        }

        return CLIProviderInfo(
            id: "dashscope",
            displayName: "DashScope (Alibaba Cloud)",
            binaryPath: nil,
            version: hasKey ? "API" : nil,
            isInstalled: hasKey,
            isAuthenticated: hasKey,
            installMethod: .manual,
            supportedModels: models,
            capabilities: CLICapabilities(
                supportsStreaming: true,
                supportsToolUse: true,
                supportsVision: false,
                supportsThinking: false,
                supportsConversation: true,
                maxContextTokens: 131_072
            )
        )
    }

    // MARK: - BitNet Detection

    /// Detect BitNet installation by checking directory structure and conda env.
    private func detectBitNet() async -> CLIProviderInfo {
        let fm = FileManager.default
        let home = BitNetKit.Paths.home

        // 1. Check if BitNet directory exists
        guard fm.fileExists(atPath: home) else {
            debugLog("  bitnet: home directory not found")
            return bitnetProviderInfo(installed: false, version: nil)
        }

        // 2. Check if inference script exists
        let hasServer = fm.fileExists(atPath: BitNetKit.Paths.serverScript)
        let hasInference = fm.fileExists(atPath: BitNetKit.Paths.inferenceScript)
        guard hasServer || hasInference else {
            debugLog("  bitnet: no inference script found")
            return bitnetProviderInfo(installed: false, version: nil)
        }

        // 3. Check if conda environment exists
        // GUI apps don't inherit shell PATH, so find conda binary directly
        let condaPaths = [
            "\(NSHomeDirectory())/miniforge3/bin/conda",
            "\(NSHomeDirectory())/miniconda3/bin/conda",
            "\(NSHomeDirectory())/anaconda3/bin/conda",
            "/opt/homebrew/bin/conda",
            "/usr/local/bin/conda",
        ]
        var condaCheck: String?
        for condaPath in condaPaths {
            if fm.isExecutableFile(atPath: condaPath) {
                condaCheck = await runCommand(condaPath, arguments: ["env", "list"], timeout: 10)
                if condaCheck != nil { break }
            }
        }
        // Fallback: try login shell (may work if conda init was run)
        if condaCheck == nil {
            condaCheck = await runCommand("/bin/zsh", arguments: ["-lc", "conda env list"], timeout: 10)
        }
        let hasCondaEnv = condaCheck?.contains(BitNetKit.condaEnvironment) ?? false
        if !hasCondaEnv {
            debugLog("  bitnet: conda env '\(BitNetKit.condaEnvironment)' not found")
            return bitnetProviderInfo(installed: false, version: "no conda env")
        }

        // 4. Check if at least one model is downloaded
        let models = BitNetKit.listInstalledModels()
        if models.isEmpty {
            debugLog("  bitnet: no models downloaded")
            return bitnetProviderInfo(installed: false, version: "no models")
        }

        debugLog("  bitnet: installed with \(models.count) model(s)")
        return bitnetProviderInfo(installed: true, version: "1.58-bit (\(models.count) models)")
    }

    /// Build CLIProviderInfo for BitNet with the appropriate install steps.
    private func bitnetProviderInfo(installed: Bool, version: String?) -> CLIProviderInfo {
        CLIProviderInfo(
            id: "bitnet",
            displayName: "BitNet (Local, 1-bit)",
            binaryPath: installed ? BitNetKit.Paths.binary : nil,
            version: version,
            isInstalled: installed,
            isAuthenticated: installed, // No auth needed for local
            installMethod: .multiStep(steps: Self.bitnetInstallSteps),
            supportedModels: [],
            capabilities: CLICapabilities(
                supportsStreaming: false,
                supportsToolUse: false,
                supportsVision: false,
                supportsThinking: false,
                supportsConversation: true,
                maxContextTokens: 2048
            ),
            isExperimental: true
        )
    }

    /// Multi-step installation sequence for BitNet.
    /// Follows the official tutorial: clone → conda → deps → download model → build kernels.
    private static let bitnetInstallSteps: [InstallStep] = [
        // 1. Clone BitNet repo with submodules
        InstallStep(
            id: "clone",
            description: "Clone BitNet repository",
            command: ["git", "clone", "--recursive", "https://github.com/microsoft/BitNet.git", BitNetKit.Paths.home],
            estimatedDuration: 60
        ),
        // 2. Create conda environment (python 3.9)
        InstallStep(
            id: "conda-create",
            description: "Create conda environment",
            command: BitNetKit.buildCondaCreateArgs(),
            estimatedDuration: 30
        ),
        // 3. Install Python dependencies (requirements.txt)
        InstallStep(
            id: "pip-install",
            description: "Install Python dependencies",
            command: BitNetKit.buildPipInstallArgs(),
            condaEnvironment: BitNetKit.condaEnvironment,
            estimatedDuration: 120
        ),
        // 4. Install HuggingFace CLI
        InstallStep(
            id: "hf-cli",
            description: "Install HuggingFace CLI",
            command: BitNetKit.buildHfCliInstallArgs(),
            condaEnvironment: BitNetKit.condaEnvironment,
            estimatedDuration: 30
        ),
        // 5+6. Download model + build kernels in one shell (conda activate via hook)
        InstallStep(
            id: "download-and-build",
            description: "Download model and build kernels",
            command: BitNetKit.buildDownloadAndBuildShellArgs(
                repo: "tiiuae/Falcon3-3B-Instruct-1.58bit",
                modelDir: "models/Falcon3-3B-Instruct-1.58bit"
            ),
            estimatedDuration: 420
        ),
        // 7. Verify llama-cli binary exists
        InstallStep(
            id: "verify",
            description: "Verify installation",
            command: ["/bin/test", "-f", BitNetKit.Paths.binary],
            estimatedDuration: 5,
            canRetry: false
        ),
    ]

    /// Run a shell command and return stdout, or nil on failure.
    /// Dispatches to GCD to avoid blocking Swift concurrency's cooperative thread pool.
    /// Includes a timeout to prevent hanging on commands that wait for input/network.
    private nonisolated func runCommand(_ path: String, arguments: [String], timeout: TimeInterval = 10) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()

                    // Kill process if it exceeds timeout
                    let timer = DispatchSource.makeTimerSource(queue: .global())
                    timer.schedule(deadline: .now() + timeout)
                    timer.setEventHandler {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                    timer.resume()

                    process.waitUntilExit()
                    timer.cancel()

                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        continuation.resume(returning: String(data: data, encoding: .utf8))
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// Internal definition for a known CLI provider.
private struct CLIProviderDefinition {
    let id: String
    let displayName: String
    let binaryNames: [String]
    let versionFlag: String
    let authCheckCommand: [String]?
    let installMethod: CLIInstallMethod
    let capabilities: CLICapabilities
    /// True for optional tool CLIs (not AI providers).
    var isToolCLI: Bool = false
    /// True for experimental providers.
    var isExperimental: Bool = false
}
