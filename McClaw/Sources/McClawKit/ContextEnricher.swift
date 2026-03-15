import Foundation

/// Pure logic for generating preference context blocks to inject into CLI prompts.
/// Stateless struct with no side effects — all data comes from the caller.
public struct ContextEnricher: Sendable {

    /// Minimum confidence threshold for a preference to be included in enrichment.
    public static let defaultThreshold: Double = 0.5

    /// Maximum number of format preferences to include.
    public static let maxFormatPreferences = 5

    /// Maximum number of style preferences to include.
    public static let maxStylePreferences = 3

    /// Maximum number of behavior preferences to include.
    public static let maxBehaviorPreferences = 3

    public init() {}

    /// Generate a preference enrichment block to prepend to the system prompt.
    /// Returns nil if no preferences meet the confidence threshold.
    public func enrichmentBlock(
        formatPreferences: [(key: String, value: String, confidence: Double)],
        stylePreferences: [(key: String, value: String, confidence: Double)],
        behaviors: [(key: String, value: String, confidence: Double)],
        threshold: Double = ContextEnricher.defaultThreshold
    ) -> String? {
        let relevantFormats = formatPreferences
            .filter { $0.confidence >= threshold }
            .sorted { $0.confidence > $1.confidence }
            .prefix(Self.maxFormatPreferences)

        let relevantStyles = stylePreferences
            .filter { $0.confidence >= threshold }
            .sorted { $0.confidence > $1.confidence }
            .prefix(Self.maxStylePreferences)

        let relevantBehaviors = behaviors
            .filter { $0.confidence >= threshold }
            .sorted { $0.confidence > $1.confidence }
            .prefix(Self.maxBehaviorPreferences)

        if relevantFormats.isEmpty && relevantStyles.isEmpty && relevantBehaviors.isEmpty {
            return nil
        }

        var lines: [String] = ["[User Preferences]"]

        for pref in relevantFormats {
            lines.append("- \(pref.key): \(pref.value)")
        }
        for pref in relevantStyles {
            lines.append("- \(pref.key): \(pref.value)")
        }
        for pref in relevantBehaviors {
            lines.append("- \(pref.key): \(pref.value)")
        }

        return lines.joined(separator: "\n")
    }
}
