import Foundation
import Logging

/// Handles installation of AI provider CLIs.
actor CLIInstaller {
    private let logger = Logger(label: "ai.mcclaw.cli-installer")

    /// Install a CLI provider using its preferred method.
    /// - Parameter provider: The CLI provider to install
    /// - Returns: Stream of installation progress messages
    func install(provider: CLIProviderInfo) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let command: (String, [String])

                switch (provider.id, provider.installMethod) {
                case ("claude", .npm):
                    command = ("/usr/bin/env", ["npm", "install", "-g", "@anthropic-ai/claude-code"])

                case ("chatgpt", .homebrew):
                    command = ("/usr/bin/env", ["brew", "install", "chatgpt"])

                case ("gemini", .npm):
                    command = ("/usr/bin/env", ["npm", "install", "-g", "@google/gemini-cli"])

                case ("ollama", .homebrew):
                    command = ("/usr/bin/env", ["brew", "install", "ollama"])

                case (_, .homebrew):
                    command = ("/usr/bin/env", ["brew", "install", provider.id])

                case (_, .npm):
                    command = ("/usr/bin/env", ["npm", "install", "-g", provider.id])

                default:
                    continuation.yield("Manual installation required for \(provider.displayName)")
                    continuation.finish()
                    return
                }

                continuation.yield("Installing \(provider.displayName)...")
                logger.info("Installing \(provider.id) via \(provider.installMethod)")

                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: command.0)
                process.arguments = command.1
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()

                    for try await line in pipe.fileHandleForReading.bytes.lines {
                        continuation.yield(line)
                    }

                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.yield("\(provider.displayName) installed successfully.")
                        logger.info("\(provider.id) installed successfully")
                    } else {
                        continuation.yield("Installation failed with exit code \(process.terminationStatus)")
                        logger.error("\(provider.id) installation failed")
                    }
                } catch {
                    continuation.yield("Installation error: \(error.localizedDescription)")
                    logger.error("Install error: \(error)")
                }

                continuation.finish()
            }
        }
    }
}
