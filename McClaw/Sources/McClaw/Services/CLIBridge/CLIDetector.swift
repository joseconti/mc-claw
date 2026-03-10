import Foundation
import Logging

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

        debugLog("scan() complete: \(results.count) total, \(results.filter(\.isInstalled).count) installed")
        return results
    }

    /// Detect a single CLI provider.
    private func detectProvider(_ definition: CLIProviderDefinition) async -> CLIProviderInfo {
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

        return CLIProviderInfo(
            id: definition.id,
            displayName: definition.displayName,
            binaryPath: binaryPath,
            version: version,
            isInstalled: isInstalled,
            isAuthenticated: isAuthenticated,
            installMethod: definition.installMethod,
            supportedModels: [],  // Populated later via CLI query
            capabilities: definition.capabilities
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
}
