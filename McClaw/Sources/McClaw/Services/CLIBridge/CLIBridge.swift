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
        allowedTools: [String]? = nil,
        planMode: Bool = false
    ) -> AsyncStream<CLIStreamEvent> {
        // BitNet uses REST API server instead of CLI process
        if provider.id == "bitnet" {
            return sendViaBitNet(message: message, model: model, systemPrompt: systemPrompt, planMode: planMode)
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
                    allowedTools: allowedTools,
                    planMode: planMode
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

                // Collect stderr in background for error reporting
                let stderrHandle = stderrPipe.fileHandleForReading
                let stderrBuffer = LineBuffer()
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        stderrHandle.readabilityHandler = nil
                        return
                    }
                    if let text = String(data: data, encoding: .utf8) {
                        stderrBuffer.append(text)
                    }
                }

                // Use readabilityHandler for real-time streaming instead of bytes.lines.
                // bytes.lines buffers internally and delivers data late; readabilityHandler
                // fires as soon as data arrives in the pipe.
                let providerId = provider.id
                let lineBuffer = LineBuffer()
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        // EOF — flush remaining buffer
                        let remaining = lineBuffer.flush()
                        if !remaining.isEmpty {
                            let parsed = CLIParser.parseLine(remaining, provider: providerId)
                            if case .passthrough(let s) = parsed, s.isEmpty { /* skip */ } else {
                                continuation.yield(CLIBridge.mapParserEvent(parsed))
                            }
                        }
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        return
                    }
                    if let text = String(data: data, encoding: .utf8) {
                        // Split into lines; the last segment may be incomplete
                        let lines = lineBuffer.feed(text)
                        for line in lines {
                            let parsed = CLIParser.parseLine(line, provider: providerId)
                            if case .passthrough(let s) = parsed, s.isEmpty { continue }
                            continuation.yield(CLIBridge.mapParserEvent(parsed))
                        }
                    }
                }

                do {
                    try process.run()
                    print("[DEBUG] CLIBridge: process started, PID=\(process.processIdentifier)")
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    continuation.yield(.error(error.localizedDescription))
                    continuation.yield(.done)
                    self.activeProcess = nil
                    continuation.finish()
                    return
                }

                // Wait for process in a detached task to avoid blocking the actor
                let processRef = process
                Task.detached {
                    processRef.waitUntilExit()
                    print("[DEBUG] CLIBridge: stream ended, status=\(processRef.terminationStatus)")
                    if processRef.terminationStatus != 0 {
                        let stderrText = stderrBuffer.flush()
                        if !stderrText.isEmpty {
                            print("[DEBUG] CLIBridge: stderr: \(stderrText.prefix(500))")
                            continuation.yield(.error(stderrText))
                        }
                    }
                    continuation.yield(.done)
                    continuation.finish()
                }

                // activeProcess cleared when stream finishes (not here)
            }
        }
    }

    // MARK: - BitNet REST Server

    /// Send a message via the BitNet REST API server.
    private func sendViaBitNet(
        message: String,
        model: String?,
        systemPrompt: String?,
        planMode: Bool = false
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
                    // In plan mode, prepend read-only instructions to system prompt
                    let effectiveSystemPrompt: String?
                    if planMode {
                        let planPrefix = "[PLAN MODE] You are in read-only analysis mode. Do NOT write, edit, or delete files. Do NOT execute commands. Only analyze, read, and create plans."
                        effectiveSystemPrompt = if let sp = systemPrompt { "\(planPrefix)\n\n\(sp)" } else { planPrefix }
                    } else {
                        effectiveSystemPrompt = systemPrompt
                    }
                    let stream = try await server.chatStream(
                        message: message,
                        systemPrompt: effectiveSystemPrompt
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
        case .passthrough(let line): .text(line.isEmpty ? "" : line + "\n")
        }
    }
}

/// Accumulates partial line data from readabilityHandler and splits on newlines.
/// readabilityHandler delivers arbitrary byte chunks that may split across line boundaries.
private final class LineBuffer: Sendable {
    nonisolated(unsafe) var buffer = ""

    /// Feed new text, return complete lines (split by \n). Incomplete trailing data is kept.
    func feed(_ text: String) -> [String] {
        buffer += text
        var lines: [String] = []
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<range.lowerBound])
            lines.append(line)
            buffer = String(buffer[range.upperBound...])
        }
        return lines
    }

    /// Append text to buffer (for stderr collection).
    func append(_ text: String) {
        buffer += text
    }

    /// Return and clear remaining buffer.
    func flush() -> String {
        let result = buffer
        buffer = ""
        return result
    }
}
