import Foundation
import Logging
import McClawProtocol

/// Manages cron jobs with hybrid backend:
/// - Claude CLI: delegates to `claude task` (native scheduling)
/// - Other providers: uses LocalScheduler for background execution
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

    var isLoadingJobs = false
    var isLoadingRuns = false
    var lastError: String?
    var statusMessage: String?

    private let logger = Logger(label: "ai.mcclaw.cron")
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var runsTask: Task<Void, Never>?

    private let pollInterval: TimeInterval = 30

    private static let localJobsURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw", isDirectory: true)
        return dir.appendingPathComponent("schedules.json")
    }()

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

        // Start polling (for Claude task sync + local job state refresh)
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
        LocalScheduler.shared.stop()
    }

    // MARK: - Refresh

    func refreshJobs() async {
        guard !isLoadingJobs else { return }
        isLoadingJobs = true
        lastError = nil
        statusMessage = nil
        defer { isLoadingJobs = false }

        // Check if current provider is Claude (uses native task scheduling)
        if isClaudeProvider {
            await refreshClaudeJobs()
            // Also merge in local jobs (user may have created schedules for other providers)
            mergeLocalJobs()
            return
        }

        // Local scheduler for non-Claude providers
        loadLocalJobs()
        schedulerEnabled = true
        if jobs.isEmpty {
            statusMessage = "No scheduled tasks yet."
        }
    }

    func refreshRuns(jobId: String, limit: Int = 200) async {
        guard !isLoadingRuns else { return }
        isLoadingRuns = true
        defer { isLoadingRuns = false }

        if isClaudeProvider {
            // Claude CLI doesn't have run logs via Gateway
            runEntries = []
            return
        }

        do {
            runEntries = try await GatewayConnectionService.shared.cronRuns(jobId: jobId, limit: limit)
        } catch {
            logger.error("cron.runs failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    // MARK: - CRUD

    func runJob(id: String, force: Bool = true) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }

        // Claude tasks use native `claude task` — can't force-run
        if isClaudeProvider && job.agentId == nil {
            return
        }

        // For local jobs, execute directly via LocalScheduler logic
        if isLocalJob(id) {
            // Mark as running and let LocalScheduler handle it
            logger.info("Manual run of local job '\(job.displayName)'")
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
        if isClaudeProvider, let job = jobs.first(where: { $0.id == id }), job.agentId == nil {
            await removeClaudeTask(id: id)
            return
        }

        // Remove from local storage
        jobs.removeAll { $0.id == id }
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
        // Always save locally so the job is visible in the list
        let job = buildCronJob(from: payload, existingId: id)
        if let existingIndex = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[existingIndex] = job
        } else {
            jobs.append(job)
        }
        persistLocalJobs()

        // Additionally delegate to Claude CLI for native scheduling (best-effort)
        if isClaudeProvider {
            let agentId = payload["agentId"]
            let isForClaude = agentId == nil || agentId == .string("claude") || agentId == .string("")
            if isForClaude {
                do {
                    try await upsertClaudeTask(payload: payload)
                } catch {
                    logger.warning("Claude task create failed (job saved locally): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Claude CLI Task Integration

    private var isClaudeProvider: Bool {
        AppState.shared.currentCLIIdentifier == "claude"
    }

    /// Refresh jobs from `claude task list` output.
    /// Only replaces Claude-sourced jobs; local jobs are preserved.
    private func refreshClaudeJobs() async {
        do {
            let output = try await runClaudeCommand(["task", "list", "--json"])
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

            // Empty output or non-JSON means no tasks from Claude CLI
            guard !trimmed.isEmpty, trimmed.hasPrefix("[") || trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8) else {
                // Remove only Claude-sourced jobs (non-local), keep local jobs
                jobs.removeAll { !localJobIds.contains($0.id) }
                if jobs.isEmpty {
                    statusMessage = "No scheduled tasks."
                }
                return
            }

            let tasks = try JSONDecoder().decode([ClaudeTask].self, from: data)
            let claudeJobs = tasks.map { $0.toCronJob() }

            // Remove old Claude-sourced jobs, keep local, add fresh Claude jobs
            jobs.removeAll { !localJobIds.contains($0.id) }
            for cj in claudeJobs where !jobs.contains(where: { $0.id == cj.id }) {
                jobs.append(cj)
            }

            if jobs.isEmpty {
                statusMessage = "No scheduled tasks."
            }
        } catch {
            logger.error("claude task list failed: \(error.localizedDescription)")
            // Keep local jobs intact — only clear Claude-sourced ones
            jobs.removeAll { !localJobIds.contains($0.id) }
            if jobs.isEmpty {
                statusMessage = "No scheduled tasks (or `claude task` not available)."
            }
        }
    }

    private func removeClaudeTask(id: String) async {
        do {
            _ = try await runClaudeCommand(["task", "delete", id])
            await refreshJobs()
            if selectedJobId == id {
                selectedJobId = nil
                runEntries = []
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func upsertClaudeTask(payload: [String: AnyCodableValue]) async throws {
        // Extract fields from payload for claude task create
        var args = ["task", "create"]

        if case .string(let name) = payload["name"] {
            args += ["--name", name]
        }
        if case .dictionary(let schedule) = payload["schedule"],
           case .string(let kind) = schedule["kind"] {
            switch kind {
            case "every":
                if case .int(let ms) = schedule["everyMs"] {
                    args += ["--every", DurationFormatting.concise(ms: ms)]
                }
            case "cron":
                if case .string(let expr) = schedule["expr"] {
                    args += ["--cron", expr]
                }
            case "at":
                if case .string(let at) = schedule["at"] {
                    args += ["--at", at]
                }
            default:
                break
            }
        }
        if case .dictionary(let payloadDict) = payload["payload"],
           case .string(let message) = payloadDict["message"] {
            args += ["--message", message]
        } else if case .dictionary(let payloadDict) = payload["payload"],
                  case .string(let text) = payloadDict["text"] {
            args += ["--message", text]
        }

        _ = try await runClaudeCommand(args)
        await refreshJobs()
    }

    /// Run a Claude CLI command and return stdout.
    private func runClaudeCommand(_ args: [String]) async throws -> String {
        guard let cli = AppState.shared.currentCLI,
              let binaryPath = cli.binaryPath else {
            throw CronError.noCLI
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment
        process.environment?["NO_COLOR"] = "1"

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
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

    /// Merge local jobs into the current jobs list (for Claude provider that also has local jobs).
    private func mergeLocalJobs() {
        guard FileManager.default.fileExists(atPath: Self.localJobsURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.localJobsURL)
            let loaded = try JSONDecoder().decode([CronJob].self, from: data)
            for job in loaded {
                localJobIds.insert(job.id)
                if !jobs.contains(where: { $0.id == job.id }) {
                    jobs.append(job)
                }
            }
        } catch {
            logger.error("Failed to load local jobs for merge: \(error.localizedDescription)")
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

// MARK: - Claude Task DTO

/// Maps `claude task list --json` output to CronJob.
private struct ClaudeTask: Codable {
    let id: String
    let name: String?
    let schedule: String?
    let message: String?
    let createdAt: String?
    let enabled: Bool?

    func toCronJob() -> CronJob {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let scheduleModel: CronSchedule
        if let schedule, schedule.contains("*") {
            scheduleModel = .cron(expr: schedule, tz: nil)
        } else if let schedule, let ms = DurationFormatting.parseDurationMs(schedule) {
            scheduleModel = .every(everyMs: ms, anchorMs: nil)
        } else {
            scheduleModel = .every(everyMs: 3_600_000, anchorMs: nil)
        }

        return CronJob(
            id: id,
            agentId: nil,
            model: nil,
            name: name ?? "Claude Task",
            description: nil,
            enabled: enabled ?? true,
            deleteAfterRun: nil,
            createdAtMs: now,
            updatedAtMs: now,
            schedule: scheduleModel,
            sessionTarget: .isolated,
            wakeMode: .now,
            payload: .agentTurn(
                message: message ?? "",
                thinking: nil,
                timeoutSeconds: nil,
                deliver: nil,
                channel: nil,
                to: nil,
                bestEffortDeliver: nil,
                connectorBindings: nil),
            delivery: nil,
            state: CronJobState()
        )
    }
}
