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
        case scheduled = "Scheduled interval"
        case custom = "Custom interval"
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .every15m: String(localized: "Every 15 minutes")
            case .every1h: String(localized: "Every hour")
            case .every6h: String(localized: "Every 6 hours")
            case .daily: String(localized: "Every day")
            case .weekly: String(localized: "Every week")
            case .scheduled: String(localized: "Every X time at...")
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
            case .scheduled, .custom: nil
            }
        }
    }
    @State private var repeatPreset: RepeatPreset = .daily
    @State private var customInterval: String = "1h"

    // Scheduled interval ("Every X [unit] at HH:MM")
    enum ScheduleUnit: String, CaseIterable, Identifiable {
        case minutes, hours, days, weeks, months, years
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .minutes: String(localized: "Minutes")
            case .hours: String(localized: "Hours")
            case .days: String(localized: "Days")
            case .weeks: String(localized: "Weeks")
            case .months: String(localized: "Months")
            case .years: String(localized: "Years")
            }
        }

        /// Whether this unit supports a "at HH:MM" time picker.
        var supportsTime: Bool {
            switch self {
            case .minutes, .hours: false
            case .days, .weeks, .months, .years: true
            }
        }
    }
    @State private var scheduledAmount: Int = 1
    @State private var scheduledUnit: ScheduleUnit = .days
    @State private var scheduledTime: Date = {
        var cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 9
        comps.minute = 0
        return cal.date(from: comps) ?? Date()
    }()

    // Advanced (cron expression)
    @State private var cronExpr: String = "0 9 * * *"
    @State private var cronTz: String = ""

    // MARK: - Step 4: Delivery (multi-select)

    /// A single delivery destination (native channel + optional recipient).
    struct DeliveryDestination: Identifiable {
        let id = UUID()
        var channelId: String     // e.g. "telegram", "slack"
        var channelName: String   // display name
        var channelIcon: String   // SF Symbol
        var recipient: String = ""
    }

    @State private var deliverNotifications: Bool = true
    @State private var deliverSaveHistory: Bool = false
    @State private var deliveryDestinations: [DeliveryDestination] = []
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
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: step.icon)
                        .font(.subheadline)
                        .foregroundStyle(isCurrent ? .white : .secondary)
                }
            }
            Text(step.title)
                .font(.subheadline)
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
                    .mcclawTextField()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "What should the AI do?"))
                    .font(.subheadline.weight(.medium))
                TextField(
                    String(localized: "e.g. Check my pending emails and send me a summary ordered by priority via Telegram"),
                    text: $taskDescription,
                    axis: .vertical
                )
                .mcclawTextField()
                .lineLimit(4...10)
            }

            // Data sources (only if connectors available)
            if hasConnectedConnectors {
                dataSourcesSection
            }

            Text(String(localized: "Tip: Be specific about what you want. The more detail you give, the better the result."))
                .font(.subheadline)
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
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Text(String(localized: "Pre-fetch data from connected services before running. Results are injected into the prompt automatically."))
                .font(.subheadline)
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
            let installedCLIs = AppState.shared.installedAIProviders

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
                        .font(.subheadline)
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

            if repeatPreset == .scheduled {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(String(localized: "Every"))
                            .font(.callout)
                        Stepper(value: $scheduledAmount, in: 1...99) {
                            Text("\(scheduledAmount)")
                                .font(.body.monospacedDigit())
                                .frame(width: 30, alignment: .center)
                        }
                        .frame(width: 110)
                        Picker("", selection: $scheduledUnit) {
                            ForEach(ScheduleUnit.allCases) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    if scheduledUnit.supportsTime {
                        HStack(spacing: 8) {
                            Text(String(localized: "At"))
                                .font(.callout)
                            DatePicker("", selection: $scheduledTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .frame(width: 100)
                        }
                    }
                }
                .padding(.leading, 28)
            }

            if repeatPreset == .custom {
                HStack(spacing: 8) {
                    Text(String(localized: "Interval:"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "e.g. 30m, 2h, 3d"), text: $customInterval)
                        .mcclawTextField()
                        .frame(width: 150)
                    Text(String(localized: "(m = minutes, h = hours, d = days)"))
                        .font(.subheadline)
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
                    .mcclawTextField()
                    .font(.body.monospaced())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Timezone"))
                    .font(.subheadline.weight(.medium))
                TextField(String(localized: "e.g. Europe/Madrid (optional)"), text: $cronTz)
                    .mcclawTextField()
            }

            // Quick reference
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Quick reference"))
                    .font(.subheadline.weight(.semibold))
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Step 4 — Delivery (multi-select)

    /// Configured native channels available for delivery.
    private var availableNativeChannels: [(id: String, name: String, icon: String)] {
        NativeChannelsManager.availableChannels
            .filter { NativeChannelsManager.shared.hasValidConnector(for: $0.id) }
            .map { ($0.id, $0.name, $0.icon) }
    }

    private var stepDeliver: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Select one or more delivery methods:"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Notifications toggle
            deliverToggleCard(
                icon: "bell.badge",
                title: String(localized: "Notifications"),
                subtitle: String(localized: "Show as macOS system notification"),
                isOn: $deliverNotifications
            )

            // Save in history toggle
            deliverToggleCard(
                icon: "tray.full",
                title: String(localized: "Save only in history"),
                subtitle: String(localized: "Results are saved in the schedule's run history"),
                isOn: $deliverSaveHistory
            )

            // Native channels section
            if !availableNativeChannels.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Send to channels"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Select channels to receive the results. You can add the same channel multiple times with different recipients."))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)

                    // Available channels as selectable chips
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(availableNativeChannels, id: \.id) { channel in
                            Button {
                                deliveryDestinations.append(
                                    DeliveryDestination(
                                        channelId: channel.id,
                                        channelName: channel.name,
                                        channelIcon: channel.icon
                                    )
                                )
                            } label: {
                                Label(channel.name, systemImage: channel.icon)
                                    .font(.callout)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Added destinations
                if !deliveryDestinations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($deliveryDestinations) { $dest in
                            deliveryDestinationRow(destination: $dest)
                        }
                    }

                    Toggle(String(localized: "Continue even if delivery fails"), isOn: $bestEffortDeliver)
                        .font(.callout)
                        .padding(.top, 4)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Configure native channels in Settings → Channels to enable channel delivery."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func deliverToggleCard(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(isOn.wrappedValue ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .padding(10)
            .background(isOn.wrappedValue ? Color.accentColor.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn.wrappedValue ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func deliveryDestinationRow(destination: Binding<DeliveryDestination>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: destination.wrappedValue.channelIcon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            Text(destination.wrappedValue.channelName)
                .font(.callout.weight(.medium))
                .frame(width: 80, alignment: .leading)
            TextField(
                String(localized: "Recipient (Chat ID, channel, etc.)"),
                text: destination.recipient
            )
            .mcclawTextField()
            Button {
                deliveryDestinations.removeAll { $0.id == destination.wrappedValue.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Thinking level"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "e.g. low, medium, high"), text: $thinking)
                        .mcclawTextField()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Timeout (seconds)"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "e.g. 120"), text: $timeoutSeconds)
                        .mcclawTextField()
                }
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Session"))
                        .font(.subheadline.weight(.medium))
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
                        .font(.subheadline.weight(.medium))
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                summaryRow(String(localized: "Task"), name.isEmpty ? String(localized: "Unnamed") : name)
                summaryRow(String(localized: "AI"), selectedProvider.isEmpty ? String(localized: "Default (active)") : selectedProvider)
                summaryRow(String(localized: "When"), whenSummaryText)
                summaryRow(String(localized: "Results"), deliverySummaryText)
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    private var whenSummaryText: String {
        switch whenChoice {
        case .once:
            return String(localized: "Once on \(atDate.formatted(date: .abbreviated, time: .shortened))")
        case .repeating:
            if repeatPreset == .scheduled {
                let unit = scheduledUnit.displayName.lowercased()
                if scheduledUnit.supportsTime {
                    let time = scheduledTime.formatted(date: .omitted, time: .shortened)
                    return String(localized: "Every \(scheduledAmount) \(unit) at \(time)")
                }
                return String(localized: "Every \(scheduledAmount) \(unit)")
            } else if repeatPreset == .custom {
                return String(localized: "Every \(customInterval)")
            } else {
                return repeatPreset.displayName
            }
        case .advanced:
            return cronExpr.isEmpty ? String(localized: "Not configured") : cronExpr
        }
    }

    private var deliverySummaryText: String {
        var parts: [String] = []
        if deliverNotifications { parts.append(String(localized: "Notifications")) }
        for dest in deliveryDestinations {
            if dest.recipient.isEmpty {
                parts.append(dest.channelName)
            } else {
                parts.append("\(dest.channelName) → \(dest.recipient)")
            }
        }
        if deliverSaveHistory { parts.append(String(localized: "History")) }
        if parts.isEmpty { return String(localized: "No notification") }
        return parts.joined(separator: ", ")
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
            if let parsed = parseScheduledCronExpr(expr) {
                whenChoice = .repeating
                repeatPreset = .scheduled
                scheduledAmount = parsed.amount
                scheduledUnit = parsed.unit
                if let h = parsed.hour, let m = parsed.minute {
                    let cal = Calendar.current
                    var comps = cal.dateComponents([.year, .month, .day], from: Date())
                    comps.hour = h
                    comps.minute = m
                    scheduledTime = cal.date(from: comps) ?? scheduledTime
                }
            } else {
                whenChoice = .advanced
                cronExpr = expr
                cronTz = tz ?? ""
            }
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
                    deliverNotifications = true
                } else if !ch.isEmpty {
                    let def = NativeChannelsManager.availableChannels.first { $0.id == ch }
                    deliveryDestinations.append(DeliveryDestination(
                        channelId: ch,
                        channelName: def?.name ?? ch.capitalized,
                        channelIcon: def?.icon ?? "paperplane",
                        recipient: delivery.to ?? ""
                    ))
                    bestEffortDeliver = delivery.bestEffort ?? true
                    deliverNotifications = false
                }
            case .none:
                deliverNotifications = false
            case .webhook:
                deliverNotifications = false
            }
        } else if sessionTarget == .main {
            deliverSaveHistory = true
            deliverNotifications = false
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
        if !deliveryDestinations.isEmpty { return .isolated }
        // Default: isolated (agentTurn) for most use cases
        return .isolated
    }

    private func buildSchedule() throws -> [String: Any] {
        switch whenChoice {
        case .once:
            return ["kind": "at", "at": CronSchedule.formatIsoDate(atDate)]
        case .repeating:
            if repeatPreset == .scheduled {
                let expr = buildScheduledCronExpr()
                return ["kind": "cron", "expr": expr]
            }
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

    /// Build a cron expression from the scheduled interval settings.
    private func buildScheduledCronExpr() -> String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: scheduledTime)
        let minute = cal.component(.minute, from: scheduledTime)
        let n = scheduledAmount

        switch scheduledUnit {
        case .minutes:
            // */N * * * *
            return "*/\(n) * * * *"
        case .hours:
            // 0 */N * * *
            return "0 */\(n) * * *"
        case .days:
            // M H */N * *
            if n == 1 {
                return "\(minute) \(hour) * * *"
            }
            return "\(minute) \(hour) */\(n) * *"
        case .weeks:
            // M H * * DOW (every N weeks approximated: */N*7 days)
            if n == 1 {
                return "\(minute) \(hour) * * 1"
            }
            // For N weeks, use day interval: N*7
            return "\(minute) \(hour) */\(n * 7) * *"
        case .months:
            // M H 1 */N *
            if n == 1 {
                return "\(minute) \(hour) 1 * *"
            }
            return "\(minute) \(hour) 1 */\(n) *"
        case .years:
            // M H 1 1 * (yearly) — cron doesn't support multi-year natively, use 12*N months
            if n == 1 {
                return "\(minute) \(hour) 1 1 *"
            }
            return "\(minute) \(hour) 1 */\(n * 12) *"
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
        // Build array of delivery targets
        var targets: [[String: Any]] = []

        if deliverNotifications {
            targets.append(["mode": "announce", "channel": "notifications", "bestEffort": true])
        }

        for dest in deliveryDestinations {
            var entry: [String: Any] = ["mode": "announce", "channel": dest.channelId]
            let toVal = dest.recipient.trimmingCharacters(in: .whitespacesAndNewlines)
            if !toVal.isEmpty { entry["to"] = toVal }
            entry["bestEffort"] = bestEffortDeliver
            targets.append(entry)
        }

        // If only one target, return it directly (backwards compatible)
        if targets.count == 1 {
            return targets[0]
        }

        // Multiple targets: wrap in array
        if !targets.isEmpty {
            return ["mode": "multi", "targets": targets]
        }

        // No delivery selected
        return ["mode": "none"]
    }

    /// Try to parse a cron expression back into scheduled interval components.
    private func parseScheduledCronExpr(_ expr: String) -> (amount: Int, unit: ScheduleUnit, hour: Int?, minute: Int?)? {
        let parts = expr.split(separator: " ").map(String.init)
        guard parts.count == 5 else { return nil }

        // */N * * * * → every N minutes
        if parts[0].hasPrefix("*/"), parts[1] == "*", parts[2] == "*", parts[3] == "*", parts[4] == "*",
           let n = Int(parts[0].dropFirst(2)), n > 0 {
            return (n, .minutes, nil, nil)
        }
        // 0 */N * * * → every N hours
        if parts[0] == "0", parts[1].hasPrefix("*/"), parts[2] == "*", parts[3] == "*", parts[4] == "*",
           let n = Int(parts[1].dropFirst(2)), n > 0 {
            return (n, .hours, nil, nil)
        }

        // Patterns with minute and hour
        guard let minute = Int(parts[0]), let hour = Int(parts[1]) else { return nil }

        // M H * * * → every 1 day
        if parts[2] == "*", parts[3] == "*", parts[4] == "*" {
            return (1, .days, hour, minute)
        }
        // M H */N * * → every N days (or N weeks if divisible by 7)
        if parts[2].hasPrefix("*/"), parts[3] == "*", parts[4] == "*",
           let n = Int(parts[2].dropFirst(2)), n > 0 {
            if n % 7 == 0 {
                return (n / 7, .weeks, hour, minute)
            }
            return (n, .days, hour, minute)
        }
        // M H * * 1 → every 1 week (Monday)
        if parts[2] == "*", parts[3] == "*", parts[4] == "1" {
            return (1, .weeks, hour, minute)
        }
        // M H 1 * * → every 1 month
        if parts[2] == "1", parts[3] == "*", parts[4] == "*" {
            return (1, .months, hour, minute)
        }
        // M H 1 */N * → every N months
        if parts[2] == "1", parts[3].hasPrefix("*/"), parts[4] == "*",
           let n = Int(parts[3].dropFirst(2)), n > 0 {
            if n % 12 == 0 {
                return (n / 12, .years, hour, minute)
            }
            return (n, .months, hour, minute)
        }
        // M H 1 1 * → every 1 year
        if parts[2] == "1", parts[3] == "1", parts[4] == "*" {
            return (1, .years, hour, minute)
        }

        return nil
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
