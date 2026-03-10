import Foundation
import Logging
import McClawKit

/// Maintains a persistent Claude CLI process for background scheduling.
///
/// Uses a PTY (pseudo-terminal) so the CLI activates its interactive mode,
/// enabling slash commands like `/loop`. The PTY is used **only** to register
/// `/loop` commands — we do not parse the PTY output (it's interactive UI,
/// not structured JSON). Task results are handled externally.
///
/// If the process dies, it automatically restarts and re-creates all tasks from disk.
actor BackgroundCLISession {
    static let shared = BackgroundCLISession()

    // MARK: - State

    enum SessionState: Sendable, Equatable {
        case idle
        case starting
        case running
        case restarting
        case stopped
    }

    /// Events emitted by the background session.
    enum SessionEvent: Sendable {
        case error(String)
        case processExited(status: Int32)
        case stateChanged(SessionState)
        /// Fired when Claude CLI confirms a `/loop` schedule was accepted.
        /// The associated string contains the raw confirmation text from the PTY.
        case loopConfirmed(String)
        /// Fired when Claude CLI delivers a scheduled task result (⏺ bullet detected).
        /// The associated string is the cleaned PTY output containing the response.
        case taskCompleted(String)
    }

    private let logger = Logger(label: "ai.mcclaw.background-session")

    private var ptyProcess: PTYProcess?
    private var state: SessionState = .idle
    private var sessionId: String = UUID().uuidString
    private var restartCount = 0
    private var monitorTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<SessionEvent>.Continuation?

    /// Maximum restart attempts before giving up.
    private static let maxRestarts = 5
    /// Delay between restarts (seconds).
    private static let restartDelay: TimeInterval = 3

    private init() {}

    // MARK: - Public API

    /// Current session state.
    var currentState: SessionState { state }

    /// Whether the session has a running Claude process.
    var isRunning: Bool { state == .running }

    /// PID of the current process (for diagnostics).
    var processId: Int32? { ptyProcess?.childPID }

    /// Start the background session. Returns a stream of events.
    /// Safe to call multiple times — only starts if not already running.
    func start() -> AsyncStream<SessionEvent> {
        let stream = AsyncStream<SessionEvent> { continuation in
            self.eventContinuation = continuation
        }

        if state == .running || state == .starting {
            logger.info("BackgroundCLISession already running/starting, skipping")
            return stream
        }

        Task {
            await launchProcess()
        }

        return stream
    }

    /// Stop the background session and terminate the process.
    func stop() {
        state = .stopped
        eventContinuation?.yield(.stateChanged(.stopped))
        monitorTask?.cancel()
        monitorTask = nil
        terminateProcess()
        eventContinuation?.finish()
        eventContinuation = nil
        logger.info("BackgroundCLISession stopped")
    }

    /// Send text to the running Claude process by simulating keyboard input.
    ///
    /// Characters are delivered one at a time with a 30ms delay between each.
    /// This is required because Claude CLI's Ink TUI only activates the `/loop`
    /// slash command handler when the leading `/` arrives as an individual keystroke
    /// on an empty input field. Bulk delivery (bracketed paste, raw stream) bypasses
    /// the slash command handler and the text is routed to the LLM instead.
    @discardableResult
    func sendMessage(_ text: String) async -> Bool {
        guard state == .running, let pty = ptyProcess, pty.isRunning else {
            logger.warning("Cannot send message — session not running")
            return false
        }

        logger.info("Typing to PTY (char-by-char): \(text.prefix(200))")

        // Clear any stale input with Ctrl+U before starting
        pty.write("\u{15}")
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        // Deliver characters one at a time so Ink's key handler sees each keystroke.
        // 30ms per char: fast enough to be snappy, slow enough for Ink to process.
        for char in text {
            pty.write(String(char))
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms
        }

        // Brief pause before Enter so the input is fully rendered before submission
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        pty.write("\r")

        return true
    }

    /// Send an interrupt (Ctrl+C) to the running process.
    func interrupt() {
        guard let pty = ptyProcess, pty.isRunning else { return }
        pty.write("\u{03}") // ETX = Ctrl+C
    }

    /// Schedule a task by sending a `/loop` command to the live Claude process.
    /// - Parameters:
    ///   - interval: Human-readable interval (e.g. "5m", "1h", "30s")
    ///   - message: The task message to execute on each iteration
    /// - Returns: true if the message was sent successfully
    @discardableResult
    func scheduleTask(interval: String, message: String) async -> Bool {
        // /loop is a Claude CLI slash command: /loop <interval> <prompt>
        let loopCommand = "/loop \(interval) \(message)"
        return await sendMessage(loopCommand)
    }

    /// Cancel a previously scheduled `/loop` task by its Claude CLI internal ID.
    /// The ID is extracted from the confirmation text when the task was first scheduled
    /// (e.g. "Scheduled 8772934d (Every 5 minutes)" → ID = "8772934d").
    /// - Parameter claudeTaskId: The hex ID assigned by Claude CLI.
    /// - Returns: true if the cancel command was sent successfully.
    @discardableResult
    func cancelTask(claudeTaskId: String) async -> Bool {
        logger.info("Cancelling Claude task \(claudeTaskId)")
        return await sendMessage("/loop cancel \(claudeTaskId)")
    }

    /// Wait until the PTY output has been silent for the silence threshold, indicating
    /// Claude CLI has finished initializing and is ready for input.
    /// Called by CronJobsStore before sending `/loop` commands after a session restart.
    func waitUntilReady(timeout: TimeInterval = 60) async {
        await ptyProcess?.waitUntilReady(timeout: timeout)
    }

    /// Re-register all persisted scheduled tasks after a restart.
    /// Reads from `~/.mcclaw/schedules.json` and sends `/loop` for each enabled Claude job.
    func restoreScheduledTasks() async {
        let schedulesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw", isDirectory: true)
            .appendingPathComponent("schedules.json")

        guard FileManager.default.fileExists(atPath: schedulesURL.path) else {
            logger.info("No schedules.json found, skipping task restoration")
            return
        }

        do {
            let data = try Data(contentsOf: schedulesURL)
            let jobs = try JSONDecoder().decode([ScheduledJobDefinition].self, from: data)

            let claudeJobs = jobs.filter { job in
                let agent = job.agentId ?? ""
                return job.enabled && (agent.isEmpty || agent == "claude")
            }

            guard !claudeJobs.isEmpty else {
                logger.info("No enabled Claude jobs to restore")
                return
            }

            logger.info("Restoring \(claudeJobs.count) Claude scheduled tasks")

            // Wait until the PTY output has been silent for 3 seconds.
            // This means Claude CLI has finished rendering its UI (trust prompt,
            // welcome screen, etc.) and is waiting for user input.
            // Timeout of 45s covers slow startups (auth, network, trust prompts).
            if let pty = ptyProcess {
                logger.info("Waiting for Claude CLI to become ready (silence detection)...")
                await pty.waitUntilReady(timeout: 60)
                logger.info("Claude CLI ready — sending /loop commands")
            }

            for job in claudeJobs {
                guard let interval = formatScheduleInterval(job.schedule) else { continue }
                let message = extractMessage(from: job.payload)
                guard !message.isEmpty else { continue }

                let sent = await scheduleTask(interval: interval, message: message)
                if sent {
                    logger.info("Restored task '\(job.name ?? job.id)' (\(interval))")
                } else {
                    logger.warning("Failed to restore task '\(job.name ?? job.id)'")
                }

                // Small delay between task creations to avoid overwhelming
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        } catch {
            logger.error("Failed to restore scheduled tasks: \(error.localizedDescription)")
        }
    }

    // MARK: - Process Lifecycle

    /// Launch the Claude CLI process inside a PTY (pseudo-terminal).
    /// No `--output-format` flags — the PTY needs pure interactive mode.
    private func launchProcess() async {
        state = .starting
        eventContinuation?.yield(.stateChanged(.starting))

        // Find Claude binary
        guard let binaryPath = await findClaudeBinary() else {
            state = .idle
            eventContinuation?.yield(.error("Claude CLI not found"))
            eventContinuation?.yield(.stateChanged(.idle))
            return
        }

        let args = CLIParser.buildBackgroundSessionArguments(sessionId: sessionId)

        // Sanitize environment
        let binaryDir = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
        var env = HostEnvSanitizer.sanitize(isShellWrapper: false)
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        if !currentPath.contains(binaryDir) {
            env["PATH"] = "\(binaryDir):\(currentPath)"
        }

        // Create and launch PTY process
        let pty = PTYProcess()

        do {
            try pty.launch(executablePath: binaryPath, arguments: args, environment: env)
        } catch {
            state = .idle
            eventContinuation?.yield(.error("Failed to launch Claude: \(error.localizedDescription)"))
            eventContinuation?.yield(.stateChanged(.idle))
            logger.error("Failed to launch Claude background session: \(error)")
            return
        }

        // Configure terminal for background operation
        pty.configureTerminal()

        // Set up output reading — diagnostics + auto-respond to interactive prompts.
        // The PTY output is interactive UI (prompts, colors, animations),
        // not structured JSON. We don't attempt to parse it for task results.
        // However, we DO detect blocking prompts (trust dialog, permission prompts)
        // and auto-respond so the session can reach the interactive state.
        let sessionLogger = logger
        let ptyRef = pty
        let continuation = eventContinuation
        // Box for task-run deduplication — shared across onData invocations.
        // Uses a class (not actor-isolated) because onData runs on the pty dispatch queue.
        let taskBox = TaskDetectionBox()

        pty.startReading(
            onData: { data in
                if let text = String(data: data, encoding: .utf8) {
                    // Strip ANSI escape codes for readable logging and prompt detection.
                    // The raw PTY output contains colors, cursor movement, etc.
                    let stripped = CLIParser.stripANSI(text)
                    let cleaned = stripped
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        sessionLogger.info("PTY output: \(String(cleaned.prefix(500)))")
                    }

                    // Auto-respond to Claude CLI interactive prompts that block startup.
                    // After ANSI stripping, words may be concatenated (no spaces) because
                    // cursor positioning codes that created visual spacing are removed.
                    // Match without spaces to handle both cases.
                    let lower = stripped.lowercased()
                    let compact = lower.replacingOccurrences(of: " ", with: "")
                    if compact.contains("trustthisfolder") || compact.contains("entertoconfirm")
                        || compact.contains("yes,itrust") || lower.contains("trust this folder") {
                        sessionLogger.info("Detected trust/confirm prompt — auto-confirming with Enter")
                        ptyRef.write("\r")
                        // Reset startup clock: the real boot starts AFTER trust confirmation.
                        // Claude still needs ~15-20s to fully initialize after this point.
                        ptyRef.resetStartupClock()
                    }

                    // Detect /loop confirmation from Claude CLI.
                    // Real output: "CronCreate(*/5 * * * *: ...)" then "Scheduled <id> (Every N ...)"
                    if compact.contains("croncreate") || (compact.contains("scheduled") && compact.contains("every")) {
                        sessionLogger.info("Loop confirmation detected: \(String(cleaned.prefix(300)))")
                        continuation?.yield(.loopConfirmed(cleaned))
                    }

                    // Detect scheduled task execution.
                    // Claude CLI renders results with the ⏺ bullet (U+23FA).
                    // The full result arrives in multiple PTY chunks: first the tool call
                    // (⏺ Bash(date)), then the tool output, then Claude's text response.
                    // We buffer all chunks for 2.5s after the first ⏺ is seen, then fire
                    // taskCompleted with the accumulated text so the summary has useful content.
                    let hasResultBullet = stripped.contains("\u{23FA}") // ⏺
                    let isRegistration = compact.contains("scheduled") || compact.contains("croncreate")

                    if taskBox.hasPendingResult {
                        // Accumulate additional output and restart the debounce timer
                        taskBox.resultBuffer += "\n" + cleaned
                        taskBox.resultTimer?.cancel()
                        taskBox.resultTimer = self.makeResultDebounceTimer(
                            box: taskBox, continuation: continuation, logger: sessionLogger)
                    } else if hasResultBullet && !isRegistration {
                        // First ⏺ of a task result — start buffering
                        sessionLogger.info("Claude CLI scheduled task result detected (⏺) — buffering")
                        taskBox.hasPendingResult = true
                        taskBox.resultBuffer = cleaned
                        taskBox.resultTimer = self.makeResultDebounceTimer(
                            box: taskBox, continuation: continuation, logger: sessionLogger)
                    }
                }
            },
            onEOF: {
                sessionLogger.info("PTY process closed stdout (EOF)")
            }
        )

        self.ptyProcess = pty
        state = .running
        restartCount = 0
        eventContinuation?.yield(.stateChanged(.running))
        logger.info("BackgroundCLISession started with PTY, PID=\(pty.childPID), sessionId=\(sessionId)")

        // Start process monitor
        startProcessMonitor(pty)

        // NOTE: Scheduled task restoration is handled by CronJobsStore after receiving
        // .stateChanged(.running). It calls waitUntilReady() then scheduleAllClaudeJobs().
    }

    /// Monitor the process and restart if it dies unexpectedly.
    private func startProcessMonitor(_ pty: PTYProcess) {
        monitorTask?.cancel()
        monitorTask = Task.detached { [weak self] in
            let status = pty.waitForExit()
            guard let self, !Task.isCancelled else { return }
            await self.handleProcessExit(status: status)
        }
    }

    /// Handle unexpected process exit.
    private func handleProcessExit(status: Int32) async {
        eventContinuation?.yield(.processExited(status: status))
        logger.warning("Claude background process exited with status \(status)")

        self.ptyProcess = nil

        // Don't restart if we explicitly stopped
        guard state != .stopped else { return }

        // Restart with backoff
        guard restartCount < Self.maxRestarts else {
            state = .idle
            eventContinuation?.yield(.error("Max restarts (\(Self.maxRestarts)) reached, giving up"))
            eventContinuation?.yield(.stateChanged(.idle))
            logger.error("BackgroundCLISession exceeded max restarts")
            return
        }

        restartCount += 1
        state = .restarting
        eventContinuation?.yield(.stateChanged(.restarting))
        logger.info("Restarting BackgroundCLISession (attempt \(restartCount)/\(Self.maxRestarts))")

        // Generate new session ID for fresh session
        sessionId = UUID().uuidString

        let delay = Self.restartDelay * Double(restartCount)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        guard state == .restarting else { return }
        await launchProcess()
    }

    /// Terminate the current process.
    private func terminateProcess() {
        ptyProcess?.terminate()
        ptyProcess = nil
    }

    /// Create a 2.5s debounce timer that fires `taskCompleted` with the buffered result.
    /// Called each time a PTY chunk arrives while a result is being buffered.
    /// The caller must cancel any previous timer before calling this.
    private nonisolated func makeResultDebounceTimer(
        box: TaskDetectionBox,
        continuation: AsyncStream<SessionEvent>.Continuation?,
        logger: Logger
    ) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 2.5)
        timer.setEventHandler {
            let fullResult = box.resultBuffer
            box.hasPendingResult = false
            box.resultBuffer = ""
            box.resultTimer = nil
            let now = Date()
            if box.lastTaskStartedAt == nil || now.timeIntervalSince(box.lastTaskStartedAt!) > 60 {
                box.lastTaskStartedAt = now
                logger.info("Claude CLI task result ready (2.5s debounce)")
                continuation?.yield(.taskCompleted(fullResult))
            }
        }
        timer.resume()
        return timer
    }

    /// Find the Claude CLI binary path from AppState.
    private func findClaudeBinary() async -> String? {
        await MainActor.run {
            AppState.shared.availableCLIs.first { $0.id == "claude" }?.binaryPath
        }
    }

    // MARK: - Schedule Helpers

    /// Convert a CronSchedule to a human-readable interval for `/loop`.
    private func formatScheduleInterval(_ schedule: ScheduleDefinition?) -> String? {
        guard let schedule else { return nil }
        switch schedule.kind {
        case "every":
            guard let ms = schedule.everyMs, ms > 0 else { return nil }
            let seconds = ms / 1000
            if seconds < 60 { return "\(seconds)s" }
            let minutes = seconds / 60
            if minutes < 60 { return "\(minutes)m" }
            let hours = minutes / 60
            return "\(hours)h"
        case "cron":
            // For cron expressions, convert to approximate interval
            // /loop doesn't support cron directly, so we approximate
            return schedule.expr.flatMap { cronToApproxInterval($0) }
        default:
            return nil
        }
    }

    /// Approximate a cron expression to a simple interval for /loop.
    private func cronToApproxInterval(_ expr: String) -> String? {
        let parts = expr.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard parts.count >= 5 else { return nil }

        let minute = parts[0]
        let hour = parts[1]

        // */N minutes → Nm
        if minute.hasPrefix("*/"), let n = Int(minute.dropFirst(2)) {
            return "\(n)m"
        }
        // Every hour at minute X → 1h
        if minute != "*" && hour == "*" {
            return "1h"
        }
        // Specific hour → daily ≈ 24h
        if minute != "*" && hour != "*" {
            return "24h"
        }

        return "1h" // default fallback
    }

    /// Extract message text from a payload definition.
    private func extractMessage(from payload: PayloadDefinition?) -> String {
        guard let payload else { return "" }
        if let message = payload.message, !message.isEmpty { return message }
        if let text = payload.text, !text.isEmpty { return text }
        return ""
    }
}

