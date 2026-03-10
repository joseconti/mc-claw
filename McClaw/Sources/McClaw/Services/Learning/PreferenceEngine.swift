import Foundation
import Logging
import McClawKit

/// Aggregates raw feedback events into a structured preference profile.
/// Runs as an actor since profile updates come from background work.
actor PreferenceEngine {
    static let shared = PreferenceEngine()

    private let logger = Logger(label: "ai.mcclaw.learning.preference")

    private let learningDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/learning", isDirectory: true)
    }()

    private var profileURL: URL {
        learningDirectory.appending(component: "profile.json")
    }

    private(set) var profile: UserPreferenceProfile

    /// Number of interactions between profile updates.
    private var interactionsSinceUpdate = 0

    /// Update profile every N interactions.
    private static let updateInterval = 10

    private init() {
        profile = .empty()
        if let loaded = Self.loadProfileSync() {
            profile = loaded
        }
    }

    // MARK: - Profile Access

    /// Get a copy of the current profile (safe to read from any context).
    func currentProfile() -> UserPreferenceProfile {
        profile
    }

    // MARK: - Record & Update

    /// Process a feedback event and update the profile if the interval is reached.
    func processFeedback(_ event: FeedbackEvent) {
        for signal in event.signals {
            switch signal {
            case .evaluative(let eval):
                applyEvaluative(eval, provider: event.provider)
            case .directive(let dir):
                applyDirective(dir)
            }
        }
        profile.totalInteractions += 1
        interactionsSinceUpdate += 1

        if interactionsSinceUpdate >= Self.updateInterval {
            recalculateSatisfaction()
            decayConfidence()
            try? save()
            interactionsSinceUpdate = 0
        }
    }

    /// Force a profile save (e.g., on app background).
    func forceSave() {
        recalculateSatisfaction()
        try? save()
    }

    // MARK: - Enrichment Block

    /// Generate the context enrichment block for CLI prompt injection.
    func enrichmentBlock(provider: String) -> String? {
        let enricher = ContextEnricher()
        return enricher.enrichmentBlock(
            formatPreferences: profile.formatPreferences.map {
                (key: $0.key, value: $0.value, confidence: $0.confidence)
            },
            stylePreferences: profile.stylePreferences.map {
                (key: $0.key, value: $0.value, confidence: $0.confidence)
            },
            behaviors: profile.behaviors.map {
                (key: $0.key, value: $0.value, confidence: $0.confidence)
            }
        )
    }

    // MARK: - Provider Intelligence

    /// Suggest the best provider for a given task category.
    func suggestProvider(for taskCategory: String) -> String? {
        let candidates = profile.providerStats.values
            .filter { $0.bestFor.contains(taskCategory) }
            .sorted { $0.satisfactionRate > $1.satisfactionRate }
        return candidates.first?.provider
    }

    // MARK: - Reset

    /// Delete all learning data and reset the profile.
    func resetAll() async throws {
        profile = .empty()
        interactionsSinceUpdate = 0
        let fm = FileManager.default
        if fm.fileExists(atPath: learningDirectory.path) {
            try fm.removeItem(at: learningDirectory)
        }
        try fm.createDirectory(at: learningDirectory, withIntermediateDirectories: true)
        try await FeedbackStore.shared.deleteAll()
        logger.info("All learning data reset")
    }

    // MARK: - Export

    /// Export the preference profile as JSON data.
    func exportProfile() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profile)
    }

    // MARK: - Private: Apply Signals

    private func applyEvaluative(_ signal: EvaluativeSignal, provider: String) {
        var stat = profile.providerStats[provider] ?? ProviderStat(
            provider: provider,
            totalTurns: 0,
            positiveSignals: 0,
            negativeSignals: 0,
            bestFor: []
        )
        stat.totalTurns += 1
        if signal.score > 0 {
            stat.positiveSignals += 1
        } else if signal.score < 0 {
            stat.negativeSignals += 1
        }
        profile.providerStats[provider] = stat
    }

    private func applyDirective(_ directive: DirectiveSignal) {
        let parts = directive.detail.split(separator: ":", maxSplits: 1)
        let key = parts.first.map(String.init) ?? directive.detail
        let value = parts.count > 1 ? String(parts[1]) : directive.detail

        switch directive.category {
        case .formatPreference:
            upsertPreference(in: &profile.formatPreferences, key: key, value: value)
        case .stylePreference:
            upsertPreference(in: &profile.stylePreferences, key: key, value: value)
        case .behaviorPreference:
            upsertBehavior(key: key, value: value)
        case .languagePreference:
            upsertPreference(in: &profile.languagePreferences, key: key, value: value)
        case .contentCorrection, .providerHint:
            // These don't persist as preferences
            break
        }
    }

    private func upsertPreference(
        in list: inout [FormatPreference],
        key: String,
        value: String
    ) {
        if let idx = list.firstIndex(where: { $0.key == key }) {
            var pref = list[idx]
            pref.occurrences += 1
            pref.confidence = min(1.0, pref.confidence + 0.1)
            list[idx] = pref
        } else {
            list.append(FormatPreference(
                key: key,
                value: value,
                confidence: 0.3,
                occurrences: 1
            ))
        }
    }

    private func upsertBehavior(key: String, value: String) {
        if let idx = profile.behaviors.firstIndex(where: { $0.key == key }) {
            var behavior = profile.behaviors[idx]
            behavior.confidence = min(1.0, behavior.confidence + 0.1)
            profile.behaviors[idx] = behavior
        } else {
            profile.behaviors.append(BehaviorPreference(
                key: key,
                value: value,
                confidence: 0.3
            ))
        }
    }

    // MARK: - Private: Satisfaction

    private func recalculateSatisfaction() {
        let totalPositive = profile.providerStats.values.reduce(0) { $0 + $1.positiveSignals }
        let totalTurns = profile.providerStats.values.reduce(0) { $0 + $1.totalTurns }
        profile.satisfactionRate = totalTurns > 0
            ? Double(totalPositive) / Double(totalTurns)
            : 0.5
    }

    // MARK: - Private: Confidence Decay

    private func decayConfidence() {
        let daysSinceUpdate = Date().timeIntervalSince(profile.lastUpdated) / 86400
        let factor = LearningKit.confidenceDecayFactor(daysSinceUpdate: daysSinceUpdate)

        for i in profile.formatPreferences.indices {
            var pref = profile.formatPreferences[i]
            pref.confidence *= factor
            profile.formatPreferences[i] = pref
        }
        profile.formatPreferences.removeAll { $0.confidence < 0.1 }

        for i in profile.stylePreferences.indices {
            var pref = profile.stylePreferences[i]
            pref.confidence *= factor
            profile.stylePreferences[i] = pref
        }
        profile.stylePreferences.removeAll { $0.confidence < 0.1 }

        for i in profile.behaviors.indices {
            var behavior = profile.behaviors[i]
            behavior.confidence *= factor
            profile.behaviors[i] = behavior
        }
        profile.behaviors.removeAll { $0.confidence < 0.1 }

        profile.lastUpdated = Date()
    }

    // MARK: - Private: Persistence

    private func save() throws {
        try FileManager.default.createDirectory(
            at: learningDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(to: profileURL, options: .atomic)
        logger.debug("Profile saved (\(profile.totalInteractions) interactions)")
    }

    private static func loadProfileSync() -> UserPreferenceProfile? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/learning/profile.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UserPreferenceProfile.self, from: data)
    }
}
