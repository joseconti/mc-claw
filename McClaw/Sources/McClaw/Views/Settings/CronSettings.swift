import SwiftUI

/// Cron jobs management tab in Settings.
struct CronSettings: View {
    @State var store: CronJobsStore = .shared
    @State var showEditor = false
    @State var editingJob: CronJob?
    @State var editorError: String?
    @State var isSaving = false
    @State var confirmDelete: CronJob?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            schedulerBanner
            content
            Spacer(minLength: 0)
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
        .alert("Delete cron job?", isPresented: Binding(
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cron")
                    .font(.headline)
                Text("Manage scheduled jobs. Claude uses native `claude task`; other providers use Gateway cron.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    Task { await store.refreshJobs() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isLoadingJobs)

                Button {
                    editorError = nil
                    editingJob = nil
                    showEditor = true
                } label: {
                    Label("New Job", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Scheduler Banner

    private var schedulerBanner: some View {
        Group {
            if store.schedulerEnabled == false {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Cron scheduler is disabled")
                            .font(.headline)
                        Spacer()
                    }
                    Text("Jobs are saved, but they will not run automatically until `cron.enabled` is set to `true` and the Gateway restarts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let storePath = store.schedulerStorePath, !storePath.isEmpty {
                        Text(storePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.orange.opacity(0.10))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if let err = store.lastError {
                    Text("Error: \(err)")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if let msg = store.statusMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                List(selection: $store.selectedJobId) {
                    ForEach(store.jobs) { job in
                        jobRow(job)
                            .tag(job.id)
                            .contextMenu { jobContextMenu(job) }
                    }
                }
                .listStyle(.inset)
            }
            .frame(width: 250)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selected = selectedJob {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    detailHeader(selected)
                    detailCard(selected)
                    runHistoryCard(selected)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select a job to inspect details and run history.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Tip: use 'New Job' to add one, or enable cron in your gateway config.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 8)
        }
    }

    // MARK: - Job Row

    private func jobRow(_ job: CronJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(job.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !job.enabled {
                    statusPill("disabled", tint: .secondary)
                } else if let next = job.nextRunDate {
                    statusPill(nextRunLabel(next), tint: .secondary)
                } else {
                    statusPill("no next run", tint: .secondary)
                }
            }
            HStack(spacing: 6) {
                statusPill(job.sessionTarget.rawValue, tint: .secondary)
                statusPill(job.wakeMode.rawValue, tint: .secondary)
                if let agentId = job.agentId, !agentId.isEmpty {
                    statusPill("agent \(agentId)", tint: .secondary)
                }
                if let status = job.state.lastStatus {
                    statusPill(status, tint: status == "ok" ? .green : .orange)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func jobContextMenu(_ job: CronJob) -> some View {
        Button("Run now") { Task { await store.runJob(id: job.id, force: true) } }
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

    // MARK: - Detail Header

    private func detailHeader(_ job: CronJob) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayName)
                    .font(.title3.weight(.semibold))
                Text(job.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 8) {
                Toggle("Enabled", isOn: Binding(
                    get: { job.enabled },
                    set: { enabled in Task { await store.setJobEnabled(id: job.id, enabled: enabled) } }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                Button("Run") { Task { await store.runJob(id: job.id, force: true) } }
                    .buttonStyle(.borderedProminent)
                Button("Edit") {
                    editingJob = job
                    editorError = nil
                    showEditor = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Detail Card

    private func detailCard(_ job: CronJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Schedule") { Text(scheduleSummary(job.schedule)).font(.callout) }
            if case .at = job.schedule, job.deleteAfterRun == true {
                LabeledContent("Auto-delete") { Text("after success") }
            }
            if let desc = job.description, !desc.isEmpty {
                LabeledContent("Description") { Text(desc).font(.callout) }
            }
            if let agentId = job.agentId, !agentId.isEmpty {
                LabeledContent("Agent") { Text(agentId) }
            }
            LabeledContent("Session") { Text(job.sessionTarget.rawValue) }
            LabeledContent("Wake") { Text(job.wakeMode.rawValue) }
            LabeledContent("Next run") {
                if let date = job.nextRunDate {
                    Text(date.formatted(date: .abbreviated, time: .standard))
                } else {
                    Text("\u{2014}").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Last run") {
                if let date = job.lastRunDate {
                    Text("\(date.formatted(date: .abbreviated, time: .standard)) \u{00b7} \(relativeAge(from: date))")
                } else {
                    Text("\u{2014}").foregroundStyle(.secondary)
                }
            }
            if let status = job.state.lastStatus {
                LabeledContent("Last status") { Text(status) }
            }
            if let err = job.state.lastError, !err.isEmpty {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
            payloadSummary(job)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    // MARK: - Run History

    private func runHistoryCard(_ job: CronJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Run history")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.refreshRuns(jobId: job.id) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isLoadingRuns)
            }

            if store.isLoadingRuns {
                ProgressView().controlSize(.small)
            }

            if store.runEntries.isEmpty {
                Text("No run log entries yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.runEntries) { entry in
                        runRow(entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private func runRow(_ entry: CronRunLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusPill(entry.status ?? "unknown", tint: statusTint(entry.status))
                Text(entry.date.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let ms = entry.durationMs {
                    Text("\(ms)ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let summary = entry.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            if let error = entry.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Payload Summary

    private func payloadSummary(_ job: CronJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Payload")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            switch job.payload {
            case let .systemEvent(text):
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
            case let .agentTurn(message, thinking, timeoutSeconds, _, _, _, _, _):
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.callout)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        if let thinking, !thinking.isEmpty { statusPill("think \(thinking)", tint: .secondary) }
                        if let timeoutSeconds { statusPill("\(timeoutSeconds)s", tint: .secondary) }
                        if job.sessionTarget == .isolated, let delivery = job.delivery {
                            if delivery.mode == .announce {
                                statusPill("announce", tint: .secondary)
                                if let channel = delivery.channel, !channel.isEmpty {
                                    statusPill(channel, tint: .secondary)
                                }
                                if let to = delivery.to, !to.isEmpty {
                                    statusPill(to, tint: .secondary)
                                }
                            } else {
                                statusPill("no delivery", tint: .secondary)
                            }
                        }
                    }
                }
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

    private func statusTint(_ status: String?) -> Color {
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
                return "at \(date.formatted(date: .abbreviated, time: .standard))"
            }
            return "at \(at)"
        case let .every(everyMs, _):
            return "every \(DurationFormatting.concise(ms: everyMs))"
        case let .cron(expr, tz):
            if let tz, !tz.isEmpty { return "cron \(expr) (\(tz))" }
            return "cron \(expr)"
        }
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
    }
}
