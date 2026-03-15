import Foundation
import Logging
import McClawKit

/// Maintains a persistent Claude CLI process for background scheduling.
///
/// Unlike `CLIBridge` (which uses `--print` and exits after one response),
/// `BackgroundCLISession` keeps the process alive by using `--input-format stream-json`
/// and writing messages to stdin — the same approach VS Code uses.
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

    private var process: Process?
    private var stdinHandle: FileHandle?
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
    var processId: Int32? { process?.processIdentifier }

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

    /// Send a user message to the running Claude process.
    /// Returns false if the process is not running.
    @discardableResult
    func sendMessage(_ text: String) -> Bool {
        guard state == .running, let handle = stdinHandle else {
            logger.warning("Cannot send message — session not running")
            return false
        }

        let encoded = CLIParser.encodeStdinMessage(text)
        guard !encoded.isEmpty, let data = encoded.data(using: .utf8) else {
            logger.error("Failed to encode stdin message")
            return false
        }
        logger.info("Encoded JSON: \(encoded.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))")

        do {
            try handle.write(contentsOf: data)
            logger.info("Sent to stdin: \(text.prefix(200))")
            return true
        } catch {
            logger.error("Failed to write to stdin: \(error.localizedDescription)")
            return false
        }
    }

    /// Send an interrupt control request to the running process.
    func interrupt() {
        guard state == .running, let handle = stdinHandle else { return }
        let encoded = CLIParser.encodeControlRequest(subtype: "interrupt")
        guard let data = encoded.data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
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

    /// Launch the Claude CLI process in persistent mode.
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

        let proc = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = args
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        proc.standardInput = stdinPipe

        // Sanitize environment
        let binaryDir = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
        var env = HostEnvSanitizer.sanitize(isShellWrapper: false)
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        if !currentPath.contains(binaryDir) {
            env["PATH"] = "\(binaryDir):\(currentPath)"
        }
        proc.environment = env

        // Set up stdout reading
        let lineBuffer = LineBuffer()
        let taskOutputState = TaskOutputState()
        let continuation = eventContinuation
        let sessionLogger = logger

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF — process ended
                let remaining = lineBuffer.flush()
                if !remaining.isEmpty {
                    let event = CLIParser.parseLine(remaining, provider: "claude")
                    if case .text(let text) = event {
                        continuation?.yield(.text(text))
                    }
                }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                return
            }

            guard let text = String(data: data, encoding: .utf8) else { return }
            let lines = lineBuffer.feed(text)
            for line in lines {
                // Log all stdout lines for debugging
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
        }

        // Collect stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sessionLogger.warning("Claude stderr: \(text.prefix(500))")
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.stdinHandle = stdinPipe.fileHandleForWriting
            state = .running
            restartCount = 0
            eventContinuation?.yield(.stateChanged(.running))
            logger.info("BackgroundCLISession started, PID=\(proc.processIdentifier), sessionId=\(sessionId)")

            // Start process monitor
            startProcessMonitor(proc)

            // Restore scheduled tasks
            await restoreScheduledTasks()

        } catch {
            state = .idle
            eventContinuation?.yield(.error("Failed to launch Claude: \(error.localizedDescription)"))
            eventContinuation?.yield(.stateChanged(.idle))
            logger.error("Failed to launch Claude background session: \(error)")
        }
    }

    /// Monitor the process and restart if it dies unexpectedly.
    private func startProcessMonitor(_ proc: Process) {
        monitorTask?.cancel()
        monitorTask = Task.detached { [weak self] in
            proc.waitUntilExit()
            guard let self, !Task.isCancelled else { return }

            let status = proc.terminationStatus
            await self.handleProcessExit(status: status)
        }
    }

    /// Handle unexpected process exit.
    private func handleProcessExit(status: Int32) async {
        eventContinuation?.yield(.processExited(status: status))
        logger.warning("Claude background process exited with status \(status)")

        self.process = nil
        self.stdinHandle = nil

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
        stdinHandle?.closeFile()
        stdinHandle = nil
        process?.terminate()
        process = nil
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

// MARK: - Task output state for readabilityHandler

/// Tracks current task output accumulation in the readabilityHandler closure.
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
