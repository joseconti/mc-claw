import Foundation
import Logging
import McClawKit

/// Monitors conversation flow and detects evaluative/directive signals in real time.
/// Runs on MainActor since it reads from ChatViewModel's messages array.
@MainActor
final class SignalDetector {
    static let shared = SignalDetector()

    private let logger = Logger(label: "ai.mcclaw.learning.signal")

    /// Locale for pattern matching (defaults to system locale prefix).
    var locale: String = {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang
    }()

    private init() {}

    // MARK: - Analysis

    /// Analyze the user's reaction to the previous agent response.
    /// Returns a FeedbackEvent if learning signals were detected, nil otherwise.
    func analyze(
        agentResponse: ChatMessage,
        userReaction: ChatMessage,
        sessionKey: String
    ) -> FeedbackEvent? {
        // Validate: must be assistant → user pair
        guard agentResponse.role == .assistant,
              userReaction.role == .user else {
            return nil
        }

        // Only analyze main-line turns
        guard LearningKit.isMainLineTurn(
            role: agentResponse.role.rawValue,
            content: agentResponse.content,
            hasToolPhase: !agentResponse.toolCalls.isEmpty
        ) else {
            return nil
        }

        var signals: [FeedbackSignal] = []

        // Detect evaluative signals
        let evalSignalNames = LearningKit.detectEvaluativeSignals(
            response: agentResponse.content,
            reaction: userReaction.content,
            locale: locale
        )
        for name in evalSignalNames {
            if let signal = mapEvaluativeSignal(name) {
                signals.append(.evaluative(signal))
            }
        }

        // Detect directive signals
        let directives = LearningKit.extractDirectives(from: userReaction.content)
        for directive in directives {
            if let category = DirectiveCategory(rawValue: directive.category) {
                signals.append(.directive(DirectiveSignal(
                    category: category,
                    detail: directive.detail
                )))
            }
        }

        guard !signals.isEmpty else { return nil }

        let event = FeedbackEvent(
            id: UUID(),
            timestamp: Date(),
            sessionKey: sessionKey,
            provider: agentResponse.providerId ?? "unknown",
            model: nil,
            signals: signals,
            responseExcerpt: String(agentResponse.content.prefix(500)),
            reactionExcerpt: String(userReaction.content.prefix(500))
        )

        logger.debug("Detected \(signals.count) signals in session \(sessionKey)")
        return event
    }

    // MARK: - Provider Switch Detection

    /// Detect if the user switched providers between two consecutive messages.
    func detectProviderSwitch(
        previousProvider: String?,
        currentProvider: String?
    ) -> EvaluativeSignal? {
        guard let prev = previousProvider,
              let curr = currentProvider,
              prev != curr else {
            return nil
        }
        return .providerSwitch(from: prev, to: curr)
    }

    // MARK: - Abandonment Detection

    /// Check if the user abandoned the conversation (new session within threshold of last response).
    func detectAbandonment(
        lastResponseTime: Date,
        newSessionTime: Date,
        threshold: TimeInterval = 30
    ) -> Bool {
        newSessionTime.timeIntervalSince(lastResponseTime) <= threshold
    }

    // MARK: - Private Helpers

    private func mapEvaluativeSignal(_ name: String) -> EvaluativeSignal? {
        switch name {
        case "explicitPositive": return .explicitPositive
        case "explicitNegative": return .explicitNegative
        case "correction": return .correction
        case "continuation": return .continuation
        case "reQuery": return .reQuery
        case "abandonment": return .abandonment
        case "copyAction": return .copyAction
        default: return nil
        }
    }
}
