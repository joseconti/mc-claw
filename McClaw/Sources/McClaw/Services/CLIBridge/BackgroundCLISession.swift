import Foundation
import Logging
import McClawKit

/// Maintains a persistent Claude CLI process for background scheduling.
///
/// Unlike `CLIBridge` (which uses `--print` and exits after one response),
/// `BackgroundCLISession` keeps the process alive using a PTY (pseudo-terminal)
/// so the CLI activates its interactive mode. This enables slash commands like
/// `/loop` which are only processed in interactive mode with a real TTY.
///
/// Scheduled tasks are created by sending `/loop` commands to the live process.
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

    /// Emitted events from the background session.
    enum SessionEvent: Sendable {
        case text(String)
        case taskFired(taskId: String, output: String)
        case error(String)
        case processExited(status: Int32)
        case stateChanged(SessionState)
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
    /// Watchdog: kill if no output for 10 minutes (generous for background).
    private static let watchdogTimeout: TimeInterval = 600

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

    /// Send a user message to the running Claude process via PTY.
    /// The text is sent as plain text with a newline, as if typed on a keyboard.
    /// Returns false if the process is not running.
    @discardableResult
    func sendMessage(_ text: String) -> Bool {
        guard state == .running, let pty = ptyProcess, pty.isRunning else {
            logger.warning("Cannot send message — session not running")
            return false
        }

        let success = pty.write(text + "\n")
        if success {
            logger.info("Sent to PTY: \(text.prefix(200))")
        } else {
            logger.error("Failed to write to PTY")
        }
        return success
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
    func scheduleTask(interval: String, message: String) -> Bool {
        // /loop is a Claude CLI slash command: /loop <interval> <prompt>
        let loopCommand = "/loop \(interval) \(message)"
        return sendMessage(loopCommand)
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

            // Small delay to let the session initialize
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            for job in claudeJobs {
                guard let interval = formatScheduleInterval(job.schedule) else { continue }
                let message = extractMessage(from: job.payload)
                guard !message.isEmpty else { continue }

                let sent = scheduleTask(interval: interval, message: message)
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

        // Disable echo so input doesn't pollute stdout
        pty.configureTerminal()

        // Set up output reading with ANSI stripping and JSON parsing
        let lineBuffer = LineBuffer()
        let taskOutputState = TaskOutputState()
        let continuation = eventContinuation
        let sessionLogger = logger

        pty.startReading(
            onData: { data in
                guard let rawText = String(data: data, encoding: .utf8) else { return }

                // Strip ANSI escape sequences from PTY output
                let text = CLIParser.stripANSI(rawText)

                let lines = lineBuffer.feed(text)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        sessionLogger.info("stdout: \(String(trimmed.prefix(500)))")
                    }

                    let event = CLIParser.parseLine(line, provider: "claude")
                    switch event {
                    case .text(let text):
                        taskOutputState.buffer += text
                        continuation?.yield(.text(text))
                    case .done:
                        // If we were accumulating a task output, emit it
                        if let taskId = taskOutputState.currentTaskId, !taskOutputState.buffer.isEmpty {
                            continuation?.yield(.taskFired(taskId: taskId, output: taskOutputState.buffer))
                            taskOutputState.buffer = ""
                            taskOutputState.currentTaskId = nil
                        } else if !taskOutputState.buffer.isEmpty {
                            // No explicit taskId — use "auto" for unsolicited /loop output
                            continuation?.yield(.taskFired(taskId: "auto-\(UUID().uuidString.prefix(8))", output: taskOutputState.buffer))
                            taskOutputState.buffer = ""
                        }
                    case .passthrough:
                        // Check if this is a cron/loop related event
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let type = json["type"] as? String ?? "unknown"
                            sessionLogger.info("JSON event type=\(type)")

                            // Detect cron task start (from /loop scheduler)
                            if type == "cron_task_start" || type == "tool_use",
                               let taskId = json["task_id"] as? String ?? json["id"] as? String {
                                taskOutputState.currentTaskId = taskId
                                taskOutputState.buffer = ""
                                sessionLogger.info("Task started: \(taskId)")
                            }
                        }
                    default:
                        break
                    }
                }
            },
            onEOF: {
                // Flush remaining buffer
                let remaining = lineBuffer.flush()
                if !remaining.isEmpty {
                    let event = CLIParser.parseLine(remaining, provider: "claude")
                    if case .text(let text) = event {
                        continuation?.yield(.text(text))
                    }
                }
            }
        )

        self.ptyProcess = pty
        state = .running
        restartCount = 0
        eventContinuation?.yield(.stateChanged(.running))
        logger.info("BackgroundCLISession started with PTY, PID=\(pty.childPID), sessionId=\(sessionId)")

        // Start process monitor
        startProcessMonitor(pty)

        // Restore scheduled tasks
        await restoreScheduledTasks()
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

// MARK: - Task output state for PTY readabilityHandler

/// Tracks current task output accumulation in the PTY read callback.
/// Uses `nonisolated(unsafe)` to allow mutation in the Sendable closure context,
/// matching the pattern used by CLIBridge's LineBuffer and WatchdogTimer.
private final class TaskOutputState: Sendable {
    nonisolated(unsafe) var buffer = ""
    nonisolated(unsafe) var currentTaskId: String?
}

// MARK: - Line buffer (reused from CLIBridge)

/// Accumulates partial line data and splits on newlines.
private final class LineBuffer: Sendable {
    nonisolated(unsafe) var buffer = ""

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

    func flush() -> String {
        let result = buffer
        buffer = ""
        return result
    }
}
