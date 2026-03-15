import Foundation
import Logging
import McClawKit
import McClawProtocol

/// Manages cron jobs with hybrid backend:
/// - Claude CLI: delegates to BackgroundCLISession (persistent process with /loop)
/// - Other providers: uses LocalScheduler for background execution via CLIBridge
@MainActor
@Observable
final class CronJobsStore {
    static let shared = CronJobsStore()

    var jobs: [CronJob] = []
    var selectedJobId: String?
    var runEntries: [CronRunLogEntry] = []

    var schedulerEnabled: Bool?
    var schedulerStorePath: String?
    var schedulerNextWakeAtMs: Int?

    /// Whether the Claude background session is active.
    var claudeSessionActive = false
    /// PID of the Claude background process (for diagnostics).
    var claudeSessionPID: Int32?

    var isLoadingJobs = false
    var isLoadingRuns = false
    var lastError: String?
    var statusMessage: String?
    /// Last confirmation text received from Claude CLI when a /loop was accepted.
    var lastLoopConfirmation: String?

    private let logger = Logger(label: "ai.mcclaw.cron")
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var runsTask: Task<Void, Never>?
    private var sessionEventTask: Task<Void, Never>?
    private var renewalTask: Task<Void, Never>?

    /// FIFO queue of McClaw job IDs whose `/loop` commands have been sent but whose
    /// Claude CLI confirmation (loopConfirmed) hasn't arrived yet.
    /// Used to correlate confirmations with job IDs so we can store the Claude task ID.
    private var pendingLoopJobIds: [String] = []

    private let pollInterval: TimeInterval = 30
    /// Renew /loop tasks every 2 days (they expire after 3 days).
    private static let loopRenewalInterval: TimeInterval = 2 * 24 * 3600