// MARK: - Lightweight Codable models for reading schedules.json

/// Minimal model for reading scheduled job definitions from disk.
/// Only the fields needed for task restoration.
private struct ScheduledJobDefinition: Codable {
    let id: String
    let agentId: String?
    let name: String?
    let enabled: Bool
    let schedule: ScheduleDefinition?
    let payload: PayloadDefinition?

    enum CodingKeys: String, CodingKey {
        case id, agentId, name, enabled, schedule, payload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        agentId = try c.decodeIfPresent(String.self, forKey: .agentId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        schedule = try c.decodeIfPresent(ScheduleDefinition.self, forKey: .schedule)
        payload = try c.decodeIfPresent(PayloadDefinition.self, forKey: .payload)
    }
}

private struct ScheduleDefinition: Codable {
    let kind: String?
    let everyMs: Int?
    let expr: String?

    enum CodingKeys: String, CodingKey {
        case kind, everyMs, expr
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        everyMs = try c.decodeIfPresent(Int.self, forKey: .everyMs)
        expr = try c.decodeIfPresent(String.self, forKey: .expr)
    }
}

private struct PayloadDefinition: Codable {
    let message: String?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case message, text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        text = try c.decodeIfPresent(String.self, forKey: .text)
    }
}

// MARK: - Task Detection Box

/// Mutable reference box for tracking task detection and result buffering across PTY onData callbacks.
/// Uses a class (reference semantics) so it can be mutated from within a Sendable closure
/// that captures it as a `let` constant, without requiring actor isolation.
///
/// Thread safety: all fields are accessed from the PTY dispatch queue (onData callbacks)
/// and the debounce timer. The 60s deduplication on `lastTaskStartedAt` guards against
/// double-fires if a race occurs between the timer and a concurrent onData call.
private final class TaskDetectionBox: @unchecked Sendable {
    /// Timestamp of the last taskCompleted event — prevents double-firing within 60s.
    var lastTaskStartedAt: Date?
    /// Accumulated PTY output while buffering a task result.
    var resultBuffer: String = ""
    /// Active debounce timer waiting to fire taskCompleted.
    var resultTimer: DispatchSourceTimer?
    /// Whether we're currently accumulating a task result buffer.
    var hasPendingResult: Bool = false
}
