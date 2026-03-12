import AppKit
import Foundation
import Logging
import McClawKit

/// Handles installation and uninstallation of AI provider CLIs.
actor CLIInstaller {
    private let logger = Logger(label: "ai.mcclaw.cli-installer")

    /// Common paths where npm/brew binaries live (GUI apps don't inherit shell PATH).
    private static let commonPaths: [String] = {
        var paths = [
            BitNetKit.Paths.cmakeBinDir, // McClaw-installed CMake
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(NSHomeDirectory())/.npm-global/bin",
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.nvm/current/bin",
            "\(NSHomeDirectory())/miniforge3/bin",
            "\(NSHomeDirectory())/miniconda3/bin",
            "\(NSHomeDirectory())/anaconda3/bin",
        ]
        // nvm versions
        let nvmVersionsDir = "\(NSHomeDirectory())/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsDir) {
            for version in versions.sorted().reversed() {
                paths.append("\(nvmVersionsDir)/\(version)/bin")
            }
        }
        // pip --user bin paths (macOS puts them in ~/Library/Python/X.Y/bin/)
        let pythonLibDir = "\(NSHomeDirectory())/Library/Python"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: pythonLibDir) {
            for version in versions.sorted().reversed() {
                paths.append("\(pythonLibDir)/\(version)/bin")
            }
        }
        return paths
    }()

    /// Build a PATH string from common paths for use in spawned processes.
    /// GUI apps don't inherit the shell PATH, so we must set it explicitly
    /// so that scripts using `#!/usr/bin/env node` (like npm) can find their interpreter.
    private static let processPath: String = {
        let systemPaths = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        return (commonPaths + systemPaths).joined(separator: ":")
    }()

    /// Find a binary (npm, brew) by scanning common paths.
    private func findBinary(_ name: String) -> String? {
        for dir in Self.commonPaths {
            let fullPath = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    /// Install Homebrew using the official install script.
    /// Returns true if Homebrew was successfully installed.
    private func installHomebrew(
        continuation: AsyncStream<String>.Continuation
    ) async -> Bool {
        // Use the official Homebrew install script in non-interactive mode
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            "NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
        ]
        var env = ProcessInfo.processInfo.environment
        env["NONINTERACTIVE"] = "1"
        env["PATH"] = Self.processPath
        process.environment = env
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            for try await line in pipe.fileHandleForReading.bytes.lines {
                continuation.yield(line)
            }

            process.waitUntilExit()

            if process.terminationStatus == 0 {
                continuation.yield("  [\u{2713}] Homebrew installed successfully")
                return true
            } else {
                continuation.yield("  [!] Homebrew installation failed (may require admin password)")
                return false
            }
        } catch {
            continuation.yield("  [!] Could not run Homebrew installer: \(error.localizedDescription)")
            return false
        }
    }

    /// Resolve the package name for a provider.
    private func npmPackage(for id: String) -> String {
        switch id {
        case "claude": "@anthropic-ai/claude-code"
        case "gemini": "@google/gemini-cli"
        case "agent-browser": "agent-browser"
        default: id
        }
    }

    /// Open a URL in the user's default browser.
    private nonisolated func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Install a CLI provider using its preferred method.
    func install(provider: CLIProviderInfo) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let resolved: (binary: String, args: [String])

                switch provider.installMethod {
                case .npm:
                    var npmPath = findBinary("npm")

                    // Auto-install Node.js via Homebrew if npm is missing
                    if npmPath == nil {
                        var brewPath = findBinary("brew")

                        // Auto-install Homebrew if missing
                        if brewPath == nil {
                            continuation.yield("npm not found. Installing Homebrew first...")
                            let brewInstalled = await installHomebrew(continuation: continuation)
                            if brewInstalled {
                                brewPath = findBinary("brew")
                            }
                        }

                        if let brewPath {
                            continuation.yield("Installing Node.js via Homebrew...")
                            let success = await runProcessSync(
                                binary: brewPath,
                                args: ["install", "node"],
                                continuation: continuation
                            )
                            if success {
                                npmPath = findBinary("npm")
                            }
                        }
                    }

                    guard let npm = npmPath else {
                        continuation.yield("Node.js is required but not installed.")
                        continuation.yield("Opening the Node.js download page...")
                        continuation.yield("Install Node.js, then retry the installation.")
                        openURL("https://nodejs.org/en/download")
                        continuation.finish()
                        return
                    }
                    let pkg = npmPackage(for: provider.id)
                    resolved = (npm, ["install", "-g", pkg])

                case .homebrew:
                    var brewPath = findBinary("brew")

                    // Auto-install Homebrew if missing
                    if brewPath == nil {
                        continuation.yield("Homebrew not found. Installing Homebrew...")
                        let brewInstalled = await installHomebrew(continuation: continuation)
                        if brewInstalled {
                            brewPath = findBinary("brew")
                        }
                    }

                    guard let brew = brewPath else {
                        continuation.yield("Homebrew is required but could not be installed automatically.")
                        continuation.yield("Opening the Homebrew install page...")
                        continuation.yield("Install Homebrew, then retry the installation.")
                        openURL("https://brew.sh")
                        continuation.finish()
                        return
                    }
                    let formula = provider.id == "chatgpt" ? "chatgpt" : provider.id
                    resolved = (brew, ["install", formula])

                case .multiStep(let steps):
                    await installMultiStep(
                        provider: provider,
                        steps: steps,
                        continuation: continuation
                    )
                    continuation.finish()
                    return

                default:
                    continuation.yield("Manual installation required for \(provider.displayName)")
                    continuation.finish()
                    return
                }

                continuation.yield("Installing \(provider.displayName)...")
                continuation.yield("Using: \(resolved.binary) \(resolved.args.joined(separator: " "))")
                logger.info("Installing \(provider.id) via \(resolved.binary)")

                let installOk = await runProcessSync(
                    binary: resolved.binary,
                    args: resolved.args,
                    continuation: continuation
                )

                if installOk {
                    // Post-install: agent-browser needs Playwright's Chromium browser
                    if provider.id == "agent-browser", let npxPath = findBinary("npx") {
                        continuation.yield("Downloading Chromium browser (required by Agent Browser)...")
                        let chromiumOk = await runProcessSync(
                            binary: npxPath,
                            args: ["playwright", "install", "chromium"],
                            continuation: continuation
                        )
                        if chromiumOk {
                            continuation.yield("Chromium browser downloaded successfully.")
                        } else {
                            continuation.yield("Warning: Chromium download failed. Run 'npx playwright install chromium' manually.")
                        }
                    }
                    continuation.yield("\(provider.displayName) installed successfully.")
                    logger.info("Installation succeeded for \(provider.id)")
                } else {
                    continuation.yield("Installation failed for \(provider.displayName).")
                    logger.error("Installation failed for \(provider.id)")
                }

                continuation.finish()
            }
        }
    }

    /// Uninstall a CLI provider.
    func uninstall(provider: CLIProviderInfo) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let resolved: (binary: String, args: [String])

                switch provider.installMethod {
                case .npm:
                    guard let npmPath = findBinary("npm") else {
                        continuation.yield("npm not found. Cannot uninstall.")
                        continuation.finish()
                        return
                    }
                    let pkg = npmPackage(for: provider.id)
                    resolved = (npmPath, ["uninstall", "-g", pkg])

                case .homebrew:
                    guard let brewPath = findBinary("brew") else {
                        continuation.yield("Homebrew not found. Cannot uninstall.")
                        continuation.finish()
                        return
                    }
                    let formula = provider.id == "chatgpt" ? "chatgpt" : provider.id
                    resolved = (brewPath, ["uninstall", formula])

                case .multiStep:
                    if provider.id == "bitnet" {
                        await uninstallBitNetCore(continuation: continuation)
                    } else {
                        continuation.yield("Manual uninstallation required for \(provider.displayName)")
                    }
                    continuation.finish()
                    return

                default:
                    continuation.yield("Manual uninstallation required for \(provider.displayName)")
                    continuation.finish()
                    return
                }

                continuation.yield("Uninstalling \(provider.displayName)...")
                logger.info("Uninstalling \(provider.id) via \(resolved.binary)")

                await runProcess(
                    binary: resolved.binary,
                    args: resolved.args,
                    successMessage: "\(provider.displayName) uninstalled successfully.",
                    failurePrefix: "Uninstall",
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Multi-Step Installation

    /// Run a multi-step installation (e.g. BitNet).
    /// Tracks what was installed via InstallManifest for clean uninstallation.
    private func installMultiStep(
        provider: CLIProviderInfo,
        steps: [InstallStep],
        continuation: AsyncStream<String>.Continuation
    ) async {
        continuation.yield("Installing \(provider.displayName) (\(steps.count) steps)...")
        logger.info("Starting multi-step install for \(provider.id)")

        var manifest = BitNetKit.InstallManifest()

        // Check prerequisites first (for BitNet)
        if provider.id == "bitnet" {
            continuation.yield("Checking prerequisites...")
            for prereq in BitNetKit.prerequisites {
                let binary = findBinary(prereq.name)
                let isPresent = binary != nil

                if isPresent {
                    continuation.yield("  [\u{2713}] \(prereq.displayName) found")
                    manifest.recordPrerequisite(
                        name: prereq.name,
                        wasPresent: true,
                        installedByMcClaw: false
                    )
                } else if prereq.directInstallScript != nil || prereq.installCommand != nil {
                    continuation.yield("  [!] \(prereq.displayName) not found. Installing...")
                    var installed = false
                    var method = "direct"

                    // Try direct install script first (no Homebrew needed)
                    if let script = prereq.directInstallScript {
                        continuation.yield("  Installing \(prereq.displayName) directly...")
                        installed = await runProcessSync(
                            binary: "/bin/bash",
                            args: ["-c", script],
                            continuation: continuation
                        )
                        // Verify the binary is now findable (may be in paths not in commonPaths)
                        if installed && findBinary(prereq.name) == nil {
                            var extraPaths = [
                                "\(NSHomeDirectory())/miniforge3/bin",
                                "\(NSHomeDirectory())/miniconda3/bin",
                                "\(NSHomeDirectory())/anaconda3/bin",
                                "\(NSHomeDirectory())/.local/bin",
                            ]
                            // pip --user bin paths (macOS: ~/Library/Python/X.Y/bin/)
                            let pythonLibDir = "\(NSHomeDirectory())/Library/Python"
                            if let versions = try? FileManager.default.contentsOfDirectory(atPath: pythonLibDir) {
                                for version in versions {
                                    extraPaths.append("\(pythonLibDir)/\(version)/bin")
                                }
                            }
                            let found = extraPaths.contains { dir in
                                FileManager.default.isExecutableFile(atPath: "\(dir)/\(prereq.name)")
                            }
                            if !found {
                                installed = false
                            }
                        }
                    }

                    // Fallback to Homebrew if direct install failed or wasn't available
                    if !installed, let installCmd = prereq.installCommand {
                        method = installCmd
                        if let brewPath = findBinary("brew") {
                            let parts = installCmd.split(separator: " ").map(String.init)
                            let brewArgs = Array(parts.dropFirst()) // Drop "brew"
                            installed = await runProcessSync(
                                binary: brewPath,
                                args: brewArgs,
                                continuation: continuation
                            )
                        } else {
                            continuation.yield("  Homebrew not available, skipping brew fallback.")
                        }
                    }

                    manifest.recordPrerequisite(
                        name: prereq.name,
                        wasPresent: false,
                        installedByMcClaw: installed,
                        installMethod: method
                    )
                    if !installed {
                        continuation.yield("Failed to install \(prereq.displayName). Aborting.")
                        return
                    }
                    continuation.yield("  [\u{2713}] \(prereq.displayName) installed")
                } else {
                    continuation.yield("  [!] \(prereq.displayName) not found and cannot be auto-installed. Aborting.")
                    return
                }
            }
        }

        // Execute each step
        for (index, step) in steps.enumerated() {
            continuation.yield("[\(index + 1)/\(steps.count)] \(step.description)...")

            // Skip if already done (e.g. repo already cloned)
            if step.id == "clone" && FileManager.default.fileExists(atPath: BitNetKit.Paths.home) {
                continuation.yield("  Skipped (already exists)")
                manifest.components.repositoryInstalled = true
                continue
            }

            guard let binary = step.command.first else {
                continuation.yield("  Error: empty command")
                continue
            }

            let args = Array(step.command.dropFirst())
            let binaryPath = findBinary(binary) ?? binary

            let success: Bool
            if let workDir = step.workingDirectory {
                success = await runProcessSyncWithWorkDir(
                    binary: binaryPath,
                    args: args,
                    workingDirectory: workDir,
                    continuation: continuation
                )
            } else {
                success = await runProcessSync(
                    binary: binaryPath,
                    args: args,
                    continuation: continuation
                )
            }

            if success {
                continuation.yield("  [\u{2713}] \(step.description) completed")
                // Update manifest based on step
                switch step.id {
                case "clone": manifest.components.repositoryInstalled = true
                case "conda-create": manifest.components.condaEnvCreated = true
                case "download-model": manifest.addModel("BitNet-b1.58-2B-4T")
                case "download-and-build": manifest.addModel("Falcon3-3B-Instruct-1.58bit")
                default: break
                }
            } else {
                continuation.yield("  [\u{2717}] \(step.description) failed")
                if step.canRetry {
                    continuation.yield("  Retrying...")
                    let retryOk: Bool
                    if let workDir = step.workingDirectory {
                        retryOk = await runProcessSyncWithWorkDir(
                            binary: binaryPath,
                            args: args,
                            workingDirectory: workDir,
                            continuation: continuation
                        )
                    } else {
                        retryOk = await runProcessSync(
                            binary: binaryPath,
                            args: args,
                            continuation: continuation
                        )
                    }
                    if !retryOk {
                        continuation.yield("Installation failed at step: \(step.description)")
                        // Save partial manifest so we can clean up
                        try? manifest.save()
                        return
                    }
                } else {
                    continuation.yield("Installation failed at step: \(step.description)")
                    try? manifest.save()
                    return
                }
            }
        }

        // Save manifest
        do {
            try manifest.save()
            continuation.yield("\(provider.displayName) installed successfully.")
            logger.info("Multi-step install succeeded for \(provider.id)")
        } catch {
            continuation.yield("Warning: could not save install manifest: \(error.localizedDescription)")
        }
    }

    /// Uninstall BitNet core components (repo + conda env).
    /// Prerequisites are handled separately by the UI (user chooses which to remove).
    private func uninstallBitNetCore(
        continuation: AsyncStream<String>.Continuation
    ) async {
        continuation.yield("Uninstalling BitNet...")

        // 1. Remove conda environment
        if let condaPath = findBinary("conda") {
            continuation.yield("Removing conda environment '\(BitNetKit.condaEnvironment)'...")
            let args = Array(BitNetKit.buildCondaRemoveArgs().dropFirst())
            let success = await runProcessSync(
                binary: condaPath,
                args: args,
                continuation: continuation
            )
            if success {
                continuation.yield("  [\u{2713}] Conda environment removed")
            } else {
                continuation.yield("  [!] Could not remove conda environment")
            }
        }

        // 2. Remove BitNet directory
        let home = BitNetKit.Paths.home
        if FileManager.default.fileExists(atPath: home) {
            continuation.yield("Removing BitNet directory...")
            do {
                try FileManager.default.removeItem(atPath: home)
                continuation.yield("  [\u{2713}] BitNet directory removed")
            } catch {
                continuation.yield("  [!] Could not remove directory: \(error.localizedDescription)")
            }
        }

        // Manifest is inside the BitNet directory, so it's already deleted
        continuation.yield("BitNet uninstalled successfully.")
        logger.info("BitNet uninstalled")
    }

    /// Uninstall a specific BitNet prerequisite that McClaw installed.
    func uninstallPrerequisite(name: String, installMethod: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard let formula = BitNetKit.brewFormula(from: installMethod),
                      let brewPath = findBinary("brew") else {
                    continuation.yield("Cannot uninstall \(name): Homebrew not found or invalid method.")
                    continuation.finish()
                    return
                }

                continuation.yield("Uninstalling \(name) (\(formula))...")
                let args = ["uninstall", formula]
                let success = await runProcessSync(
                    binary: brewPath,
                    args: args,
                    continuation: continuation
                )
                if success {
                    continuation.yield("\(name) uninstalled successfully.")
                } else {
                    continuation.yield("Failed to uninstall \(name).")
                }
                continuation.finish()
            }
        }
    }

    /// Run a process synchronously with a custom working directory.
    private func runProcessSyncWithWorkDir(
        binary: String,
        args: [String],
        workingDirectory: String,
        continuation: AsyncStream<String>.Continuation
    ) async -> Bool {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.environment = ["PATH": Self.processPath, "HOME": NSHomeDirectory()]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            for try await line in pipe.fileHandleForReading.bytes.lines {
                continuation.yield(line)
            }

            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            continuation.yield("Error: \(error.localizedDescription)")
            return false
        }
    }

    /// Run a process synchronously, streaming output, and return whether it succeeded.
    private func runProcessSync(
        binary: String,
        args: [String],
        continuation: AsyncStream<String>.Continuation
    ) async -> Bool {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.environment = ["PATH": Self.processPath, "HOME": NSHomeDirectory()]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            for try await line in pipe.fileHandleForReading.bytes.lines {
                continuation.yield(line)
            }

            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            continuation.yield("Error: \(error.localizedDescription)")
            return false
        }
    }

    /// Run a process and stream output to the continuation.
    private func runProcess(
        binary: String,
        args: [String],
        successMessage: String,
        failurePrefix: String,
        continuation: AsyncStream<String>.Continuation
    ) async {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.environment = ["PATH": Self.processPath, "HOME": NSHomeDirectory()]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            for try await line in pipe.fileHandleForReading.bytes.lines {
                continuation.yield(line)
            }

            process.waitUntilExit()

            if process.terminationStatus == 0 {
                continuation.yield(successMessage)
                logger.info("\(failurePrefix) succeeded for \(binary)")
            } else {
                continuation.yield("\(failurePrefix) failed with exit code \(process.terminationStatus)")
                logger.error("\(failurePrefix) failed for \(binary)")
            }
        } catch {
            continuation.yield("\(failurePrefix) error: \(error.localizedDescription)")
            logger.error("\(failurePrefix) error: \(error)")
        }

        continuation.finish()
    }
}
