import Testing
@testable import McClawKit

@Suite("LearningKit Tests")
struct LearningKitTests {

    // MARK: - Turn Classification

    @Test("Main-line turn: valid assistant response")
    func mainLineTurnValid() {
        #expect(LearningKit.isMainLineTurn(
            role: "assistant",
            content: "Here is a detailed answer to your question about Swift concurrency...",
            hasToolPhase: false
        ))
    }

    @Test("Main-line turn: rejects tool phase")
    func mainLineTurnRejectsToolPhase() {
        #expect(!LearningKit.isMainLineTurn(
            role: "assistant",
            content: "Running tool...",
            hasToolPhase: true
        ))
    }

    @Test("Main-line turn: rejects system messages")
    func mainLineTurnRejectsSystem() {
        #expect(!LearningKit.isMainLineTurn(
            role: "system",
            content: "This is a system message with enough length to pass the filter.",
            hasToolPhase: false
        ))
    }

    @Test("Main-line turn: rejects short content")
    func mainLineTurnRejectsShort() {
        #expect(!LearningKit.isMainLineTurn(
            role: "assistant",
            content: "OK",
            hasToolPhase: false
        ))
    }

    @Test("Main-line turn: rejects tool role")
    func mainLineTurnRejectsTool() {
        #expect(!LearningKit.isMainLineTurn(
            role: "tool",
            content: "Result of the tool execution was successful and returned data.",
            hasToolPhase: false
        ))
    }

    // MARK: - Evaluative Signals (English)

    @Test("Evaluative: detects explicit positive - thanks")
    func evaluativePositiveThanks() {
        let signals = LearningKit.detectEvaluativeSignals(
            response: "Here is your code...",
            reaction: "Thanks, that's exactly what I needed!",
            locale: "en"
        )
        #expect(signals.contains("explicitPositive"))
    }

    @Test("Evaluative: detects explicit positive - perfect")
    func evaluativePositivePerfect() {
        let signals = LearningKit.detectEvaluativeSignals(
            response: "The answer is 42.",
            reaction: "Perfect!",
            locale: "en"
        )
        #expect(signals.contains("explicitPositive"))
    }

    @Test("Evaluative: detects explicit negative")
    func evaluativeNegative() {
        let signals = LearningKit.detectEvaluativeSignals(
            response: "Here is the solution...",
            reaction: "That's wrong, the function should return a string not an int.",
            locale: "en"
        )
        #expect(signals.contains("explicitNegative"))
    }

    @Test("Evaluative: detects correction")
    func evaluativeCorrection() {
        let signals = LearningKit.detectEvaluativeSignals(
            response: "Here is the French translation...",
            reaction: "No, I meant translate to Spanish not French.",
            locale: "en"
        )
        #expect(signals.contains("correction"))
    }

    @Test("Evaluative: continuation for neutral follow-up")
    func evaluativeContinuation() {
        let signals = LearningKit.detectEvaluativeSignals(
            response: "Swift actors provide data isolation...",
            reaction: "Can you show me an example of how to use them with async/await?",
            locale: "en"
        )
        #expect(signals.contains("continuation"))
        #expect(!signals.contains("explicitPositive"))
        #expect(!signals.contains("explicitNegative"))
    }

    // MARK: - Evaluative Signals (Spanish)

    @Test("Evaluative: detects positive in Spanish")
    func evaluativePositiveSpanish() {
        let signals = LearningKit.detectEvaluativeSignals(
            response: "Aquí tienes el código...",
            reaction: "Perfecto, gracias!",
            locale: "es"
        )
        #expect(signals.contains("explicitPositive"))
    }

    @Test("Evaluative: detects correction in Spanish")
    func evaluativeCorrectionSpanish() {
        let signals = LearningKit.detectEvaluativeSignals(
            response: "El resultado es...",
            reaction: "No, quise decir otra cosa.",
            locale: "es"
        )
        #expect(signals.contains("correction"))
    }

    // MARK: - Directive Extraction

    @Test("Directive: format preference - shorter")
    func directiveFormatShorter() {
        let directives = LearningKit.extractDirectives(from: "Can you make it shorter? I don't need all the details.")
        #expect(directives.contains { $0.category == "formatPreference" && $0.detail == "response_length:concise" })
    }

    @Test("Directive: format preference - more detail")
    func directiveFormatMoreDetail() {
        let directives = LearningKit.extractDirectives(from: "I need more detail on this topic.")
        #expect(directives.contains { $0.category == "formatPreference" && $0.detail == "response_length:detailed" })
    }

    @Test("Directive: style preference - formal")
    func directiveStyleFormal() {
        let directives = LearningKit.extractDirectives(from: "Please be more formal in your responses.")
        #expect(directives.contains { $0.category == "stylePreference" && $0.detail == "tone:formal" })
    }

    @Test("Directive: behavior preference - ask before executing")
    func directiveBehaviorAskBefore() {
        let directives = LearningKit.extractDirectives(from: "Always ask before running any commands.")
        #expect(directives.contains { $0.category == "behaviorPreference" && $0.detail == "ask_before_executing:true" })
    }

    @Test("Directive: language preference - Spanish")
    func directiveLanguageSpanish() {
        let directives = LearningKit.extractDirectives(from: "Responde en español por favor.")
        #expect(directives.contains { $0.category == "languagePreference" && $0.detail == "language:es" })
    }

    @Test("Directive: no directives in normal message")
    func directiveNone() {
        let directives = LearningKit.extractDirectives(from: "How do I implement a binary search tree?")
        #expect(directives.isEmpty)
    }

    @Test("Directive: multiple directives")
    func directiveMultiple() {
        let directives = LearningKit.extractDirectives(from: "Be more formal and give me a summary with code first.")
        #expect(directives.count >= 2)
        #expect(directives.contains { $0.category == "stylePreference" })
        #expect(directives.contains { $0.category == "formatPreference" })
    }

    // MARK: - Task Category Detection

    @Test("Task category: coding")
    func taskCategoryCoding() {
        #expect(LearningKit.detectTaskCategory(from: "Help me implement a function to sort an array") == "coding")
    }

    @Test("Task category: writing")
    func taskCategoryWriting() {
        #expect(LearningKit.detectTaskCategory(from: "Draft an email to my team about the deadline") == "writing")
    }

    @Test("Task category: analysis")
    func taskCategoryAnalysis() {
        #expect(LearningKit.detectTaskCategory(from: "Analyze the performance of this algorithm") == "analysis")
    }

    @Test("Task category: math")
    func taskCategoryMath() {
        #expect(LearningKit.detectTaskCategory(from: "Calculate the probability of getting two heads") == "math")
    }

    @Test("Task category: creative")
    func taskCategoryCreative() {
        #expect(LearningKit.detectTaskCategory(from: "Tell me a short story about a robot") == "creative")
    }

    @Test("Task category: conversation (default)")
    func taskCategoryConversation() {
        #expect(LearningKit.detectTaskCategory(from: "Hello, how are you today?") == "conversation")
    }

    // MARK: - Confidence Decay

    @Test("Confidence decay: no decay at zero days")
    func confidenceDecayZero() {
        let factor = LearningKit.confidenceDecayFactor(daysSinceUpdate: 0)
        #expect(factor == 1.0)
    }

    @Test("Confidence decay: 50% at 25 days")
    func confidenceDecay25Days() {
        let factor = LearningKit.confidenceDecayFactor(daysSinceUpdate: 25)
        #expect(factor == 0.5)
    }

    @Test("Confidence decay: zero at 50+ days")
    func confidenceDecay50Days() {
        let factor = LearningKit.confidenceDecayFactor(daysSinceUpdate: 50)
        #expect(factor == 0.0)
    }

    @Test("Confidence decay: custom rate")
    func confidenceDecayCustomRate() {
        let factor = LearningKit.confidenceDecayFactor(daysSinceUpdate: 10, decayRate: 0.05)
        #expect(factor == 0.5)
    }

    // MARK: - Localized Patterns

    @Test("Positive patterns: all locales have entries")
    func positivePatternsCoverage() {
        for locale in ["en", "es", "fr", "de", "pt"] {
            let patterns = LearningKit.positivePatterns(for: locale)
            #expect(!patterns.isEmpty, "Locale \(locale) should have positive patterns")
        }
    }

    @Test("Negative patterns: all locales have entries")
    func negativePatternsCoverage() {
        for locale in ["en", "es", "fr", "de", "pt"] {
            let patterns = LearningKit.negativePatterns(for: locale)
            #expect(!patterns.isEmpty, "Locale \(locale) should have negative patterns")
        }
    }

    @Test("Correction patterns: all locales have entries")
    func correctionPatternsCoverage() {
        for locale in ["en", "es", "fr", "de", "pt"] {
            let patterns = LearningKit.correctionPatterns(for: locale)
            #expect(!patterns.isEmpty, "Locale \(locale) should have correction patterns")
        }
    }
}
