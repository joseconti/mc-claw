import SwiftUI

/// Wizard-style editor for creating/editing scheduled actions.
/// 4 steps: What → Which AI → When → Where (delivery).
struct CronJobEditor: View {
    let job: CronJob?
    @Binding var isSaving: Bool
    @Binding var error: String?
    let onCancel: () -> Void
    let onSave: ([String: AnyCodableValue]) -> Void

    // MARK: - Wizard State

    enum WizardStep: Int, CaseIterable {
        case what = 0
        case whichAI = 1
        case when = 2
        case deliver = 3

        var title: String {
            switch self {
            case .what: String(localized: "What to do")
            case .whichAI: String(localized: "Which AI")
            case .when: String(localized: "When")
            case .deliver: String(localized: "Results")
            }
        }

        var icon: String {
            switch self {
            case .what: "text.bubble"
            case .whichAI: "cpu"
            case .when: "clock"
            case .deliver: "paperplane"
            }
        }
    }

    @State private var currentStep: WizardStep = .what

    // MARK: - Step 1: What

    @State private var name: String = ""
    @State private var taskDescription: String = ""

    // MARK: - Step 2: Which AI

    @State private var selectedProvider: String = ""

    // MARK: - Step 3: When

    enum WhenChoice: String, CaseIterable, Identifiable {
        case once = "Once"
        case repeating = "Repeating"
        case advanced = "Advanced"
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .once: String(localized: "Once")
            case .repeating: String(localized: "Repeating")
            case .advanced: String(localized: "Advanced")
            }
        }
    }
    @State private var whenChoice: WhenChoice = .repeating
    @State private var atDate: Date = .init().addingTimeInterval(60 * 5)
    @State private var deleteAfterRun: Bool = false

    // Repeating presets
    enum RepeatPreset: String, CaseIterable, Identifiable {
        case every15m = "Every 15 minutes"
        case every1h = "Every hour"
        case every6h = "Every 6 hours"
        case daily = "Every day"
        case weekly = "Every week"
        case custom = "Custom interval"
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .every15m: String(localized: "Every 15 minutes")
            case .every1h: String(localized: "Every hour")
            case .every6h: String(localized: "Every 6 hours")
            case .daily: String(localized: "Every day")
            case .weekly: String(localized: "Every week")
            case .custom: String(localized: "Custom interval")
            }
        }

        var durationText: String? {
            switch self {
            case .every15m: "15m"
            case .every1h: "1h"
            case .every6h: "6h"
            case .daily: "1d"
            case .weekly: "7d"
            case .custom: nil
            }
        }
    }
    @State private var repeatPreset: RepeatPreset = .daily
    @State private var customInterval: String = "1h"

    // Advanced (cron expression)
    @State private var cronExpr: String = "0 9 * * *"
    @State private var cronTz: String = ""

    // MARK: - Step 4: Delivery

    enum DeliverChoice: String, CaseIterable, Identifiable {
        case notifications = "Notifications"
        case channel = "Send to a channel"
        case mcclaw = "Save only in history"
        case none = "No notification"
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .notifications: String(localized: "Notifications")
            case .channel: String(localized: "Send to a channel")
            case .mcclaw: String(localized: "Save only in history")
            case .none: String(localized: "No notification")
            }
        }
    }
    @State private var deliverChoice: DeliverChoice = .notifications
    @State private var deliveryChannel: String = "telegram"
    @State private var deliveryTo: String = ""
    @State private var bestEffortDeliver: Bool = true

    // MARK: - Advanced (hidden by default)

    @State private var showAdvanced: Bool = false
    @State private var sessionTarget: CronSessionTarget = .isolated
    @State private var wakeMode: CronWakeMode = .now
    @State private var thinking: String = ""
    @State private var timeoutSeconds: String = ""
    @State private var enabled: Bool = true

    /// Connector bindings for prompt enrichment (Data Sources).
    @State private var connectorBindings: [ConnectorBinding?] = []

    private var hasConnectedConnectors: Bool {
        !ConnectorStore.shared.connectedInstances.isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            Divider()

            // Step indicator
            stepIndicator
                .padding(.vertical, 16)

            // Step content
            ScrollView(.vertical) {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)
            }

            // Error
            if let error, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 28)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Navigation buttons
            navigationBar
        }
        .frame(minWidth: 600, minHeight: 520)
        .onAppear { hydrateFromJob() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job == nil ? String(localized: "New Schedule") : String(localized: "Edit Schedule"))
                .font(.title3.weight(.semibold))
            Text(stepExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private var stepExplanation: String {
        switch currentStep {
        case .what:
            String(localized: "Describe what you want the AI to do. Write it naturally, like you would explain it to someone.")
        case .whichAI:
            String(localized: "Choose which AI provider will execute this task.")
        case .when:
            String(localized: "Configure when this action should run.")
        case .deliver:
            String(localized: "Choose where to see the results.")
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(WizardStep.allCases, id: \.rawValue) { step in
                stepBadge(step)
                if step.rawValue < WizardStep.allCases.count - 1 {
                    stepConnector(isCompleted: step.rawValue < currentStep.rawValue)
                }
            }
        }
        .padding(.horizontal, 28)
    }

    private func stepBadge(_ step: WizardStep) -> some View {
        let isCurrent = step == currentStep
        let isCompleted = step.rawValue < currentStep.rawValue
        let isUpcoming = step.rawValue > currentStep.rawValue

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isCurrent ? Color.accentColor : isCompleted ? Color.green : Color.secondary.opacity(0.2))
                    .frame(width: 32, height: 32)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: step.icon)
                        .font(.caption2)
                        .foregroundStyle(isCurrent ? .white : .secondary)
                }
            }
            Text(step.title)
                .font(.caption2)
                .foregroundStyle(isUpcoming ? .tertiary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            // Allow navigating back to completed steps
            if isCompleted {
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentStep = step
                }
            }
        }
    }

    private func stepConnector(isCompleted: Bool) -> some View {
        Rectangle()
            .fill(isCompleted ? Color.green.opacity(0.5) : Color.secondary.opacity(0.15))
            .frame(height: 2)
            .frame(maxWidth: 60)
            .padding(.bottom, 20) // Align with circles, not labels
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .what: stepWhat
        case .whichAI: stepWhichAI
        case .when: stepWhen
        case .deliver: stepDeliver
        }
    }

    // MARK: Step 1 — What

    private var stepWhat: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Name"))
                    .font(.subheadline.weight(.medium))
                TextField(String(localized: "e.g. Daily email summary"), text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "What should the AI do?"))
                    .font(.subheadline.weight(.medium))
                TextField(
                    String(localized: "e.g. Check my pending emails and send me a summary ordered by priority via Telegram"),
                    text: $taskDescription,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...10)
            }

            // Data sources (only if connectors available)
            if hasConnectedConnectors {
                dataSourcesSection
            }

            Text(String(localized: "Tip: Be specific about what you want. The more detail you give, the better the result."))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    private var dataSourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Data Sources"))
                    .font(.subheadline.weight(.medium))
                Text(String(localized: "(optional)"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text(String(localized: "Pre-fetch data from connected services before running. Results are injected into the prompt automatically."))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(connectorBindings.indices, id: \.self) { index in
                ConnectorBindingRow(
                    index: index,
                    binding: Binding(
                        get: { connectorBindings[index] },
                        set: { connectorBindings[index] = $0 }
                    ),
                    onRemove: {
                        connectorBindings.remove(at: index)
                    }
                )
                if index < connectorBindings.count - 1 {
                    Divider()
                }
            }

            Button {
                connectorBindings.append(nil)
            } label: {
                Label(String(localized: "Add Data Source"), systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Step 2 — Which AI

    private var stepWhichAI: some View {
        VStack(alignment: .leading, spacing: 16) {
            let installedCLIs = AppState.shared.availableCLIs.filter(\.isInstalled)

            // Default option
            providerCard(
                id: "",
                name: String(localized: "Default"),
                subtitle: String(localized: "Uses whichever AI is active when the schedule runs"),
                icon: "sparkles",
                isSelected: selectedProvider == ""
            )

            // Installed CLIs
            ForEach(installedCLIs) { cli in
                providerCard(
                    id: cli.id,
                    name: cli.displayName,
                    subtitle: cli.isAuthenticated ? String(localized: "Ready") : String(localized: "Not authenticated"),
                    icon: iconForCLI(cli.id),
                    isSelected: selectedProvider == cli.id,
                    isDisabled: !cli.isAuthenticated
                )
            }

            if installedCLIs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(String(localized: "No AI providers detected. Install at least one CLI (Claude, Gemini, ChatGPT, or Ollama)."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func providerCard(id: String, name: String, subtitle: String, icon: String, isSelected: Bool, isDisabled: Bool = false) -> some View {
        Button {
            if !isDisabled {
                selectedProvider = id
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.1)))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isDisabled ? .tertiary : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isDisabled ? .tertiary : .secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.title3)
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func iconForCLI(_ id: String) -> String {
        switch id.lowercased() {
        case let s where s.contains("claude"): "brain.head.profile"
        case let s where s.contains("gemini"): "sparkle"
        case let s where s.contains("chatgpt"): "bubble.left.and.bubble.right"
        case let s where s.contains("ollama"): "desktopcomputer"
        default: "cpu"
        }
    }

    // MARK: Step 3 — When

    private var stepWhen: some View {
        VStack(alignment: .leading, spacing: 16) {
            // When choice picker
            Picker("", selection: $whenChoice) {
                ForEach(WhenChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            switch whenChoice {
            case .once:
                whenOnce
            case .repeating:
                whenRepeating
            case .advanced:
                whenAdvanced
            }
        }
    }

    private var whenOnce: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Date and time"))
                    .font(.subheadline.weight(.medium))
                DatePicker("", selection: $atDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.graphical)
            }

            Toggle(String(localized: "Delete this schedule after it runs successfully"), isOn: $deleteAfterRun)
                .font(.callout)
        }
    }

    private var whenRepeating: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(RepeatPreset.allCases) { preset in
                Button {
                    repeatPreset = preset
                } label: {
                    HStack {
                        Image(systemName: repeatPreset == preset ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(repeatPreset == preset ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        Text(preset.displayName)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if repeatPreset == .custom {
                HStack(spacing: 8) {
                    Text(String(localized: "Interval:"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "e.g. 30m, 2h, 3d"), text: $customInterval)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    Text(String(localized: "(m = minutes, h = hours, d = days)"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 28)
            }
        }
    }

    private var whenAdvanced: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Cron expression"))
                    .font(.subheadline.weight(.medium))
                TextField(String(localized: "e.g. 0 9 * * 1-5"), text: $cronExpr)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Timezone"))
                    .font(.subheadline.weight(.medium))
                TextField(String(localized: "e.g. Europe/Madrid (optional)"), text: $cronTz)
                    .textFieldStyle(.roundedBorder)
            }

            // Quick reference
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Quick reference"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                cronExample("0 9 * * *", String(localized: "Every day at 9:00 AM"))
                cronExample("0 9 * * 1-5", String(localized: "Weekdays at 9:00 AM"))
                cronExample("0 */6 * * *", String(localized: "Every 6 hours"))
                cronExample("0 9 * * 1", String(localized: "Every Monday at 9:00 AM"))
                cronExample("0 0 1 * *", String(localized: "First day of every month"))
            }
            .padding(10)
            .background(Color.secondary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func cronExample(_ expr: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Text(expr)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .frame(width: 120, alignment: .leading)
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Step 4 — Delivery

    private var stepDeliver: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(DeliverChoice.allCases) { choice in
                deliverCard(choice)
            }

            if deliverChoice == .channel {
                channelConfig
            }

            // Advanced options toggle
            Divider()
                .padding(.top, 8)

            DisclosureGroup(String(localized: "Advanced options"), isExpanded: $showAdvanced) {
                advancedOptions
                    .padding(.top, 8)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            // Summary
            summaryCard
        }
    }

    private func deliverCard(_ choice: DeliverChoice) -> some View {
        let isSelected = deliverChoice == choice
        let icon: String = switch choice {
        case .notifications: "bell.badge"
        case .channel: "paperplane"
        case .mcclaw: "tray.full"
        case .none: "bell.slash"
        }
        let subtitle: String = switch choice {
        case .notifications: String(localized: "Show in Notifications and as macOS system notification")
        case .channel: String(localized: "Send results via Telegram, Slack, or another channel")
        case .mcclaw: String(localized: "Results are saved in the schedule's run history only")
        case .none: String(localized: "Run silently without any notification")
        }

        return Button {
            deliverChoice = choice
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var channelConfig: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Channel"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "e.g. telegram, slack, whatsapp"), text: $deliveryChannel)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Recipient (optional)"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Chat ID, phone, etc."), text: $deliveryTo)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Toggle(String(localized: "Continue even if delivery fails"), isOn: $bestEffortDeliver)
                .font(.callout)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Thinking level"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "e.g. low, medium, high"), text: $thinking)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Timeout (seconds)"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "e.g. 120"), text: $timeoutSeconds)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Session"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $sessionTarget) {
                        Text(String(localized: "Isolated")).tag(CronSessionTarget.isolated)
                        Text(String(localized: "Main")).tag(CronSessionTarget.main)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Wake mode"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $wakeMode) {
                        Text(String(localized: "Immediately")).tag(CronWakeMode.now)
                        Text(String(localized: "Next heartbeat")).tag(CronWakeMode.nextHeartbeat)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            Toggle(String(localized: "Enabled"), isOn: $enabled)
                .font(.callout)
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Summary"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                summaryRow(String(localized: "Task"), name.isEmpty ? String(localized: "Unnamed") : name)
                summaryRow(String(localized: "AI"), selectedProvider.isEmpty ? String(localized: "Default (active)") : selectedProvider)
                summaryRow(String(localized: "When"), whenSummaryText)
                summaryRow(String(localized: "Results"), deliverChoice.displayName)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    private var whenSummaryText: String {
        switch whenChoice {
        case .once:
            String(localized: "Once on \(atDate.formatted(date: .abbreviated, time: .shortened))")
        case .repeating:
            if repeatPreset == .custom {
                String(localized: "Every \(customInterval)")
            } else {
                repeatPreset.displayName
            }
        case .advanced:
            cronExpr.isEmpty ? String(localized: "Not configured") : cronExpr
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Button(String(localized: "Cancel")) { onCancel() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

            Spacer()

            if currentStep.rawValue > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if let prev = WizardStep(rawValue: currentStep.rawValue - 1) {
                            currentStep = prev
                        }
                    }
                } label: {
                    Label(String(localized: "Back"), systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }

            if currentStep == .deliver {
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(String(localized: "Save Schedule"))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || !canSave)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if let next = WizardStep(rawValue: currentStep.rawValue + 1) {
                            currentStep = next
                        }
                    }
                } label: {
                    Label(String(localized: "Next"), systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
    }

    private var canAdvance: Bool {
        switch currentStep {
        case .what:
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .whichAI:
            true // "Default" is always valid
        case .when:
            switch whenChoice {
            case .once: true
            case .repeating:
                if repeatPreset == .custom {
                    DurationFormatting.parseDurationMs(customInterval) != nil
                } else { true }
            case .advanced:
                !cronExpr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .deliver:
            true
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Hydrate

    private func hydrateFromJob() {
        guard let job else { return }
        name = job.name
        selectedProvider = job.agentId ?? ""
        enabled = job.enabled
        deleteAfterRun = job.deleteAfterRun ?? false
        sessionTarget = job.sessionTarget
        wakeMode = job.wakeMode

        switch job.schedule {
        case let .at(at):
            whenChoice = .once
            if let date = CronSchedule.parseAtDate(at) { atDate = date }
        case let .every(everyMs, _):
            whenChoice = .repeating
            let text = DurationFormatting.concise(ms: everyMs)
            // Try to match a preset
            if let preset = RepeatPreset.allCases.first(where: { $0.durationText == text }) {
                repeatPreset = preset
            } else {
                repeatPreset = .custom
                customInterval = text
            }
        case let .cron(expr, tz):
            whenChoice = .advanced
            cronExpr = expr
            cronTz = tz ?? ""
        }

        switch job.payload {
        case let .systemEvent(text):
            taskDescription = text
        case let .agentTurn(message, thinkingVal, timeoutVal, _, _, _, _, bindings):
            taskDescription = message
            thinking = thinkingVal ?? ""
            timeoutSeconds = timeoutVal.map(String.init) ?? ""
            if let bindings, !bindings.isEmpty {
                connectorBindings = bindings.map { Optional($0) }
            }
        }

        if let delivery = job.delivery {
            switch delivery.mode {
            case .announce:
                let ch = (delivery.channel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if ch == "notifications" {
                    deliverChoice = .notifications
                } else {
                    deliverChoice = .channel
                    deliveryChannel = ch.isEmpty ? "telegram" : ch
                    deliveryTo = delivery.to ?? ""
                    bestEffortDeliver = delivery.bestEffort ?? true
                }
            case .none:
                deliverChoice = .none
            case .webhook:
                deliverChoice = .channel
            }
        } else if sessionTarget == .main {
            deliverChoice = .mcclaw
        }

        // Description field (used as secondary info if available)
        if let desc = job.description, !desc.isEmpty, taskDescription.isEmpty {
            taskDescription = desc
        }

        // Show advanced if non-default values
        if sessionTarget == .main || wakeMode == .nextHeartbeat || !thinking.isEmpty || !timeoutSeconds.isEmpty {
            showAdvanced = true
        }
    }

    // MARK: - Save

    private func save() {
        do {
            error = nil
            let payload = try buildPayload()
            onSave(payload)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func buildPayload() throws -> [String: AnyCodableValue] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "Cron", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: String(localized: "Name is required.")])
        }

        let trimmedTask = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTask.isEmpty else {
            throw NSError(domain: "Cron", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: String(localized: "Task description is required.")])
        }

        let schedule = try buildSchedule()
        let effectiveSession = resolveSessionTarget()
        let payload = buildTaskPayload(message: trimmedTask, session: effectiveSession)

        var root: [String: Any] = [
            "name": trimmedName,
            "enabled": enabled,
            "schedule": schedule,
            "sessionTarget": effectiveSession.rawValue,
            "wakeMode": wakeMode.rawValue,
            "payload": payload,
        ]

        let trimmedProvider = selectedProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProvider.isEmpty {
            root["agentId"] = trimmedProvider
        } else if job?.agentId != nil {
            root["agentId"] = NSNull()
        }

        if whenChoice == .once {
            root["deleteAfterRun"] = deleteAfterRun
        } else if job?.deleteAfterRun != nil {
            root["deleteAfterRun"] = false
        }

        if effectiveSession == .isolated {
            root["delivery"] = buildDelivery()
        }

        return root.mapValues { toAnyCodableValue($0) }
    }

    /// Resolve session target based on delivery choice and advanced settings.
    private func resolveSessionTarget() -> CronSessionTarget {
        // If user explicitly set it in advanced options, respect that
        if showAdvanced { return sessionTarget }
        // Channel delivery requires isolated session
        if deliverChoice == .channel { return .isolated }
        // Default: isolated (agentTurn) for most use cases
        return .isolated
    }

    private func buildSchedule() throws -> [String: Any] {
        switch whenChoice {
        case .once:
            return ["kind": "at", "at": CronSchedule.formatIsoDate(atDate)]
        case .repeating:
            let durationText = repeatPreset == .custom ? customInterval : (repeatPreset.durationText ?? "1d")
            guard let ms = DurationFormatting.parseDurationMs(durationText) else {
                throw NSError(domain: "Cron", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid interval format. Use 10m, 1h, 1d.")])
            }
            return ["kind": "every", "everyMs": ms]
        case .advanced:
            let expr = cronExpr.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !expr.isEmpty else {
                throw NSError(domain: "Cron", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: String(localized: "Cron expression is required.")])
            }
            let tz = cronTz.trimmingCharacters(in: .whitespacesAndNewlines)
            if tz.isEmpty { return ["kind": "cron", "expr": expr] }
            return ["kind": "cron", "expr": expr, "tz": tz]
        }
    }

    private func buildTaskPayload(message: String, session: CronSessionTarget) -> [String: Any] {
        // For main session, use systemEvent; otherwise agentTurn
        if session == .main {
            return ["kind": "systemEvent", "text": message]
        }

        var payload: [String: Any] = ["kind": "agentTurn", "message": message]
        let t = thinking.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { payload["thinking"] = t }
        if let n = Int(timeoutSeconds), n > 0 { payload["timeoutSeconds"] = n }

        // Include connector bindings if any are configured
        let validBindings = connectorBindings.compactMap { $0 }
        if !validBindings.isEmpty {
            let encoded = validBindings.map { binding -> [String: Any] in
                var dict: [String: Any] = [
                    "connectorInstanceId": binding.connectorInstanceId,
                    "actionId": binding.actionId,
                    "maxResultLength": binding.maxResultLength,
                ]
                if !binding.params.isEmpty {
                    dict["params"] = binding.params
                }
                return dict
            }
            payload["connectorBindings"] = encoded
        }

        return payload
    }

    private func buildDelivery() -> [String: Any] {
        switch deliverChoice {
        case .notifications:
            // Announce mode with "notifications" as the channel — McClaw intercepts this
            return ["mode": "announce", "channel": "notifications", "bestEffort": true]
        case .channel:
            var delivery: [String: Any] = ["mode": "announce"]
            let trimmed = deliveryChannel.trimmingCharacters(in: .whitespacesAndNewlines)
            delivery["channel"] = trimmed.isEmpty ? "last" : trimmed
            let toVal = deliveryTo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !toVal.isEmpty { delivery["to"] = toVal }
            if bestEffortDeliver {
                delivery["bestEffort"] = true
            } else if job?.delivery?.bestEffort == true {
                delivery["bestEffort"] = false
            }
            return delivery
        case .mcclaw, .none:
            return ["mode": "none"]
        }
    }

    /// Convert Any to AnyCodableValue for Gateway RPC.
    private func toAnyCodableValue(_ value: Any) -> AnyCodableValue {
        switch value {
        case let s as String: return .string(s)
        case let i as Int: return .int(i)
        case let d as Double: return .double(d)
        case let b as Bool: return .bool(b)
        case is NSNull: return .null
        case let dict as [String: Any]:
            return .dictionary(dict.mapValues { toAnyCodableValue($0) })
        case let arr as [Any]:
            return .array(arr.map { toAnyCodableValue($0) })
        default:
            return .string(String(describing: value))
        }
    }
}
