import SwiftUI

/// Settings tab for the Adaptive Learning system.
/// Shows toggles, statistics, provider performance, and data management controls.
struct LearningSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var totalEvents: Int = 0
    @State private var profile: UserPreferenceProfile = .empty()
    @State private var isLoading = true
    @State private var showResetConfirmation = false
    @State private var exportURL: URL?
    @State private var showExportSuccess = false

    var body: some View {
        @Bindable var state = appState
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Toggles
                sectionHeader(String(localized: "settings.learning.title"))

                Toggle(isOn: $state.adaptiveLearningEnabled) {
                    VStack(alignment: .leading) {
                        Text(String(localized: "settings.learning.enable"))
                        Text(String(localized: "settings.learning.enable.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(.bottom, 8)
                .onChange(of: appState.adaptiveLearningEnabled) {
                    Task { await ConfigStore.shared.saveFromState() }
                }

                Toggle(isOn: $state.showLearningIndicators) {
                    VStack(alignment: .leading) {
                        Text(String(localized: "settings.learning.indicators"))
                        Text(String(localized: "settings.learning.indicators.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(.bottom, 16)
                .disabled(!appState.adaptiveLearningEnabled)
                .onChange(of: appState.showLearningIndicators) {
                    Task { await ConfigStore.shared.saveFromState() }
                }

                Divider().padding(.bottom, 16)

                // MARK: - Statistics
                sectionHeader(String(localized: "settings.learning.statistics"))

                HStack(spacing: 24) {
                    statCard(
                        title: String(localized: "settings.learning.preferences"),
                        value: "\(profile.formatPreferences.count + profile.stylePreferences.count + profile.behaviors.count)"
                    )
                    statCard(
                        title: String(localized: "settings.learning.interactions"),
                        value: "\(profile.totalInteractions)"
                    )
                    statCard(
                        title: String(localized: "settings.learning.satisfaction"),
                        value: "\(Int(profile.satisfactionRate * 100))%"
                    )
                }
                .padding(.bottom, 16)

                Divider().padding(.bottom, 16)

                // MARK: - Provider Performance
                if !profile.providerStats.isEmpty {
                    sectionHeader(String(localized: "settings.learning.provider.performance"))

                    ForEach(
                        profile.providerStats.sorted(by: { $0.value.satisfactionRate > $1.value.satisfactionRate }),
                        id: \.key
                    ) { provider, stat in
                        providerRow(provider: provider, stat: stat)
                    }
                    .padding(.bottom, 16)

                    Divider().padding(.bottom, 16)
                }

                // MARK: - Learned Preferences
                if !profile.formatPreferences.isEmpty || !profile.stylePreferences.isEmpty || !profile.behaviors.isEmpty {
                    sectionHeader(String(localized: "settings.learning.learned.preferences"))

                    ForEach(allPreferences(), id: \.key) { pref in
                        HStack {
                            Text(pref.key)
                                .font(.body.monospaced())
                            Spacer()
                            Text(pref.value)
                                .foregroundStyle(.secondary)
                            confidenceBadge(pref.confidence)
                        }
                        .padding(.vertical, 2)
                    }
                    .padding(.bottom, 16)

                    Divider().padding(.bottom, 16)
                }

                // MARK: - Data Management
                sectionHeader(String(localized: "settings.learning.data"))

                Text(String(localized: "settings.learning.data.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                HStack(spacing: 12) {
                    Button(String(localized: "settings.learning.export")) {
                        exportProfile()
                    }
                    .disabled(profile.totalInteractions == 0)

                    Button(String(localized: "settings.learning.reset"), role: .destructive) {
                        showResetConfirmation = true
                    }
                    .disabled(profile.totalInteractions == 0)
                }
                .padding(.bottom, 8)

                Text(String(localized: "settings.learning.events.count \(totalEvents)"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(20)
        }
        .task { await loadData() }
        .alert(
            String(localized: "settings.learning.reset.title"),
            isPresented: $showResetConfirmation
        ) {
            Button(String(localized: "settings.learning.reset.cancel"), role: .cancel) {}
            Button(String(localized: "settings.learning.reset.confirm"), role: .destructive) {
                Task { await resetLearning() }
            }
        } message: {
            Text(String(localized: "settings.learning.reset.message"))
        }
        .alert(
            String(localized: "settings.learning.export.success"),
            isPresented: $showExportSuccess
        ) {
            Button("OK") {}
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        let loadedProfile = await PreferenceEngine.shared.currentProfile()
        let count = await FeedbackStore.shared.eventCount()
        profile = loadedProfile
        totalEvents = count
        isLoading = false
    }

    private func resetLearning() async {
        try? await PreferenceEngine.shared.resetAll()
        profile = .empty()
        totalEvents = 0
    }

    private func exportProfile() {
        Task {
            guard let data = try? await PreferenceEngine.shared.exportProfile() else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "mcclaw-preferences.json"
            if panel.runModal() == .OK, let url = panel.url {
                try? data.write(to: url)
                showExportSuccess = true
            }
        }
    }

    // MARK: - Helpers

    private func allPreferences() -> [(key: String, value: String, confidence: Double)] {
        let formats = profile.formatPreferences.map { (key: $0.key, value: $0.value, confidence: $0.confidence) }
        let styles = profile.stylePreferences.map { (key: $0.key, value: $0.value, confidence: $0.confidence) }
        let behaviors = profile.behaviors.map { (key: $0.key, value: $0.value, confidence: $0.confidence) }
        return (formats + styles + behaviors).sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.bottom, 8)
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func providerRow(provider: String, stat: ProviderStat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(provider.capitalized)
                    .font(.body.bold())
                Spacer()
                Text("\(Int(stat.satisfactionRate * 100))%")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: stat.satisfactionRate)
                .tint(stat.satisfactionRate >= 0.7 ? .green : stat.satisfactionRate >= 0.4 ? .orange : .red)
            if !stat.bestFor.isEmpty {
                Text(String(localized: "settings.learning.best.for \(stat.bestFor.joined(separator: ", "))"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 8)
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                confidence >= 0.7 ? Color.green.opacity(0.2) :
                confidence >= 0.4 ? Color.orange.opacity(0.2) :
                Color.red.opacity(0.2),
                in: Capsule()
            )
    }
}
