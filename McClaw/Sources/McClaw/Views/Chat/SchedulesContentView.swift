import SwiftUI

/// Main content view for the Schedules sidebar section.
/// Provides a clean list+detail layout for managing scheduled actions.
struct SchedulesContentView: View {
    @State private var store = CronJobsStore.shared
    @State private var showEditor = false
    @State private var editingJob: CronJob?
    @State private var editorError: String?
    @State private var isSaving = false
    @State private var confirmDelete: CronJob?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            schedulerBanner
            content
        }
        .onAppear { store.start() }
        .onDisappear { store.stop() }
        .sheet(isPresented: $showEditor) {
            CronJobEditor(
                job: editingJob,
                isSaving: $isSaving,
                error: $editorError,
                onCancel: {
                    showEditor = false
                    editingJob = nil
                },
                onSave: { payload in
                    Task { await save(payload: payload) }
                })
        }
        .alert("Delete this schedule?", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }))
        {
            Button("Cancel", role: .cancel) { confirmDelete = nil }
            Button("Delete", role: .destructive) {
                if let job = confirmDelete {
                    Task { await store.removeJob(id: job.id) }
                }
                confirmDelete = nil
            }
        } message: {
            if let job = confirmDelete {
                Text(job.displayName)
            }
        }
        .onChange(of: store.selectedJobId) { _, newValue in
            guard let newValue else { return }
            Task { await store.refreshRuns(jobId: newValue) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Schedules")
                    .font(.title3.weight(.semibold))
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    Task { await store.refreshJobs() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isLoadingJobs)
                .help("Refresh")

                Button {
                    editorError = nil
                    editingJob = nil
                    showEditor = true
                } label: {
                    Label("New Schedule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var headerSubtitle: String {
        let active = store.jobs.filter(\.enabled).count
        let total = store.jobs.count
        if total == 0 { return "No scheduled actions" }
        let nextRun = store.jobs
            .filter(\.enabled)
            .compactMap(\.nextRunDate)
            .min()
        if let next = nextRun {
            return "\(active) active \u{00b7} Next: \(nextRunLabel(next))"
        }
        return "\(active) active of \(total)"
    }

    // MARK: - Scheduler Banner

    @ViewBuilder
    private var schedulerBanner: some View {
        if store.schedulerEnabled == false {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scheduler is disabled")
                        .font(.callout.weight(.medium))
                    Text("Schedules are saved but will not run until the scheduler is enabled in the Gateway.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.jobs.isEmpty && !store.isLoadingJobs {
            emptyState
        } else {
            HStack(spacing: 0) {
                jobList
                    .frame(width: 260)
                Divider()
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No schedules yet")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Create scheduled actions to automate tasks with any AI provider.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button {
                editorError = nil
                editingJob = nil
                showEditor = true
            } label: {
                Label("Create Schedule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Job List

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.jobs) { job in
                    jobRow(job)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.selectedJobId = job.id
                        }
                        .contextMenu { jobContextMenu(job) }
                }
            }
            .padding(.vertical, 4)
        }
        .background(.background)
    }

    private func jobRow(_ job: CronJob) -> some View {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(statusColor(for: job))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(scheduleSummary(job.schedule))
                    if let next = job.nextRunDate {
                        Text("\u{00b7}")
                        Text(nextRunLabel(next))
                    } else if !job.enabled {
                        Text("\u{00b7} paused")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(store.selectedJobId == job.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func jobContextMenu(_ job: CronJob) -> some View {
        Button("Run Now") { Task { await store.runJob(id: job.id, force: true) } }
        Divider()
        Button(job.enabled ? "Disable" : "Enable") {
            Task { await store.setJobEnabled(id: job.id, enabled: !job.enabled) }
        }
        Button("Edit...") {
            editingJob = job
            editorError = nil
            showEditor = true
        }
        Divider()
        Button("Delete...", role: .destructive) {
            confirmDelete = job
        }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let job = selectedJob {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailHeader(job)
                    detailInfo(job)
                    runHistorySection(job)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Text("Select a schedule to view details")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(_ job: CronJob) -> some View {
        HStack(alignment: .center) {
            Text(job.displayName)
                .font(.title3.weight(.semibold))
            Spacer()
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { job.enabled },
                    set: { enabled in Task { await store.setJobEnabled(id: job.id, enabled: enabled) } }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                Button("Run Now") { Task { await store.runJob(id: job.id, force: true) } }
                    .buttonStyle(.borderedProminent)
                Button("Edit") {
                    editingJob = job
                    editorError = nil
                    showEditor = true
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) {
                    confirmDelete = job
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func detailInfo(_ job: CronJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Schedule") { Text(scheduleSummary(job.schedule)).font(.callout) }
            if let agentId = job.agentId, !agentId.isEmpty {
                LabeledContent("AI Provider") { Text(providerDisplayName(agentId)).font(.callout) }
            }
            LabeledContent("Session") { Text(sessionDisplayName(job.sessionTarget)).font(.callout) }
            LabeledContent("Wake") { Text(wakeDisplayName(job.wakeMode)).font(.callout) }
            if let desc = job.description, !desc.isEmpty {
                LabeledContent("Description") { Text(desc).font(.callout) }
            }
            LabeledContent("Next run") {
                if let date = job.nextRunDate {
                    Text(date.formatted(date: .abbreviated, time: .standard))
                        .font(.callout)
                } else {
                    Text("\u{2014}").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Last run") {
                if let date = job.lastRunDate {
                    Text("\(date.formatted(date: .abbreviated, time: .standard)) \u{00b7} \(relativeAge(from: date))")
                        .font(.callout)
                } else {
                    Text("\u{2014}").foregroundStyle(.secondary)
                }
            }
            if let status = job.state.lastStatus {
                LabeledContent("Last status") {
                    statusPill(status == "ok" ? "Success" : status.capitalized, tint: statusTintForString(status))
                }
            }

            // Payload summary
            payloadSummary(job)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func providerDisplayName(_ id: String) -> String {
        switch id.lowercased() {
        case "claude": return "Claude"
        case "chatgpt": return "ChatGPT"
        case "gemini": return "Gemini"
        case "ollama": return "Ollama"
        case "copilot": return "GitHub Copilot"
        default: return id.capitalized
        }
    }

    private func sessionDisplayName(_ target: CronSessionTarget) -> String {
        switch target {
        case .main: return "Main conversation"
        case .isolated: return "Isolated session"
        }
    }

    private func wakeDisplayName(_ mode: CronWakeMode) -> String {
        switch mode {
        case .now: return "Immediately"
        case .nextHeartbeat: return "Next heartbeat"
        }
    }

    // MARK: - Run History

    private func runHistorySection(_ job: CronJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Run History")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.refreshRuns(jobId: job.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isLoadingRuns)
            }

            if store.isLoadingRuns && !store.runEntries.isEmpty {
                ProgressView().controlSize(.small)
            }

            if store.runEntries.isEmpty && !store.isLoadingRuns {
                Text("No runs yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.runEntries) { entry in
                        runRow(entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func runRow(_ entry: CronRunLogEntry) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusTintForString(entry.status))
                .frame(width: 6, height: 6)
            Text(entry.date.formatted(date: .abbreviated, time: .standard))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let summary = entry.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let ms = entry.durationMs {
                Text(DurationFormatting.concise(ms: ms))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Payload Summary

    private func payloadSummary(_ job: CronJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Payload")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            switch job.payload {
            case let .systemEvent(text):
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .lineLimit(4)
            case let .agentTurn(message, _, _, _, _, _, _, _):
                Text(message)
                    .font(.callout)
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
        }
    }

    // MARK: - Save

    private func save(payload: [String: AnyCodableValue]) async {
        guard !isSaving else { return }
        isSaving = true
        editorError = nil
        do {
            try await store.upsertJob(id: editingJob?.id, payload: payload)
            isSaving = false
            showEditor = false
            editingJob = nil
        } catch {
            isSaving = false
            editorError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private var selectedJob: CronJob? {
        guard let id = store.selectedJobId else { return nil }
        return store.jobs.first { $0.id == id }
    }

    private func statusColor(for job: CronJob) -> Color {
        if !job.enabled { return .gray }
        if let status = job.state.lastStatus?.lowercased(), status == "error" { return .red }
        return .green
    }

    private func statusTintForString(_ status: String?) -> Color {
        switch (status ?? "").lowercased() {
        case "ok": .green
        case "error": .red
        case "skipped": .orange
        default: .secondary
        }
    }

    private func scheduleSummary(_ schedule: CronSchedule) -> String {
        switch schedule {
        case let .at(at):
            if let date = CronSchedule.parseAtDate(at) {
                return date.formatted(date: .abbreviated, time: .shortened)
            }
            return at
        case let .every(everyMs, _):
            return "Every \(humanReadableInterval(ms: everyMs))"
        case let .cron(expr, tz):
            let human = humanReadableCron(expr)
            if let tz, !tz.isEmpty { return "\(human) (\(tz))" }
            return human
        }
    }

    /// Convert a cron expression to a human-readable description.
    private func humanReadableCron(_ expr: String) -> String {
        let parts = expr.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard parts.count >= 5 else { return expr }

        let minute = parts[0]
        let hour = parts[1]
        let dom = parts[2]
        let month = parts[3]
        let dow = parts[4]

        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let monthNames = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

        // Format time string
        func timeString(_ h: String, _ m: String) -> String {
            guard let hi = Int(h), let mi = Int(m) else { return "\(h):\(m)" }
            let hour12 = hi == 0 ? 12 : (hi > 12 ? hi - 12 : hi)
            let ampm = hi < 12 ? "AM" : "PM"
            return mi == 0 ? "\(hour12) \(ampm)" : "\(hour12):\(String(format: "%02d", mi)) \(ampm)"
        }

        // Every N minutes: */N * * * *
        if hour == "*" && dom == "*" && month == "*" && dow == "*" {
            if minute.hasPrefix("*/"), let n = Int(minute.dropFirst(2)) {
                return "Every \(n) minutes"
            }
        }

        // Every N hours: 0 */N * * *
        if minute == "0" && hour.hasPrefix("*/") && dom == "*" && month == "*" && dow == "*" {
            if let n = Int(hour.dropFirst(2)) {
                return n == 1 ? "Every hour" : "Every \(n) hours"
            }
        }

        // Specific time with fixed hour and minute
        if let _ = Int(hour), let _ = Int(minute) {
            let time = timeString(hour, minute)

            // Every day: M H * * *
            if dom == "*" && month == "*" && dow == "*" {
                return "Every day at \(time)"
            }

            // Specific days of week: M H * * 1-5 or M H * * 0,6
            if dom == "*" && month == "*" && dow != "*" {
                if dow == "1-5" {
                    return "Weekdays at \(time)"
                } else if dow == "0,6" || dow == "6,0" {
                    return "Weekends at \(time)"
                }
                let dowList = dow.components(separatedBy: ",")
                let names = dowList.compactMap { Int($0).flatMap { $0 < dayNames.count ? dayNames[$0] : nil } }
                if !names.isEmpty {
                    return "\(names.joined(separator: ", ")) at \(time)"
                }
                return "Every \(dow) at \(time)"
            }

            // Specific day of month: M H D * *
            if let d = Int(dom), month == "*" && dow == "*" {
                let suffix = daySuffix(d)
                return "\(d)\(suffix) of every month at \(time)"
            }

            // Specific month and day: M H D Mo *
            if let d = Int(dom), let mo = Int(month), dow == "*", mo > 0, mo < monthNames.count {
                let suffix = daySuffix(d)
                return "\(monthNames[mo]) \(d)\(suffix) at \(time)"
            }
        }

        // Fallback: return a slightly cleaned-up version
        return "Cron: \(expr)"
    }

    private func daySuffix(_ day: Int) -> String {
        switch day {
        case 1, 21, 31: return "st"
        case 2, 22: return "nd"
        case 3, 23: return "rd"
        default: return "th"
        }
    }

    /// Convert milliseconds to a human-readable interval.
    private func humanReadableInterval(ms: Int) -> String {
        if ms < 60_000 { return "\(ms / 1000) seconds" }
        let minutes = ms / 60_000
        if minutes < 60 {
            return minutes == 1 ? "minute" : "\(minutes) minutes"
        }
        let hours = minutes / 60
        if hours < 24 {
            return hours == 1 ? "hour" : "\(hours) hours"
        }
        let days = hours / 24
        return days == 1 ? "day" : "\(days) days"
    }

    private func nextRunLabel(_ date: Date, now: Date = .init()) -> String {
        let delta = date.timeIntervalSince(now)
        if delta <= 0 { return "due" }
        if delta < 60 { return "in <1m" }
        let minutes = Int(round(delta / 60))
        if minutes < 60 { return "in \(minutes)m" }
        let hours = Int(round(Double(minutes) / 60))
        if hours < 48 { return "in \(hours)h" }
        let days = Int(round(Double(hours) / 24))
        return "in \(days)d"
    }

    private func relativeAge(from date: Date, now: Date = .init()) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "just now" }
        let minutes = Int(delta / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }

    private func statusPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(Capsule())
            .liquidGlassCapsule(interactive: false)
    }
}
