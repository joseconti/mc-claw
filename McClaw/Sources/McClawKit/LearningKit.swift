import Foundation

/// Pure learning logic extracted for testability.
/// Used by SignalDetector and PreferenceEngine in the main app target.
public enum LearningKit {

    // MARK: - Turn Classification

    /// Determine if a turn is a main-line turn (suitable for learning).
    /// Excludes tool-phase, system, and very short messages.
    public static func isMainLineTurn(
        role: String,
        content: String,
        hasToolPhase: Bool
    ) -> Bool {
        if hasToolPhase { return false }
        if role == "system" || role == "tool" { return false }
        if content.count < 20 { return false }
        return true
    }

    // MARK: - Evaluative Signal Detection

    /// Detect evaluative signals from the user's reaction to an agent response.
    /// Returns all detected signals (may be empty if reaction is a neutral continuation).
    public static func detectEvaluativeSignals(
        response: String,
        reaction: String,
        locale: String = "en"
    ) -> [String] {
        let lower = reaction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var signals: [String] = []

        // Explicit positive
        let positivePatterns = Self.positivePatterns(for: locale)
        for pattern in positivePatterns {
            if lower.contains(pattern) {
                signals.append("explicitPositive")
                break
            }
        }

        // Explicit negative
        let negativePatterns = Self.negativePatterns(for: locale)
        for pattern in negativePatterns {
            if lower.contains(pattern) {
                signals.append("explicitNegative")
                break
            }
        }

        // Correction
        let correctionPatterns = Self.correctionPatterns(for: locale)
        for pattern in correctionPatterns {
            if lower.hasPrefix(pattern) || lower.contains(", \(pattern)") {
                signals.append("correction")
                break
            }
        }

        // If no specific signal detected, it's a continuation
        if signals.isEmpty {
            signals.append("continuation")
        }

        return signals
    }

    // MARK: - Directive Extraction

    /// Extract directive signals from a user's reaction message.
    /// Detects preferences about format, style, behavior, and language.
    public static func extractDirectives(from reaction: String) -> [(category: String, detail: String)] {
        let lower = reaction.lowercased()
        var directives: [(category: String, detail: String)] = []

        // Format preferences
        let formatKeywords: [(keyword: String, detail: String)] = [
            ("shorter", "response_length:concise"),
            ("more concise", "response_length:concise"),
            ("longer", "response_length:detailed"),
            ("more detail", "response_length:detailed"),
            ("bullet points", "use_bullets:always"),
            ("no bullets", "use_bullets:never"),
            ("code first", "code_position:first"),
            ("step by step", "explanation_style:step_by_step"),
            ("summary", "response_length:summary"),
        ]
        for (keyword, detail) in formatKeywords {
            if lower.contains(keyword) {
                directives.append((category: "formatPreference", detail: detail))
            }
        }

        // Style preferences
        let styleKeywords: [(keyword: String, detail: String)] = [
            ("more formal", "tone:formal"),
            ("less formal", "tone:casual"),
            ("be more formal", "tone:formal"),
            ("more casual", "tone:casual"),
            ("less verbose", "verbosity:low"),
            ("more verbose", "verbosity:high"),
            ("simpler words", "vocabulary:simple"),
            ("technical", "vocabulary:technical"),
        ]
        for (keyword, detail) in styleKeywords {
            if lower.contains(keyword) {
                directives.append((category: "stylePreference", detail: detail))
            }
        }

        // Behavior preferences
        let behaviorKeywords: [(keyword: String, detail: String)] = [
            ("ask before", "ask_before_executing:true"),
            ("don't ask", "ask_before_executing:false"),
            ("show reasoning", "show_reasoning:true"),
            ("show your work", "show_reasoning:true"),
            ("just the answer", "show_reasoning:false"),
            ("always show code", "show_code:always"),
        ]
        for (keyword, detail) in behaviorKeywords {
            if lower.contains(keyword) {
                directives.append((category: "behaviorPreference", detail: detail))
            }
        }

        // Language preferences
        let languageKeywords: [(keyword: String, detail: String)] = [
            ("respond in spanish", "language:es"),
            ("respond in english", "language:en"),
            ("respond in french", "language:fr"),
            ("responde en español", "language:es"),
            ("en español", "language:es"),
            ("en français", "language:fr"),
            ("in english", "language:en"),
        ]
        for (keyword, detail) in languageKeywords {
            if lower.contains(keyword) {
                directives.append((category: "languagePreference", detail: detail))
            }
        }

        return directives
    }

