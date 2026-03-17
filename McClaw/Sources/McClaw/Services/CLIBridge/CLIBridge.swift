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
    private var watchdogTask: Task<Void, Never>?

    /// Maximum seconds of silence (no stdout output) before killing a hung CLI process.
    private static let streamTimeoutSeconds: TimeInterval = 180 // 3 minutes

    /// Cached login shell environment variables.
    /// GUI apps (.app bundles) don't inherit shell env vars (GEMINI_API_KEY, etc.).
    /// We resolve them once via `zsh -lc env` and merge into process environments.
    private static nonisolated(unsafe) var _cachedShellEnv: [String: String]?
    private static let shellEnvLock = NSLock()

    /// Resolve the user's login shell environment, cached for the app lifetime.
    nonisolated static func resolveShellEnvironment() -> [String: String] {
        shellEnvLock.lock()
        defer { shellEnvLock.unlock() }
        if let cached = _cachedShellEnv { return cached }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "env"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        var env: [String: String] = [:]
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: "\n") {
                    guard let eqIdx = line.firstIndex(of: "=") else { continue }
                    let key = String(line[..<eqIdx])
                    let value = String(line[line.index(after: eqIdx)...])
                    env[key] = value
                }
            }
        } catch {
            // Fallback: empty dict, ProcessInfo.processInfo.environment will be used
        }
        _cachedShellEnv = env
        return env
    }

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
        // DashScope uses REST API (OpenAI-compatible)
        if provider.id == "dashscope" {
            return sendViaDashScope(message: message, model: model, systemPrompt: systemPrompt, planMode: planMode)
        }

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

                // Merge login shell env with process env so CLI tools find API keys
                // (GUI .app bundles don't inherit shell-defined vars like GEMINI_API_KEY)
                let shellEnv = CLIBridge.resolveShellEnvironment()
                let mergedEnv = ProcessInfo.processInfo.environment.merging(shellEnv) { _, shell in shell }
                let isShellWrapper = ["bash", "sh", "zsh"].contains(
                    URL(fileURLWithPath: binaryPath).lastPathComponent
                )
                var env = HostEnvSanitizer.sanitize(env: mergedEnv, isShellWrapper: isShellWrapper)

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
                let watchdog = WatchdogTimer()
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
                    watchdog.touch()
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

                // Start watchdog: kill process if no output for 3 minutes
                let processRef = process
                let timeout = CLIBridge.streamTimeoutSeconds
                self.watchdogTask = Task.detached {
                    while !Task.isCancelled && processRef.isRunning {
                        try? await Task.sleep(for: .seconds(30)) // Check every 30s
                        guard !Task.isCancelled && processRef.isRunning else { break }
                        if watchdog.secondsSinceLastActivity > timeout {
                            print("[WATCHDOG] CLIBridge: killing hung process PID=\(processRef.processIdentifier) after \(Int(timeout))s of silence")
                            continuation.yield(.error("CLI process timed out after \(Int(timeout / 60)) minutes of inactivity"))
                            processRef.terminate()
                            break
                        }
                    }
                }

                // Wait for process in a detached task to avoid blocking the actor
                let watchdogRef = self.watchdogTask
                Task.detached {
                    processRef.waitUntilExit()
                    watchdogRef?.cancel()
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

    // MARK: - DashScope REST API

    /// Send a message via DashScope's OpenAI-compatible streaming API.
    private func sendViaDashScope(
        message: String,
        model: String?,
        systemPrompt: String?,
        planMode: Bool = false
    ) -> AsyncStream<CLIStreamEvent> {
        AsyncStream { continuation in
            Task {
                // Get config from AppState
                let (regionStr, apiKey) = await MainActor.run {
                    let state = AppState.shared
                    let region = state.dashscopeRegion
                    let key = DashScopeKeychainHelper.loadAPIKey()
                    return (region, key)
                }

                guard let apiKey, !apiKey.isEmpty else {
                    continuation.yield(.error("DashScope API key not configured. Go to Settings → DashScope to add your key."))
                    continuation.yield(.done)
                    continuation.finish()
                    return
                }

                let region = DashScopeKit.Region(rawValue: regionStr) ?? .international
                let selectedModel = model ?? DashScopeKit.defaultModelId

                // Build messages
                var messages: [DashScopeKit.ChatMessage] = []

                // System prompt (with plan mode if active)
                let planPrefix = planMode ? "[PLAN MODE] You are in read-only analysis mode. Do NOT write, edit, or delete files. Do NOT execute commands. Only analyze, read, and create plans.\n\n" : ""
                if let sp = systemPrompt, !sp.isEmpty {
                    messages.append(DashScopeKit.ChatMessage(role: .system, content: planPrefix + sp))
                } else if planMode {
                    messages.append(DashScopeKit.ChatMessage(role: .system, content: planPrefix))
                }

                messages.append(DashScopeKit.ChatMessage(role: .user, content: message))

                // Build request
                guard let request = DashScopeKit.buildStreamRequest(
                    region: region,
                    apiKey: apiKey,
                    model: selectedModel,
                    messages: messages
                ) else {
                    continuation.yield(.error("Failed to build DashScope request"))
                    continuation.yield(.done)
                    continuation.finish()
                    return
                }

                logger.info("DashScope: sending to \(region.rawValue) with model \(selectedModel)")

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        // Try to read error body
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        continuation.yield(.error("DashScope API error (\(httpResponse.statusCode)): \(errorBody.prefix(500))"))
                        continuation.yield(.done)
                        continuation.finish()
                        return
                    }

                    // Stream SSE lines
                    for try await line in bytes.lines {
                        let result = DashScopeKit.parseStreamLine(line)
                        switch result {
                        case .text(let text):
                            continuation.yield(.text(text))
                        case .done:
                            break
                        case .error(let msg):
                            continuation.yield(.error(msg))
                        case .skip:
                            continue
                        }
                    }
                } catch {
                    logger.error("DashScope stream error: \(error)")
                    continuation.yield(.error(error.localizedDescription))
                }

                continuation.yield(.done)
                continuation.finish()
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
        watchdogTask?.cancel()
        watchdogTask = nil
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

/// Tracks when the last stdout output was received.
/// Used by the watchdog to detect hung CLI processes.
private final class WatchdogTimer: Sendable {
    nonisolated(unsafe) private var lastActivity: Date = Date()

    /// Reset the timer (called each time stdout receives data).
    func touch() {
        lastActivity = Date()
    }

    /// Seconds elapsed since the last output.
    var secondsSinceLastActivity: TimeInterval {
        Date().timeIntervalSince(lastActivity)
    }
}

// MARK: - DashScope Keychain Helper

/// Simple Keychain helper for DashScope API key, using Security framework directly.
enum DashScopeKeychainHelper {
    private static let service = "com.mcclaw.dashscope"
    private static let account = "api-key"

    /// Save or update the API key in Keychain.
    static func saveAPIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        // Try to update first
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        // If not found, add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// Load the API key from Keychain.
    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete the API key from Keychain.
    static func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
