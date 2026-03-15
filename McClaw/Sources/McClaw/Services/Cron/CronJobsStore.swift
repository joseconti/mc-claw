import Foundation
import Logging
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

    private let logger = Logger(label: "ai.mcclaw.cron")
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var runsTask: Task<Void, Never>?
    private var sessionEventTask: Task<Void, Never>?

    private let pollInterval: TimeInterval = 30

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
    }

    /// Handle events from the BackgroundCLISession.
    private func handleSessionEvent(_ event: BackgroundCLISession.SessionEvent) {
        switch event {
        case .stateChanged(let newState):
            claudeSessionActive = (newState == .running)
            if newState == .running {
                Task {
                    claudeSessionPID = await BackgroundCLISession.shared.processId
                }
            } else {
                claudeSessionPID = nil
            }
            logger.info("Claude background session state: \(newState)")

        case .taskFired(let taskId, let output):
            logger.info("Claude task fired: \(taskId), output: \(output.prefix(200))")
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            if let index = jobs.firstIndex(where: { $0.id == taskId }) {
                var state = jobs[index].state
                state.lastRunAtMs = nowMs
                state.lastStatus = "ok"
                state.lastError = nil
                let job = jobs[index]
                jobs[index] = CronJob(
                    id: job.id, agentId: job.agentId, model: job.model,
                    name: job.name, description: job.description,
                    enabled: job.enabled, deleteAfterRun: job.deleteAfterRun,
                    createdAtMs: job.createdAtMs, updatedAtMs: nowMs,
                    schedule: job.schedule, sessionTarget: job.sessionTarget,
                    wakeMode: job.wakeMode, payload: job.payload,
                    delivery: job.delivery, state: state
                )
                persistLocalJobs()

                appendRunLog(
                    jobId: taskId,
                    status: "ok",
                    summary: String(output.prefix(500)),
                    startMs: nowMs
                )

                if let delivery = job.delivery {
                    let summary = String(output.prefix(500))
                    Task {
                        await LocalScheduler.shared.deliverCronResults(
                            delivery: delivery, job: job,
                            summary: summary, status: .success
                        )
                    }
                }
            }

        case .error(let msg):
            logger.error("Claude background session error: \(msg)")
            lastError = msg

        case .processExited(let status):
            logger.warning("Claude background process exited: \(status)")
            claudeSessionActive = false
            claudeSessionPID = nil

        case .text:
            break
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
                    let sent = await BackgroundCLISession.shared.scheduleTask(
                        interval: interval, message: message
                    )
                    if !sent {
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

