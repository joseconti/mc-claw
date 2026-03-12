import Foundation
import Logging
import McClawKit

/// Local scheduler that executes scheduled jobs in the background.
/// Works independently of Gateway — runs as long as McClaw is alive
/// (even when minimized to the menu bar).
///
/// - Claude provider: delegates to `claude task` (native scheduling).
/// - Other providers: this scheduler handles execution directly via CLIBridge.
@MainActor
final class LocalScheduler {
    static let shared = LocalScheduler()

    private let logger = Logger(label: "ai.mcclaw.local-scheduler")
    private var timerTask: Task<Void, Never>?
    private var runningJobIds: Set<String> = []

    /// How often the scheduler checks for jobs to fire (seconds).
    private let tickInterval: TimeInterval = 15

    /// Whether the scheduler is currently active.
    private(set) var isRunning = false

    private init() {}

    // MARK: - Lifecycle

    /// Start the scheduler loop. Safe to call multiple times.
    func start() {
        guard timerTask == nil else { return }
        isRunning = true
        logger.info("LocalScheduler started (tick every \(Int(tickInterval))s)")

        timerTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: UInt64((self?.tickInterval ?? 15) * 1_000_000_000))
            }
        }
    }

    /// Stop the scheduler loop.
    func stop() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
        logger.info("LocalScheduler stopped")
    }

    // MARK: - Tick

    /// One scheduler tick: check all enabled jobs and fire those that are due.
    private func tick() async {
        let store = CronJobsStore.shared
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)

        for job in store.jobs where job.enabled {
            // Skip Claude-native jobs (agentId nil or "claude") — they use `claude task`
            let agent = job.agentId ?? ""
            if agent.isEmpty || agent == "claude" { continue }

            // Skip if already running
            guard !runningJobIds.contains(job.id) else { continue }

            // Check if job is due
            guard shouldFire(job: job, nowMs: nowMs) else { continue }

            // Fire!
            runningJobIds.insert(job.id)
            logger.info("Firing job '\(job.displayName)' (id: \(job.id))")

            Task { [weak self] in
                await self?.executeJob(job)
                self?.runningJobIds.remove(job.id)
            }
        }
    }

    // MARK: - Schedule Evaluation

    /// Determine if a job should fire now.
    private func shouldFire(job: CronJob, nowMs: Int) -> Bool {
        // If the store already computed a nextRunAtMs, use it
        if let nextMs = job.state.nextRunAtMs {
            return nowMs >= nextMs
        }

        // Otherwise compute from the schedule
        switch job.schedule {
        case .at(let at):
            guard let date = CronSchedule.parseAtDate(at) else { return false }
            let atMs = Int(date.timeIntervalSince1970 * 1000)
            // Fire if the time has arrived and the job hasn't run yet
            return nowMs >= atMs && job.state.lastRunAtMs == nil

        case .every(let everyMs, let anchorMs):
            let anchor = anchorMs ?? job.createdAtMs
            let lastRun = job.state.lastRunAtMs ?? anchor
            return nowMs >= lastRun + everyMs

        case .cron(let expr, let tz):
            guard let nextDate = nextCronDate(expr: expr, tz: tz, after: lastRunOrCreation(job)) else {
                return false
            }
            let nextMs = Int(nextDate.timeIntervalSince1970 * 1000)
            return nowMs >= nextMs
        }
    }

    private func lastRunOrCreation(_ job: CronJob) -> Date {
        if let ms = job.state.lastRunAtMs {
            return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        }
        return Date(timeIntervalSince1970: TimeInterval(job.createdAtMs) / 1000)
    }

    // MARK: - Job Execution

    /// Execute a job by sending its message to the appropriate CLI provider.
    /// Full pipeline: Pre-fetch → AI analysis → @fetch extra → @action writes → Delivery
    private func executeJob(_ job: CronJob) async {
        let startMs = Int(Date().timeIntervalSince1970 * 1000)

        // Resolve the CLI provider
        guard let provider = resolveProvider(for: job) else {
            logger.error("No provider found for job '\(job.displayName)'")
            updateJobState(jobId: job.id, startMs: startMs, status: "error", error: "Provider not found")
            postNotification(job: job, summary: "Provider not found", status: .error)
            return
        }

        // Extract message from payload
        let message: String
        switch job.payload {
        case .agentTurn(let msg, _, _, _, _, _, _, let bindings):
            // Enrich with connector data if bindings exist
            if let bindings, !bindings.isEmpty {
                message = await PromptEnrichmentService.shared.enrichForCronJob(
                    message: msg,
                    bindings: bindings
                )
            } else {
                message = msg
            }
        case .systemEvent(let text):
            message = text
        }

        guard !message.isEmpty else {
            logger.warning("Empty message for job '\(job.displayName)', skipping")
            updateJobState(jobId: job.id, startMs: startMs, status: "error", error: "Empty message")
            return
        }

        // Build dynamic system prompt with all connected services
        let cronSystemPrompt = buildCronSystemPrompt()

        let timeout = extractTimeout(from: job)

        // --- Phase 1: Initial AI execution ---
        var responseText = ""
        var hadError = false
        var errorMessage: String?

        (responseText, hadError, errorMessage) = await sendToCLI(
            message: message,
            provider: provider,
            systemPrompt: cronSystemPrompt,
            timeout: timeout
        )

        guard !hadError else {
            let endMs = Int(Date().timeIntervalSince1970 * 1000)
            updateJobState(jobId: job.id, startMs: startMs, status: "error", error: errorMessage, durationMs: endMs - startMs)
            postNotification(job: job, summary: errorMessage ?? "Unknown error", status: .error)
            return
        }

        // --- Phase 2: @fetch extra data (max 2 rounds) ---
        for fetchRound in 1...2 {
            let fetchCommands = ConnectorsKit.extractFetchCommands(responseText)
            guard !fetchCommands.isEmpty else { break }

            logger.info("Job '\(job.displayName)' @fetch round \(fetchRound): \(fetchCommands.count) commands")

            let fetchResults = await executeFetchCommands(fetchCommands)
            let cleanResponse = ConnectorsKit.removeFetchCommands(responseText)

            // Re-send to AI with fetched data
            let enrichedMessage = ConnectorsKit.buildEnrichedPrompt(
                original: cleanResponse,
                results: fetchResults
            )

            (responseText, hadError, errorMessage) = await sendToCLI(
                message: enrichedMessage,
                provider: provider,
                systemPrompt: cronSystemPrompt,
                timeout: timeout
            )

            guard !hadError else { break }
        }

        // --- Phase 3: @action write operations ---
        var actionSummary: String?
        let actionCommands = ConnectorsKit.extractActionCommands(responseText)
        if !actionCommands.isEmpty {
            logger.info("Job '\(job.displayName)' executing \(actionCommands.count) @action commands")
            let actionResults = await executeActionCommands(Array(actionCommands.prefix(ConnectorsKit.maxActionCommandsPerTurn)))
            actionSummary = ConnectorsKit.buildActionResultsSummary(results: actionResults)
            responseText = ConnectorsKit.removeActionCommands(responseText)
            if let summary = actionSummary {
                responseText += "\n\n" + summary
            }
        }

        // --- Phase 4: Finalize ---
        let endMs = Int(Date().timeIntervalSince1970 * 1000)
        let durationMs = endMs - startMs
        let wasTimeout = false

        let status: String
        let notifStatus: ScheduleNotification.Status
        if hadError {
            status = "error"
            notifStatus = .error
        } else {
            status = "ok"
            notifStatus = .success
        }

        let summary = hadError ? (errorMessage ?? "Unknown error") :
                       wasTimeout ? (errorMessage ?? "Timeout") :
                       String(responseText.prefix(500))

        updateJobState(
            jobId: job.id,
            startMs: startMs,
            status: status,
            error: hadError ? errorMessage : nil,
            durationMs: durationMs
        )

        // Deliver results
        if let delivery = job.delivery {
            await deliverResults(delivery: delivery, job: job, summary: summary, status: notifStatus)
        }

        // Handle deleteAfterRun (one-time schedules)
        if job.deleteAfterRun == true {
            await CronJobsStore.shared.removeJob(id: job.id)
        }

        logger.info("Job '\(job.displayName)' completed: \(status) (\(durationMs)ms)")
    }

    // MARK: - CLI Communication

    /// Send a message to CLI and collect the response.
    private func sendToCLI(
        message: String,
        provider: CLIProviderInfo,
        systemPrompt: String,
        timeout: Int?
    ) async -> (response: String, hadError: Bool, errorMessage: String?) {
        var responseText = ""
        var hadError = false
        var errorMessage: String?

        let stream = await CLIBridge.shared.send(
            message: message,
            provider: provider,
            sessionId: nil,
            systemPrompt: systemPrompt
        )

        let collectTask = Task {
            for await event in stream {
                switch event {
                case .text(let text):
                    responseText += text
                case .error(let err):
                    hadError = true
                    errorMessage = err
                case .done:
                    break
                default:
                    break
                }
            }
        }

        if let timeout {
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                collectTask.cancel()
            }
            await collectTask.value
            timeoutTask.cancel()
            if collectTask.isCancelled && !hadError {
                hadError = true
                errorMessage = "Timed out after \(timeout)s"
            }
        } else {
            await collectTask.value
        }

        return (responseText, hadError, errorMessage)
    }

    // MARK: - Dynamic System Prompt

    /// Build a system prompt that lists all connected services with their read/write actions.
    private func buildCronSystemPrompt() -> String {
        var lines: [String] = [
            "This is an automated scheduled task. Execute ALL actions directly without asking for permission.",
            "IMPORTANT: Do NOT use any MCP tools or external tools that require user confirmation.",
            "Use ONLY @fetch and @action commands to interact with connected services.",
            "",
        ]

        // Gather connected services
        let store = ConnectorStore.shared
        let connectedInstances = store.connectedInstances
        if !connectedInstances.isEmpty {
            lines.append("Connected services:")
            for instance in connectedInstances {
                guard let def = ConnectorRegistry.definition(for: instance.definitionId) else { continue }
                let readActions = def.actions.filter { !$0.isWriteAction }.map { $0.id }
                let writeActions = def.actions.filter { $0.isWriteAction }.map { $0.id }
                var actionDesc = ""
                if !readActions.isEmpty { actionDesc += "READ: \(readActions.joined(separator: ", "))" }
                if !writeActions.isEmpty {
                    if !actionDesc.isEmpty { actionDesc += " | " }
                    actionDesc += "WRITE: \(writeActions.joined(separator: ", "))"
                }
                lines.append("- \(instance.definitionId): \(actionDesc)")
            }
            lines.append("")
        }

        // Gather connected native channels
        let channelManager = NativeChannelsManager.shared
        let connectedChannels = channelManager.connectedChannelIds
        if !connectedChannels.isEmpty {
            lines.append("Connected delivery channels: \(connectedChannels.joined(separator: ", "))")
            lines.append("")
        }

        lines.append(contentsOf: [
            "To read additional data: @fetch(connector.action, param=value)",
            "To execute a write action: @action(connector.action, param=value)",
            "",
            "Rules:",
            "1. Execute ALL actions directly. NEVER ask for permission or confirmation.",
            "2. Pre-fetched data (if any) is provided above the task description.",
            "3. The delivery channel is already configured — focus on the task, not on notifying.",
            "4. After completing actions, summarize what you did in plain text.",
            "5. You can chain @fetch and @action: first read more data if needed, then act.",
        ])

        return lines.joined(separator: "\n")
    }

    // MARK: - @fetch Execution

    /// Execute @fetch commands and return results.
    private func executeFetchCommands(
        _ commands: [ConnectorsKit.FetchCommand]
    ) async -> [(connector: String, action: String, data: String)] {
        var results: [(connector: String, action: String, data: String)] = []

        for cmd in commands {
            guard let instance = resolveInstance(for: cmd.connector) else {
                results.append((connector: cmd.connector, action: cmd.action, data: "Error: No connected instance for '\(cmd.connector)'"))
                continue
            }
            do {
                let result = try await ConnectorExecutor.shared.execute(
                    instanceId: instance.id,
                    actionId: cmd.action,
                    params: cmd.params
                )
                results.append((connector: cmd.connector, action: cmd.action, data: result.data))
            } catch {
                results.append((connector: cmd.connector, action: cmd.action, data: "Error: \(error.localizedDescription)"))
                logger.warning("@fetch failed: \(cmd.connector).\(cmd.action): \(error)")
            }
        }

        return results
    }

    // MARK: - @action Execution

    /// Execute @action commands and return results.
    private func executeActionCommands(
        _ commands: [ConnectorsKit.ActionCommand]
    ) async -> [(connector: String, action: String, success: Bool, message: String)] {
        var results: [(connector: String, action: String, success: Bool, message: String)] = []

        for cmd in commands {
            guard let instance = resolveInstance(for: cmd.connector) else {
                results.append((connector: cmd.connector, action: cmd.action, success: false, message: "No connected instance for '\(cmd.connector)'"))
                continue
            }
            do {
                let result = try await ConnectorExecutor.shared.execute(
                    instanceId: instance.id,
                    actionId: cmd.action,
                    params: cmd.params
                )
                results.append((connector: cmd.connector, action: cmd.action, success: true, message: result.data))
                logger.info("@action OK: \(cmd.connector).\(cmd.action)")
            } catch {
                results.append((connector: cmd.connector, action: cmd.action, success: false, message: error.localizedDescription))
                logger.warning("@action FAILED: \(cmd.connector).\(cmd.action): \(error)")
            }
        }

        return results
    }

    /// Resolve a connector name to a connected instance. Matches by definition ID, name, or suffix.
    private func resolveInstance(for name: String) -> ConnectorInstance? {
        let connected = ConnectorStore.shared.connectedInstances
        let lower = name.lowercased()

        if let match = connected.first(where: { $0.definitionId.lowercased() == lower }) {
            return match
        }
        if let match = connected.first(where: {
            $0.definitionId.lowercased().hasSuffix(".\(lower)") ||
            $0.definitionId.lowercased() == "google.\(lower)" ||
            $0.definitionId.lowercased() == "microsoft.\(lower)"
        }) {
            return match
        }
        if let match = connected.first(where: { $0.name.lowercased() == lower }) {
            return match
        }
        return nil
    }

    // MARK: - Manual Run

    /// Execute a job on demand (triggered by user "Run Now" button).
    func manualRun(job: CronJob) async {
        guard !runningJobIds.contains(job.id) else { return }
        runningJobIds.insert(job.id)
        await executeJob(job)
        runningJobIds.remove(job.id)
    }

    // MARK: - Delivery

    /// Known native channel IDs for routing delivery.
    private static let nativeChannelIds: Set<String> = [
        "telegram", "slack", "discord", "matrix", "mattermost",
        "mastodon", "zulip", "rocketchat", "twitch"
    ]

    /// Deliver job results to configured targets (notifications, native channels, etc.).
    private func deliverResults(
        delivery: CronDelivery,
        job: CronJob,
        summary: String,
        status: ScheduleNotification.Status
    ) async {
        let targets = delivery.allTargets

        if targets.isEmpty {
            // Single-target legacy: check the channel field
            if delivery.channel == "notifications" {
                postNotification(job: job, summary: summary, status: status)
            } else if let channel = delivery.channel, Self.nativeChannelIds.contains(channel) {
                let sent = await NativeChannelsManager.shared.sendMessage(
                    channelId: channel,
                    text: "[\(job.displayName)] \(summary)",
                    recipientId: delivery.to ?? ""
                )
                if !sent {
                    logger.warning("Failed to deliver job '\(job.displayName)' to \(channel)")
                }
            }
            return
        }

        // Multi-target delivery
        for target in targets {
            if target.channel == "notifications" {
                postNotification(job: job, summary: summary, status: status)
            } else if Self.nativeChannelIds.contains(target.channel) {
                let sent = await NativeChannelsManager.shared.sendMessage(
                    channelId: target.channel,
                    text: "[\(job.displayName)] \(summary)",
                    recipientId: target.to ?? ""
                )
                if !sent && target.bestEffort != true {
                    logger.warning("Failed to deliver job '\(job.displayName)' to \(target.channel)")
                }
            }
        }
    }

    // MARK: - Helpers

    /// Find the CLI provider to use for a job.
    private func resolveProvider(for job: CronJob) -> CLIProviderInfo? {
        let state = AppState.shared
        // If job specifies an agentId, find that CLI
        if let agentId = job.agentId, !agentId.isEmpty {
            return state.availableCLIs.first { $0.id == agentId && $0.isInstalled }
        }
        // Otherwise use the currently active CLI
        return state.currentCLI
    }

    /// Extract timeout from job payload.
    private func extractTimeout(from job: CronJob) -> Int? {
        if case .agentTurn(_, _, let timeoutSeconds, _, _, _, _, _) = job.payload {
            return timeoutSeconds
        }
        return nil
    }

    /// Update the CronJob state after execution.
    private func updateJobState(
        jobId: String,
        startMs: Int,
        status: String,
        error: String? = nil,
        durationMs: Int? = nil
    ) {
        let store = CronJobsStore.shared
        guard let index = store.jobs.firstIndex(where: { $0.id == jobId }) else { return }

        var job = store.jobs[index]
        var newState = job.state
        newState.lastRunAtMs = startMs
        newState.lastStatus = status
        newState.lastError = error
        newState.lastDurationMs = durationMs
        newState.runningAtMs = nil

        // Calculate next run
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        switch job.schedule {
        case .every(let everyMs, _):
            newState.nextRunAtMs = nowMs + everyMs
        case .cron(let expr, let tz):
            if let next = nextCronDate(expr: expr, tz: tz, after: Date()) {
                newState.nextRunAtMs = Int(next.timeIntervalSince1970 * 1000)
            }
        case .at:
            newState.nextRunAtMs = nil // One-time, no next run
        }

        // Create updated job with new state
        let updated = CronJob(
            id: job.id,
            agentId: job.agentId,
            name: job.name,
            description: job.description,
            enabled: job.enabled,
            deleteAfterRun: job.deleteAfterRun,
            createdAtMs: job.createdAtMs,
            updatedAtMs: nowMs,
            schedule: job.schedule,
            sessionTarget: job.sessionTarget,
            wakeMode: job.wakeMode,
            payload: job.payload,
            delivery: job.delivery,
            state: newState
        )
        store.jobs[index] = updated
        store.persistLocalJobs()
    }

    /// Post a notification to the ScheduleNotificationStore.
    private func postNotification(
        job: CronJob,
        summary: String,
        status: ScheduleNotification.Status
    ) {
        ScheduleNotificationStore.shared.add(
            scheduleName: job.displayName,
            scheduleId: job.id,
            provider: job.agentId,
            summary: summary,
            status: status
        )
    }

    // MARK: - Cron Expression Parser (basic 5-field)

    /// Calculate the next fire date for a basic cron expression.
    /// Supports standard 5-field format: minute hour day-of-month month day-of-week
    func nextCronDate(expr: String, tz: String?, after: Date) -> Date? {
        let parts = expr.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard parts.count >= 5 else { return nil }

        let calendar: Calendar
        if let tz, let timeZone = TimeZone(identifier: tz) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            calendar = cal
        } else {
            calendar = Calendar.current
        }

        let minuteSpec = parts[0]
        let hourSpec = parts[1]
        let domSpec = parts[2]
        let monthSpec = parts[3]
        let dowSpec = parts[4]

        // Search up to 366 days ahead
        var candidate = calendar.date(byAdding: .minute, value: 1, to: after) ?? after
        // Round down to start of minute
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: candidate)
        candidate = calendar.date(from: comps) ?? candidate

        for _ in 0..<(366 * 24 * 60) {
            let c = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: candidate)
            guard let min = c.minute, let hour = c.hour,
                  let day = c.day, let month = c.month, let weekday = c.weekday else {
                candidate = calendar.date(byAdding: .minute, value: 1, to: candidate) ?? candidate
                continue
            }

            // Weekday: Calendar uses 1=Sunday, cron uses 0=Sunday
            let cronDow = weekday - 1

            if matches(minuteSpec, value: min, range: 0...59) &&
               matches(hourSpec, value: hour, range: 0...23) &&
               matches(domSpec, value: day, range: 1...31) &&
               matches(monthSpec, value: month, range: 1...12) &&
               matches(dowSpec, value: cronDow, range: 0...6) {
                return candidate
            }

            candidate = calendar.date(byAdding: .minute, value: 1, to: candidate) ?? candidate
        }

        return nil
    }

    /// Check if a cron field spec matches a value.
    /// Supports: * (any), N (exact), N-M (range), */N (step), N,M,O (list)
    private func matches(_ spec: String, value: Int, range: ClosedRange<Int>) -> Bool {
        if spec == "*" { return true }

        // List: "1,5,10"
        let parts = spec.components(separatedBy: ",")
        for part in parts {
            // Step: "*/5" or "1-10/2"
            if part.contains("/") {
                let stepParts = part.components(separatedBy: "/")
                guard stepParts.count == 2, let step = Int(stepParts[1]), step > 0 else { continue }
                let baseRange: ClosedRange<Int>
                if stepParts[0] == "*" {
                    baseRange = range
                } else if stepParts[0].contains("-") {
                    let bounds = stepParts[0].components(separatedBy: "-")
                    guard bounds.count == 2, let lo = Int(bounds[0]), let hi = Int(bounds[1]) else { continue }
                    baseRange = lo...hi
                } else {
                    guard let lo = Int(stepParts[0]) else { continue }
                    baseRange = lo...range.upperBound
                }
                if baseRange.contains(value) && (value - baseRange.lowerBound) % step == 0 {
                    return true
                }
            }
            // Range: "1-5"
            else if part.contains("-") {
                let bounds = part.components(separatedBy: "-")
                guard bounds.count == 2, let lo = Int(bounds[0]), let hi = Int(bounds[1]) else { continue }
                if value >= lo && value <= hi { return true }
            }
            // Exact: "5"
            else if let exact = Int(part) {
                if value == exact { return true }
            }
        }

        return false
    }
}
