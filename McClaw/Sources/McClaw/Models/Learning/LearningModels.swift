import Foundation

// MARK: - Evaluative Signals

/// Implicit quality signals detected from user behavior after an agent response.
enum EvaluativeSignal: Codable, Sendable {
    case reQuery
    case correction
    case abandonment
    case providerSwitch(from: String, to: String)
    case continuation
    case explicitPositive
    case explicitNegative
    case copyAction

    var score: Int {
        switch self {
        case .reQuery, .correction, .abandonment,
             .providerSwitch, .explicitNegative:
            return -1
        case .continuation, .explicitPositive, .copyAction:
            return +1
        }
    }
}

// MARK: - Directive Signals

/// Explicit correction direction extracted from user reactions.
struct DirectiveSignal: Codable, Sendable {
    let category: DirectiveCategory
    let detail: String
}

enum DirectiveCategory: String, Codable, Sendable {
    case formatPreference
    case contentCorrection
    case stylePreference
    case languagePreference
    case behaviorPreference
    case providerHint
}

// MARK: - Feedback Signal (Union)

enum FeedbackSignal: Codable, Sendable {
    case evaluative(EvaluativeSignal)
    case directive(DirectiveSignal)
}

// MARK: - Feedback Event

/// A single learning event recorded from a user-agent interaction pair.
struct FeedbackEvent: Codable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let sessionKey: String
    let provider: String
    let model: String?

    let signals: [FeedbackSignal]
    let responseExcerpt: String
    let reactionExcerpt: String
}

// MARK: - User Preference Profile

/// Aggregated preference profile built from accumulated feedback signals.
struct UserPreferenceProfile: Codable, Sendable {
    var lastUpdated: Date
    var totalInteractions: Int
    var satisfactionRate: Double

    var formatPreferences: [FormatPreference]
    var stylePreferences: [FormatPreference]
    var providerStats: [String: ProviderStat]
    var behaviors: [BehaviorPreference]
    var languagePreferences: [FormatPreference]

    static func empty() -> UserPreferenceProfile {
        UserPreferenceProfile(
            lastUpdated: Date(),
            totalInteractions: 0,
            satisfactionRate: 0.5,
            formatPreferences: [],
            stylePreferences: [],
            providerStats: [:],
            behaviors: [],
            languagePreferences: []
        )
    }
}

struct FormatPreference: Codable, Sendable {
    let key: String
    let value: String
    var confidence: Double
    var occurrences: Int
}

struct BehaviorPreference: Codable, Sendable {
    let key: String
    let value: String
    var confidence: Double
}

struct ProviderStat: Codable, Sendable {
    let provider: String
    var totalTurns: Int
    var positiveSignals: Int
    var negativeSignals: Int
    var bestFor: [String]

    var satisfactionRate: Double {
        guard totalTurns > 0 else { return 0.5 }
        return Double(positiveSignals) / Double(totalTurns)
    }
}

// MARK: - Task Category

enum TaskCategory: String, CaseIterable, Codable, Sendable {
    case coding
    case writing
    case analysis
    case conversation
    case math
    case creative
}