    // MARK: - Task Category Detection

    /// Classify a user query into a task category using keyword matching.
    public static func detectTaskCategory(from query: String) -> String {
        let lower = query.lowercased()

        let codingKeywords = ["code", "function", "bug", "implement", "compile", "debug", "refactor", "class", "method", "api", "endpoint", "test", "swift", "python", "javascript"]
        for keyword in codingKeywords {
            if lower.contains(keyword) { return "coding" }
        }

        let writingKeywords = ["write", "draft", "email", "document", "essay", "article", "blog", "letter", "report"]
        for keyword in writingKeywords {
            if lower.contains(keyword) { return "writing" }
        }

        let analysisKeywords = ["analyze", "compare", "explain", "why", "how does", "review", "evaluate", "assess"]
        for keyword in analysisKeywords {
            if lower.contains(keyword) { return "analysis" }
        }

        let mathKeywords = ["calculate", "math", "equation", "formula", "solve", "probability", "statistics"]
        for keyword in mathKeywords {
            if lower.contains(keyword) { return "math" }
        }

        let creativeKeywords = ["story", "poem", "creative", "imagine", "fiction", "brainstorm", "idea"]
        for keyword in creativeKeywords {
            if lower.contains(keyword) { return "creative" }
        }

        return "conversation"
    }

    // MARK: - Confidence Decay

    /// Calculate the decay factor for preference confidence.
    /// Returns a multiplier between 0.0 and 1.0 based on days since last update.
    public static func confidenceDecayFactor(
        daysSinceUpdate: Double,
        decayRate: Double = 0.02
    ) -> Double {
        max(0.0, 1.0 - (decayRate * daysSinceUpdate))
    }

    // MARK: - Localized Patterns

    public static func positivePatterns(for locale: String) -> [String] {
        switch locale {
        case "es":
            return ["gracias", "perfecto", "genial", "excelente", "bien hecho", "exacto", "correcto"]
        case "fr":
            return ["merci", "parfait", "génial", "excellent", "bien fait", "exact", "correct"]
        case "de":
            return ["danke", "perfekt", "genial", "ausgezeichnet", "gut gemacht", "genau", "richtig"]
        case "pt":
            return ["obrigado", "perfeito", "genial", "excelente", "bem feito", "exato", "correto"]
        default: // en
            return ["thanks", "thank you", "perfect", "great", "excellent", "well done", "exactly", "correct", "awesome", "nice"]
        }
    }

    public static func negativePatterns(for locale: String) -> [String] {
        switch locale {
        case "es":
            return ["no es útil", "incorrecto", "mal", "eso no", "no sirve", "está mal"]
        case "fr":
            return ["pas utile", "incorrect", "mauvais", "c'est faux", "ça ne marche pas"]
        case "de":
            return ["nicht hilfreich", "falsch", "schlecht", "das stimmt nicht", "funktioniert nicht"]
        case "pt":
            return ["não ajudou", "incorreto", "errado", "isso não", "não funciona"]
        default: // en
            return ["not helpful", "wrong", "incorrect", "bad response", "that's not right", "useless", "doesn't work", "that's wrong"]
        }
    }

    public static func correctionPatterns(for locale: String) -> [String] {
        switch locale {
        case "es":
            return ["no,", "quise decir", "en realidad", "eso está mal", "no es lo que pedí"]
        case "fr":
            return ["non,", "je voulais dire", "en fait", "c'est faux", "ce n'est pas ce que"]
        case "de":
            return ["nein,", "ich meinte", "eigentlich", "das ist falsch", "das war nicht"]
        case "pt":
            return ["não,", "eu quis dizer", "na verdade", "isso está errado", "não foi o que"]
        default: // en
            return ["no,", "i meant", "actually", "that's wrong", "not what i asked", "i said"]
        }
    }
}
