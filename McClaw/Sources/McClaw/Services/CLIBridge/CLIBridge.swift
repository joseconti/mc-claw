import Foundation
import Logging
import McClawKit

/// Executes AI provider CLIs and streams their output.
/// This is the core differentiator of McClaw: instead of calling APIs directly,
/// it wraps the official CLIs as a GUI frontend.
actor CLIBridge {
    static let shared = CLIBridge()

    private let logger = Logger(label: "ai.mcclaw.cli-bridge")
    private var activeProcess: Process?

    /// Send a message to an AI provider via its CLI and stream the response.
    /// Includes execution approval check before running the process.
    func send(
        message: String,
        provider: CLIProviderInfo,
        model: String? = nil,
        sessionId: String? = nil,
        isResume: Bool = false,
        systemPrompt: String? = nil,
        allowedTools: [String]? = nil
    ) -> AsyncStream<CLIStreamEvent> {
        // BitNet uses REST API server instead of CLI process
        if provider.id == "bitnet" {
            return sendViaBitNet(message: message, model: model, systemPrompt: systemPrompt)
        }

        return AsyncStream { continuation in
            Task {
                guard let binaryPath = provider.binaryPath else {
                    continuation.yield(.error("CLI not installed: \(provider.displayName)"))
                    continuation.yield(.done)
                    continuation.finish()
                    return
                }

                let args = CLIParser.buildArguments(
                    for: provider.id,
                    message: message,
                    model: model,
                    sessionId: sessionId,
                    isResume: isResume,
                    systemPrompt: systemPrompt,
                    allowedTools: allowedTools
                )

                // CLI provider binaries are always approved (they're what McClaw wraps)
                let approvalResult: ExecApprovalResult = .approved

                switch approvalResult {
                case .denied(let reason):
                    continuation.yield(.error("Command denied: \(reason)"))
                    continuation.yield(.done)
                    continuation.finish()
                    return
                case .needsApproval(let command, let resolution):
                    // Request approval from user via UI
                    let request = ExecApprovalRequest(
                        command: binaryPath,
                        arguments: args,
                        resolution: resolution
                    )
                    let decision = await self.requestApproval(request)
                    switch decision {
                    case .deny:
                        continuation.yield(.error("Command denied by user"))
                        continuation.yield(.done)
                        continuation.finish()
                        return
                    case .allowAlways:
                        // Add to allowlist
                        await MainActor.run {
                            ExecApprovals.shared.addAllowlistEntry(
                                pattern: binaryPath,
                                command: command
                            )
                        }
                    case .allowOnce:
                        break // Proceed without adding to allowlist
                    }
                case .approved:
                    break // Proceed
                }

                logger.info("Executing: \(provider.id) with \(args.count) args")

                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = args
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                // Sanitize environment before passing to CLI process
                let isShellWrapper = ["bash", "sh", "zsh"].contains(
                    URL(fileURLWithPath: binaryPath).lastPathComponent
                )
                var env = HostEnvSanitizer.sanitize(isShellWrapper: isShellWrapper)

                // Ensure the binary's directory is in PATH (GUI apps lack nvm/shell PATH)
                let binaryDir = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
                let currentPath = env["PATH"] ?? "/usr/bin:/bin"
                if !currentPath.contains(binaryDir) {
                    env["PATH"] = "\(binaryDir):\(currentPath)"
                }

                process.environment = env

                self.activeProcess = process

                print("[DEBUG] CLIBridge: launching \(binaryPath) with args: \(args)")
                print("[DEBUG] CLIBridge: CLAUDECODE in env? \(env["CLAUDECODE"] != nil)")

                do {
                    try process.run()
                    print("[DEBUG] CLIBridge: process started, PID=\(process.processIdentifier)")

                    // Read stderr concurrently so we can see errors immediately
                    let stderrHandle = stderrPipe.fileHandleForReading
                    let stderrTask = Task.detached {
                        var stderrLines: [String] = []
                        for try await line in stderrHandle.bytes.lines {
                            print("[DEBUG] CLIBridge stderr: \(line.prefix(200))")
                            stderrLines.append(line)
                        }
                        return stderrLines
                    }

                    let handle = stdoutPipe.fileHandleForReading
                    for try await line in handle.bytes.lines {
                        print("[DEBUG] CLIBridge: received line: \(line.prefix(100))")
                        let parsed = CLIParser.parseLine(line, provider: provider.id)
                        // Skip empty passthroughs (ignored verbose events)
                        if case .passthrough(let s) = parsed, s.isEmpty { continue }
                        let event = CLIBridge.mapParserEvent(parsed)
                        continuation.yield(event)
                    }

                    // Process has finished writing (bytes.lines hit EOF).
                    // Wait for process to actually terminate before reading status.
                    process.waitUntilExit()
                    print("[DEBUG] CLIBridge: stream ended, status=\(process.terminationStatus)")
                    if process.terminationStatus != 0 {
                        let stderrLines = (try? await stderrTask.value) ?? []
                        let stderrText = stderrLines.joined(separator: "\n")
                        if !stderrText.isEmpty {
                            print("[DEBUG] CLIBridge: stderr output: \(stderrText.prefix(500))")
                            continuation.yield(.error(stderrText))
                        }
                    }
                    stderrTask.cancel()

                    continuation.yield(.done)
                } catch {
                    print("[DEBUG] CLIBridge: error: \(error)")
                    continuation.yield(.error(error.localizedDescription))
                    continuation.yield(.done)
                }

                self.activeProcess = nil
                continuation.finish()
            }
        }
    }

    // MARK: - BitNet REST Server

    /// Send a message via the BitNet REST API server.
    private func sendViaBitNet(
        message: String,
        model: String?,
        systemPrompt: String?
    ) -> AsyncStream<CLIStreamEvent> {
        AsyncStream { continuation in
            Task {
                let selectedModel = model ?? BitNetKit.defaultModel?.modelId ?? "BitNet-b1.58-2B-4T"

                do {
                    // Validate model supports chat (instruct models only)
                    if let modelInfo = BitNetKit.registryModel(for: selectedModel),
                       !modelInfo.isInstruct {
                        continuation.yield(.error(
                            "\(modelInfo.displayName) is a base model and does not support chat. " +
                            "Please select an Instruct model in Settings → BitNet."
                        ))
                        continuation.yield(.done)
                        continuation.finish()
                        return
                    }

                    // Ensure server is running (on-demand fallback)
                    let server = BitNetServerManager.shared
                    if await !server.isRunning {
                        continuation.yield(.text("Starting BitNet server..."))
                        let (alwaysOn, serverConfig) = await MainActor.run {
                            let s = AppState.shared
                            return (s.bitnetAlwaysOn, BitNetKit.ServerConfig(
                                port: s.bitnetServerPort,
                                threads: s.bitnetThreads,
                                contextSize: s.bitnetContextSize,
                                maxTokens: s.bitnetMaxTokens,
                                temperature: s.bitnetTemperature
                            ))
                        }
                        try await server.start(
                            model: selectedModel,
                            config: serverConfig,
                            trackIdle: !alwaysOn
                        )
                    } else {
                        await server.touch()
                    }

                    // Get stream from server (sets up process)
                    let stream = try await server.chatStream(
                        message: message,
                        systemPrompt: systemPrompt
                    )
                    // Consume stream in a detached task to avoid actor isolation issues
                    let textTask = Task.detached { () -> String in
                        var full = ""
                        for await chunk in stream {
                            continuation.yield(.text(chunk))
                            full += chunk
                        }
                        return full
                    }
                    _ = await textTask.value
                } catch {
                    logger.error("BitNet error: \(error)")
                    continuation.yield(.error(error.localizedDescription))
                }

                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    /// Request user approval for a command execution via the UI dialog.
    private func requestApproval(_ request: ExecApprovalRequest) async -> ExecApprovalDecision {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                ExecApprovals.shared.pendingApproval = request
                // Store the continuation to be resolved by the UI
                CLIBridge.pendingApprovalContinuation = continuation
            }
        }
    }

    /// Continuation for pending approval requests. Set by CLIBridge, resolved by UI.
    @MainActor static var pendingApprovalContinuation: CheckedContinuation<ExecApprovalDecision, Never>?

    /// Called by the UI when the user makes an approval decision.
    @MainActor static func resolveApproval(_ decision: ExecApprovalDecision) {
        pendingApprovalContinuation?.resume(returning: decision)
        pendingApprovalContinuation = nil
        ExecApprovals.shared.pendingApproval = nil
    }

    /// Abort the currently running CLI process.
    func abort() {
        activeProcess?.terminate()
        activeProcess = nil
        logger.info("CLI process aborted")
    }

    /// Map CLIParser.StreamEvent to CLIStreamEvent.
    private static func mapParserEvent(_ event: CLIParser.StreamEvent) -> CLIStreamEvent {
        switch event {
        case .text(let text): .text(text)
        case .toolStart(let name, let id): .toolStart(name: name, id: id)
        case .thinking(let text): .thinking(text)
        case .done: .done
        case .passthrough(let line): .text(line)
        }
    }
}