    private static let localJobsURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw", isDirectory: true)
        return dir.appendingPathComponent("schedules.json")
    }()

    private static let runLogsURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw", isDirectory: true)
        return dir.appendingPathComponent("run-logs.json")
    }()

    /// Maximum number of run log entries to keep per job.
    private static let maxRunLogsPerJob = 50

    private init() {
        loadLocalJobs()
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }

        // Subscribe to cron events from Gateway
        Task {
            await GatewayConnectionService.shared.setOnCronEvent { [weak self] cronEvent in
                self?.handleCronEvent(cronEvent)
            }
        }

        // Start LocalScheduler for non-Claude providers
        LocalScheduler.shared.start()

        // Start BackgroundCLISession for Claude scheduled tasks
        startClaudeBackgroundSession()

        // Start polling (for local job state refresh)
        pollTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.refreshJobs()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                await self.refreshJobs()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        runsTask?.cancel()
        runsTask = nil
        sessionEventTask?.cancel()
        sessionEventTask = nil
        renewalTask?.cancel()
        renewalTask = nil
        LocalScheduler.shared.stop()
        Task {
            await BackgroundCLISession.shared.stop()
        }
    }

    /// Start the Claude background session and monitor its events.
    private func startClaudeBackgroundSession() {
        // Only start if there are enabled Claude jobs
        let hasClaudeJobs = jobs.contains { job in
            let agent = job.agentId ?? ""
            return job.enabled && (agent.isEmpty || agent == "claude")
        }
        guard hasClaudeJobs else {
            logger.info("No enabled Claude jobs, skipping background session")
            return
        }

        sessionEventTask = Task { [weak self] in
            let stream = await BackgroundCLISession.shared.start()
            for await event in stream {
                guard let self, !Task.isCancelled else { break }
                await self.handleSessionEvent(event)
            }
        }

        // Start renewal timer to prevent /loop task expiry (3-day limit)
        startLoopRenewalTimer()
    }

    /// Periodically re-send /loop commands to prevent 3-day expiry.
    private func startLoopRenewalTimer() {
        renewalTask?.cancel()
        renewalTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.loopRenewalInterval * 1_000_000_000))
                guard let self, !Task.isCancelled else { break }
                await self.renewAllClaudeTasks()
            }
        }
    }

    /// Re-send /loop for all active Claude jobs to prevent expiry.
    private func renewAllClaudeTasks() async {
        let claudeJobs = jobs.filter { job in
            let agent = job.agentId ?? ""
            return job.enabled && (agent.isEmpty || agent == "claude")
        }
        guard !claudeJobs.isEmpty else { return }

        logger.info("Renewing \(claudeJobs.count) Claude /loop tasks (3-day expiry prevention)")

        for job in claudeJobs {
            guard let interval = scheduleToLoopInterval(job.schedule) else { continue }
            let message: String
            switch job.payload {
            case .agentTurn(let msg, _, _, _, _, _, _, _): message = msg
            case .systemEvent(let text): message = text
            }
            guard !message.isEmpty else { continue }

            pendingLoopJobIds.append(job.id)
            let sent = await BackgroundCLISession.shared.scheduleTask(interval: interval, message: message)
            if sent {
                logger.info("Renewed task '\(job.displayName)'")
            } else {
                pendingLoopJobIds.removeLast()
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    /// Schedule /loop for all enabled Claude jobs. Called after the PTY session becomes ready.
    /// This is the restore path — CronJobsStore owns the ordering so it can track IDs via pendingLoopJobIds.
    private func scheduleAllClaudeJobs() async {
        let claudeJobs = jobs.filter { job in
            let agent = job.agentId ?? ""
            return job.enabled && (agent.isEmpty || agent == "claude")
        }
        guard !claudeJobs.isEmpty else {
            logger.info("No enabled Claude jobs to restore")
            return
        }
        logger.info("Restoring \(claudeJobs.count) Claude /loop tasks via CronJobsStore")
        for job in claudeJobs {
            guard let interval = scheduleToLoopInterval(job.schedule) else { continue }
            let message: String
            switch job.payload {
            case .agentTurn(let msg, _, _, _, _, _, _, _): message = msg
            case .systemEvent(let text): message = text
            }
            guard !message.isEmpty else { continue }

            pendingLoopJobIds.append(job.id)
            let sent = await BackgroundCLISession.shared.scheduleTask(interval: interval, message: message)
            if sent {
                logger.info("Restored task '\(job.displayName)' (\(interval))")
            } else {
                pendingLoopJobIds.removeLast()
                logger.warning("Failed to restore task '\(job.displayName)'")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    /// Handle events from the BackgroundCLISession.
    /// Note: the PTY output is not parsed, so there's no `.taskFired` event.
    /// Task results from `/loop` are managed by Claude CLI internally.
    private func handleSessionEvent(_ event: BackgroundCLISession.SessionEvent) {
        switch event {
        case .stateChanged(let newState):
            claudeSessionActive = (newState == .running)
            if newState == .running {
                Task {
                    claudeSessionPID = await BackgroundCLISession.shared.processId
                }
                // PTY is launching — wait until it's ready, then restore all /loop tasks.
                Task { [weak self] in
                    guard let self else { return }
                    await BackgroundCLISession.shared.waitUntilReady(timeout: 60)
                    await self.scheduleAllClaudeJobs()
                }
            } else {
                claudeSessionPID = nil
            }
            logger.info("Claude background session state: \(newState)")

        case .error(let msg):
            logger.error("Claude background session error: \(msg)")
            lastError = msg

        case .processExited(let status):
            logger.warning("Claude background process exited: \(status)")
            claudeSessionActive = false
            claudeSessionPID = nil

        case .loopConfirmed(let confirmation):
            logger.info("Claude /loop confirmed: \(confirmation.prefix(200))")
            lastLoopConfirmation = confirmation
            // Pop the next pending job ID from the FIFO queue to correlate this confirmation.
            let pendingJobId = pendingLoopJobIds.isEmpty ? nil : pendingLoopJobIds.removeFirst()
            let claudeTaskId = parseClaudeTaskId(from: confirmation)
            if let claudeTaskId, let pendingJobId {
                logger.info("Stored Claude task ID: \(claudeTaskId) for job \(pendingJobId)")
            }
            if let intervalMs = parseLoopConfirmationInterval(confirmation) {
                updateClaudeJobsNextRun(intervalMs: intervalMs, specificJobId: pendingJobId, claudeTaskId: claudeTaskId)
            }

        case .taskCompleted(let result):
            // A /loop iteration completed. Update job state and send notifications.
            logger.info("Claude scheduled task completed — updating job state")
            updateClaudeJobsAfterRun(result: result)
        }
    }

    /// Extract the Claude CLI internal task ID from a /loop confirmation string.
    /// Claude CLI outputs: "Scheduled 8772934d (Every 5 minutes)" → returns "8772934d".
    /// Works on both normal text and compact text (spaces removed after ANSI strip).
    private func parseClaudeTaskId(from text: String) -> String? {
        let compact = text.lowercased().replacingOccurrences(of: " ", with: "")
        // Pattern: "scheduled" followed immediately by a hex ID (6-12 chars), then "("
        guard let range = compact.range(of: "scheduled([a-f0-9]{6,12})\\(", options: .regularExpression),
              let idRange = compact[range].range(of: "[a-f0-9]{6,12}", options: .regularExpression) else {
            return nil
        }
        return String(compact[range][idRange])
    }

    /// Parse the interval in milliseconds from a /loop confirmation string.
    /// Handles compact (no-space) or normal text, e.g. "Every5minutes" or "Every 5 minutes".
    private func parseLoopConfirmationInterval(_ text: String) -> Int? {
        let compact = text.lowercased().replacingOccurrences(of: " ", with: "")
        // Match patterns like "every5minutes", "every1hour", "every30seconds"
        let patterns: [(String, Int)] = [
            ("every(\\d+)minutes", 60_000),
            ("every(\\d+)hours", 3_600_000),
            ("every(\\d+)seconds", 1_000),
            ("every(\\d+)days", 86_400_000),
        ]
        for (pattern, multiplier) in patterns {
            if let range = compact.range(of: pattern, options: .regularExpression),
               let numRange = compact[range].range(of: "\\d+", options: .regularExpression),
               let n = Int(compact[range][numRange]) {
                return n * multiplier
            }
        }
        return nil
    }

    /// Set nextRunAtMs (and optionally claudeTaskId) on Claude jobs after /loop confirmation.
    /// - Parameters:
    ///   - intervalMs: Schedule interval in milliseconds, used to compute nextRunAtMs.
    ///   - specificJobId: If set, update only this McClaw job ID; otherwise update all Claude jobs.
    ///   - claudeTaskId: If set, store the Claude CLI internal task ID for later cancellation.
    private func updateClaudeJobsNextRun(
        intervalMs: Int,
        specificJobId: String? = nil,
        claudeTaskId: String? = nil
    ) {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        var changed = false
        for i in jobs.indices {
            guard localJobIds.contains(jobs[i].id) else { continue }
            // If a specific job was targeted, skip all others
            if let specificJobId, jobs[i].id != specificJobId { continue }
            let agent = jobs[i].agentId ?? ""
            guard jobs[i].enabled && (agent.isEmpty || agent == "claude") else { continue }
            let job = jobs[i]
            let newState = CronJobState(
                nextRunAtMs: nowMs + intervalMs,
                runningAtMs: nil,
                lastRunAtMs: job.state.lastRunAtMs,
                lastStatus: job.state.lastStatus,
                lastError: nil,
                lastDurationMs: job.state.lastDurationMs,
                claudeTaskId: claudeTaskId ?? job.state.claudeTaskId
            )
            jobs[i] = CronJob(
                id: job.id, agentId: job.agentId, model: job.model, name: job.name,
                description: job.description, enabled: job.enabled,
                deleteAfterRun: job.deleteAfterRun, createdAtMs: job.createdAtMs,
                updatedAtMs: job.updatedAtMs, schedule: job.schedule,
                sessionTarget: job.sessionTarget, wakeMode: job.wakeMode,
                payload: job.payload, delivery: job.delivery, state: newState
            )
            changed = true
        }
        if changed { persistLocalJobs() }
    }

    /// Update lastRunAtMs = now and recalculate nextRunAtMs for all enabled local Claude jobs.
    /// Also posts a notification for jobs with delivery channel = "notifications".
    private func updateClaudeJobsAfterRun(result: String) {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        var changed = false
        for i in jobs.indices {
            guard localJobIds.contains(jobs[i].id) else { continue }
            let agent = jobs[i].agentId ?? ""
            guard jobs[i].enabled && (agent.isEmpty || agent == "claude") else { continue }
            let job = jobs[i]
            let intervalMs = scheduleIntervalMs(job.schedule)
            let newState = CronJobState(
                nextRunAtMs: intervalMs > 0 ? nowMs + intervalMs : job.state.nextRunAtMs,
                runningAtMs: nil,
                lastRunAtMs: nowMs,
                lastStatus: "ok",
                lastError: nil,
                lastDurationMs: nil
            )
            jobs[i] = CronJob(
                id: job.id, agentId: job.agentId, model: job.model, name: job.name,
                description: job.description, enabled: job.enabled,
                deleteAfterRun: job.deleteAfterRun, createdAtMs: job.createdAtMs,
                updatedAtMs: job.updatedAtMs, schedule: job.schedule,
                sessionTarget: job.sessionTarget, wakeMode: job.wakeMode,
                payload: job.payload, delivery: job.delivery, state: newState
            )
            appendRunLog(jobId: job.id, status: "ok", startMs: nowMs)

            // Send notification if delivery channel is "notifications"
            if job.delivery?.channel == "notifications" {
                let summary = extractResultSummary(from: result)
                ScheduleNotificationStore.shared.add(
                    scheduleName: job.displayName,
                    scheduleId: job.id,
                    provider: job.agentId ?? "claude",
                    summary: summary.isEmpty ? "Task completed" : summary,
                    status: .success
                )
            }

            changed = true
        }
        if changed { persistLocalJobs() }
    }

    /// Extract the useful response text from buffered PTY output.
    ///
    /// PTY output for a task like "tell me the time" looks like:
    /// ```
    /// ⏺ Bash(date)               ← tool invocation — skip
    ///   Sun Mar 15 14:05:32 ...   ← tool result (indented, no bullet)
    /// ⏺ Sun Mar 15 14:05:32 ...  ← tool result (with bullet, no CamelCase pattern)
    /// The current time is...      ← Claude's text response — prefer this
    /// ✻ Calculating…              ← spinner — stop here
    /// ```
    ///
    /// Priority: Claude's text response > tool result lines > raw fallback.
    private func extractResultSummary(from text: String) -> String {
        let bullet = "\u{23FA}" // ⏺
        // Prefixes for structural/spinner lines — skip them but keep processing further lines
        let skipPrefixes = ["✻", "✽", "✶", "✳", "✢", "·", "⎿", "❯", "────", "Tip:",
                            "Wait", "Running", "Ionizing", "Spelunking", "Calculating",
                            "Thinking", "Working", "? for"]
        // Tool invocation pattern: ⏺ CamelCaseName( — e.g. "Bash(", "Write(", "Read("
        // Also catches PTY-garbled variants like "B (date)" where ANSI cursor splitting
        // leaves a single uppercase letter followed by optional space before "(".
        let toolCallRegex = try? NSRegularExpression(pattern: "^[A-Z][a-zA-Z]* ?\\(")

        // claudeResponse: ⏺ lines that are NOT tool calls (Claude's formatted reply)
        var claudeResponse: [String] = []
        // toolOutput: plain-text lines without bullet (raw command stdout)
        var toolOutput: [String] = []

        // Re-apply ANSI strip on the full buffer (some sequences arrive split across chunks)
        // and collapse multiple spaces left by cursor-forward replacements.
        let cleanText = CLIParser.stripANSI(text)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)

        for raw in cleanText.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // Skip structural/spinner lines but keep processing subsequent lines
            if skipPrefixes.contains(where: { line.hasPrefix($0) }) { continue }

            if line.hasPrefix(bullet) {
                let content = String(line.dropFirst(bullet.unicodeScalars.count))
                    .trimmingCharacters(in: .whitespaces)
                let isToolCall = toolCallRegex?.firstMatch(
                    in: content, range: NSRange(content.startIndex..., in: content)
                ) != nil
                if !isToolCall && !content.isEmpty {
                    claudeResponse.append(content) // Claude's bulleted text reply
                }
                // Tool invocations (Bash(date), Write(...)) are discarded
            } else {
                toolOutput.append(line) // Raw tool stdout
            }
        }

        // Priority: Claude's formatted bulleted response > raw tool stdout > raw fallback
        let best = claudeResponse.isEmpty ? toolOutput : claudeResponse
        let joined = best.joined(separator: " ")
        return joined.isEmpty ? String(cleanText.prefix(200)) : String(joined.prefix(300))
    }

    /// Return the schedule interval in milliseconds for a CronSchedule.
    private func scheduleIntervalMs(_ schedule: CronSchedule) -> Int {
        switch schedule {
        case .every(let ms, _): return ms
        case .cron(let expr, _):
            let parts = expr.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard parts.count >= 5 else { return 0 }
            if parts[0].hasPrefix("*/"), let n = Int(parts[0].dropFirst(2)) { return n * 60_000 }
            if parts[0] != "*" && parts[1] == "*" { return 3_600_000 }
            if parts[0] != "*" && parts[1] != "*" { return 86_400_000 }
            return 3_600_000
        case .at: return 0
        }
    }

    // MARK: - Refresh

    func refreshJobs() async {
        guard !isLoadingJobs else { return }
        isLoadingJobs = true
        lastError = nil
        statusMessage = nil
        defer { isLoadingJobs = false }

        loadLocalJobs()
        schedulerEnabled = true

        claudeSessionActive = await BackgroundCLISession.shared.isRunning

        if jobs.isEmpty {
            statusMessage = "No scheduled tasks yet."
        }
    }

    func refreshRuns(jobId: String, limit: Int = 200) async {
        guard !isLoadingRuns else { return }
        isLoadingRuns = true
        defer { isLoadingRuns = false }

        if isLocalJob(jobId) {
            // Local jobs: load from local run log file
            runEntries = loadLocalRunLogs(jobId: jobId, limit: limit)
            return
        }

        // Gateway jobs: fetch from WebSocket
        do {
            runEntries = try await GatewayConnectionService.shared.cronRuns(jobId: jobId, limit: limit)
        } catch {
            logger.error("cron.runs failed: \(error.localizedDescription)")
            runEntries = []
        }
    }

    // MARK: - CRUD

    func runJob(id: String, force: Bool = true) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }

        // Local jobs: execute via LocalScheduler (CLIBridge one-shot).
        if isLocalJob(id) {
            logger.info("Manual run of job '\(job.displayName)'")
            Task {
                await LocalScheduler.shared.manualRun(job: job)
            }
            return
        }

        // Gateway fallback
        do {
            try await GatewayConnectionService.shared.cronRun(jobId: id, force: force)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeJob(id: String) async {
        // Cancel the corresponding Claude CLI /loop task if we have its ID
        if let job = jobs.first(where: { $0.id == id }),
           let claudeTaskId = job.state.claudeTaskId {
            Task {
                await BackgroundCLISession.shared.cancelTask(claudeTaskId: claudeTaskId)
            }
        }
        // Remove from local storage
        jobs.removeAll { $0.id == id }
        localJobIds.remove(id)
        persistLocalJobs()
        if selectedJobId == id {
            selectedJobId = nil
            runEntries = []
        }
    }

    func setJobEnabled(id: String, enabled: Bool) async {
        // Cancel the Claude /loop task when disabling
        if !enabled,
           let job = jobs.first(where: { $0.id == id }),
           let claudeTaskId = job.state.claudeTaskId {
            Task {
                await BackgroundCLISession.shared.cancelTask(claudeTaskId: claudeTaskId)
            }
        }
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            let job = jobs[index]
            let updated = CronJob(
                id: job.id, agentId: job.agentId, model: job.model, name: job.name,
                description: job.description, enabled: enabled,
                deleteAfterRun: job.deleteAfterRun,
                createdAtMs: job.createdAtMs,
                updatedAtMs: Int(Date().timeIntervalSince1970 * 1000),
                schedule: job.schedule, sessionTarget: job.sessionTarget,
                wakeMode: job.wakeMode, payload: job.payload,
                delivery: job.delivery, state: job.state
            )
            jobs[index] = updated
            persistLocalJobs()
        }
    }

    func upsertJob(id: String?, payload: [String: AnyCodableValue]) async throws {
        // Save locally so the job is visible in the list
        let job = buildCronJob(from: payload, existingId: id)
        if let existingIndex = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[existingIndex] = job
        } else {
            jobs.append(job)
        }
        persistLocalJobs()

        // For Claude jobs, register in BackgroundCLISession via /loop
        let agentId = payload["agentId"]
        let isForClaude = agentId == nil || agentId == .string("claude") || agentId == .string("")
        if isForClaude && job.enabled {
            if await !BackgroundCLISession.shared.isRunning {
                startClaudeBackgroundSession()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            if let interval = scheduleToLoopInterval(job.schedule) {
                let message: String
                switch job.payload {
                case .agentTurn(let msg, _, _, _, _, _, _, _): message = msg
                case .systemEvent(let text): message = text
                }
                if !message.isEmpty {
                    pendingLoopJobIds.append(job.id)
                    let sent = await BackgroundCLISession.shared.scheduleTask(
                        interval: interval, message: message
                    )
                    if !sent {
                        pendingLoopJobIds.removeLast()
                        logger.warning("Failed to register Claude task '\(job.displayName)' in background session")
                    }
                }
            }
        }
    }

    /// Convert CronSchedule to a simple interval string for /loop.
    private func scheduleToLoopInterval(_ schedule: CronSchedule) -> String? {
        switch schedule {
        case .every(let everyMs, _):
            let seconds = everyMs / 1000
            if seconds < 60 { return "\(seconds)s" }
            let minutes = seconds / 60
            if minutes < 60 { return "\(minutes)m" }
            let hours = minutes / 60
            return "\(hours)h"
        case .cron(let expr, _):
            let parts = expr.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard parts.count >= 5 else { return nil }
            if parts[0].hasPrefix("*/"), let n = Int(parts[0].dropFirst(2)) { return "\(n)m" }
            if parts[0] != "*" && parts[1] == "*" { return "1h" }
            if parts[0] != "*" && parts[1] != "*" { return "24h" }
            return "1h"
        case .at:
            return nil
        }
    }

    // MARK: - Claude Provider Check

    private var isClaudeProvider: Bool {
        AppState.shared.currentCLIIdentifier == "claude"
    }

    // MARK: - Local Job Persistence

    /// IDs of jobs that were loaded from local storage.
    private var localJobIds: Set<String> = []

    private func isLocalJob(_ id: String) -> Bool {
        localJobIds.contains(id)
    }

    func persistLocalJobs() {
        let localJobs = jobs.filter { localJobIds.contains($0.id) }
        do {
            let dir = Self.localJobsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(localJobs)
            try data.write(to: Self.localJobsURL, options: .atomic)
        } catch {
            logger.error("Failed to persist local jobs: \(error.localizedDescription)")
        }
    }

    private func loadLocalJobs() {
        guard FileManager.default.fileExists(atPath: Self.localJobsURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.localJobsURL)
            let loaded = try JSONDecoder().decode([CronJob].self, from: data)
            localJobIds = Set(loaded.map(\.id))
            // Replace jobs array with local jobs (avoids duplicates)
            jobs = loaded
        } catch {
            logger.error("Failed to load local jobs: \(error.localizedDescription)")
        }
    }

    // MARK: - Local Run Logs

    /// Append a run log entry for a local job and persist to disk.
    func appendRunLog(
        jobId: String,
        status: String,
        summary: String? = nil,
        error: String? = nil,
        startMs: Int,
        durationMs: Int? = nil
    ) {
        let entry = CronRunLogEntry(
            ts: startMs,
            jobId: jobId,
            action: "run",
            status: status,
            error: error,
            summary: summary,
            runAtMs: startMs,
            durationMs: durationMs,
            nextRunAtMs: nil
        )

        // If viewing this job, update the UI immediately
        if selectedJobId == jobId {
            runEntries.insert(entry, at: 0)
        }

        // Persist to disk
        var allLogs = loadAllRunLogs()
        allLogs.append(entry)

        // Trim: keep only the last N entries per job
        let grouped = Dictionary(grouping: allLogs, by: \.jobId)
        var trimmed: [CronRunLogEntry] = []
        for (_, entries) in grouped {
            let sorted = entries.sorted { $0.ts > $1.ts }
            trimmed.append(contentsOf: sorted.prefix(Self.maxRunLogsPerJob))
        }

        persistRunLogs(trimmed)
    }

    /// Load run log entries for a specific job from local storage.
    private func loadLocalRunLogs(jobId: String, limit: Int) -> [CronRunLogEntry] {
        let allLogs = loadAllRunLogs()
        return allLogs
            .filter { $0.jobId == jobId }
            .sorted { $0.ts > $1.ts }
            .prefix(limit)
            .map { $0 }
    }

    private func loadAllRunLogs() -> [CronRunLogEntry] {
        guard FileManager.default.fileExists(atPath: Self.runLogsURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: Self.runLogsURL)
            return try JSONDecoder().decode([CronRunLogEntry].self, from: data)
        } catch {
            logger.error("Failed to load run logs: \(error.localizedDescription)")
            return []
        }
    }

    private func persistRunLogs(_ logs: [CronRunLogEntry]) {
        do {
            let dir = Self.runLogsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(logs)
            try data.write(to: Self.runLogsURL, options: .atomic)
        } catch {
            logger.error("Failed to persist run logs: \(error.localizedDescription)")
        }
    }

    /// Build a CronJob from the editor payload dictionary.
    private func buildCronJob(from payload: [String: AnyCodableValue], existingId: String?) -> CronJob {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let id = existingId ?? UUID().uuidString

        // Track this as a local job
        localJobIds.insert(id)

        let name: String = {
            if case .string(let n) = payload["name"] { return n }
            return "Untitled"
        }()

        let description: String? = {
            if case .string(let d) = payload["description"] { return d }
            return nil
        }()

        let agentId: String? = {
            if case .string(let a) = payload["agentId"], !a.isEmpty { return a }
            return nil
        }()

        let enabled: Bool = {
            if case .bool(let e) = payload["enabled"] { return e }
            return true
        }()

        let deleteAfterRun: Bool? = {
            if case .bool(let d) = payload["deleteAfterRun"] { return d }
            return nil
        }()

        let schedule: CronSchedule = {
            if case .dictionary(let s) = payload["schedule"],
               case .string(let kind) = s["kind"] {
                switch kind {
                case "at":
                    if case .string(let at) = s["at"] { return .at(at: at) }
                case "every":
                    if case .int(let ms) = s["everyMs"] {
                        let anchor: Int? = {
                            if case .int(let a) = s["anchorMs"] { return a }
                            return nil
                        }()
                        return .every(everyMs: ms, anchorMs: anchor)
                    }
                case "cron":
                    if case .string(let expr) = s["expr"] {
                        let tz: String? = {
                            if case .string(let t) = s["tz"] { return t }
                            return nil
                        }()
                        return .cron(expr: expr, tz: tz)
                    }
                default: break
                }
            }
            return .every(everyMs: 3_600_000, anchorMs: nil)
        }()

        let sessionTarget: CronSessionTarget = {
            if case .string(let s) = payload["sessionTarget"],
               let t = CronSessionTarget(rawValue: s) { return t }
            return .isolated
        }()

        let wakeMode: CronWakeMode = {
            if case .string(let w) = payload["wakeMode"],
               let m = CronWakeMode(rawValue: w) { return m }
            return .now
        }()

        let cronPayload: CronPayload = {
            if case .dictionary(let p) = payload["payload"] {
                let message: String = {
                    if case .string(let m) = p["message"] { return m }
                    if case .string(let t) = p["text"] { return t }
                    return ""
                }()
                let thinking: String? = {
                    if case .string(let t) = p["thinking"] { return t }
                    return nil
                }()
                let timeout: Int? = {
                    if case .int(let t) = p["timeoutSeconds"] { return t }
                    return nil
                }()
                return .agentTurn(
                    message: message, thinking: thinking,
                    timeoutSeconds: timeout, deliver: nil,
                    channel: nil, to: nil, bestEffortDeliver: nil,
                    connectorBindings: nil
                )
            }
            return .agentTurn(
                message: "", thinking: nil, timeoutSeconds: nil,
                deliver: nil, channel: nil, to: nil,
                bestEffortDeliver: nil, connectorBindings: nil
            )
        }()

        let delivery: CronDelivery? = {
            if case .dictionary(let d) = payload["delivery"] {
                let mode: CronDeliveryMode = {
                    if case .string(let m) = d["mode"],
                       let dm = CronDeliveryMode(rawValue: m) { return dm }
                    return .none
                }()
                let channel: String? = {
                    if case .string(let c) = d["channel"] { return c }
                    return nil
                }()
                return CronDelivery(mode: mode, channel: channel, to: nil, bestEffort: nil)
            }
            return nil
        }()

        // Preserve existing state if editing
        let existingState: CronJobState = {
            if let existingId, let existing = jobs.first(where: { $0.id == existingId }) {
                return existing.state
            }
            return CronJobState()
        }()

        return CronJob(
            id: id, agentId: agentId, model: nil, name: name, description: description,
            enabled: enabled, deleteAfterRun: deleteAfterRun,
            createdAtMs: existingId != nil ? (jobs.first { $0.id == existingId }?.createdAtMs ?? nowMs) : nowMs,
            updatedAtMs: nowMs,
            schedule: schedule, sessionTarget: sessionTarget, wakeMode: wakeMode,
            payload: cronPayload, delivery: delivery, state: existingState
        )
    }

    // MARK: - Gateway Events

    private func handleCronEvent(_ evt: CronEvent) {
        scheduleRefresh(delayMs: 250)
        if evt.action == "finished", let selected = selectedJobId, selected == evt.jobId {
            scheduleRunsRefresh(jobId: selected, delayMs: 200)
        }

        // Post to ScheduleNotificationStore if the job uses "notifications" delivery
        if evt.action == "finished" || evt.action == "error" {
            if let job = jobs.first(where: { $0.id == evt.jobId }),
               job.delivery?.channel == "notifications" {
                let status: ScheduleNotification.Status =
                    (evt.status ?? "").lowercased() == "ok" ? .success :
                    (evt.status ?? "").lowercased() == "timeout" ? .timeout : .error
                ScheduleNotificationStore.shared.add(
                    scheduleName: job.displayName,
                    scheduleId: job.id,
                    provider: job.agentId,
                    summary: evt.summary ?? evt.error ?? "Completed",
                    status: status
                )
            }
        }
    }

    private func scheduleRefresh(delayMs: Int = 250) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            await self.refreshJobs()
        }
    }

    private func scheduleRunsRefresh(jobId: String, delayMs: Int = 200) {
        runsTask?.cancel()
        runsTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            await self.refreshRuns(jobId: jobId)
        }
    }
}

// MARK: - Errors

enum CronError: Error, LocalizedError {
    case noCLI

    var errorDescription: String? {
        switch self {
        case .noCLI: "No CLI provider available"
        }
    }
}

