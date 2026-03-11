import AppKit
import Foundation
import Logging

/// Handles installation and uninstallation of AI provider CLIs.
actor CLIInstaller {
    private let logger = Logger(label: "ai.mcclaw.cli-installer")

    /// Common paths where npm/brew binaries live (GUI apps don't inherit shell PATH).
    private static let commonPaths: [String] = {
        var paths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(NSHomeDirectory())/.npm-global/bin",
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.nvm/current/bin",
        ]
        let nvmVersionsDir = "\(NSHomeDirectory())/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsDir) {
            for version in versions.sorted().reversed() {
                paths.append("\(nvmVersionsDir)/\(version)/bin")
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
                        if let brewPath = findBinary("brew") {
                            continuation.yield("npm not found. Installing Node.js via Homebrew...")
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
                    guard let brewPath = findBinary("brew") else {
                        continuation.yield("Homebrew is required but not installed.")
                        continuation.yield("Opening the Homebrew install page...")
                        continuation.yield("Install Homebrew, then retry the installation.")
                        openURL("https://brew.sh")
                        continuation.finish()
                        return
                    }
                    let formula = provider.id == "chatgpt" ? "chatgpt" : provider.id
                    resolved = (brewPath, ["install", formula])

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
