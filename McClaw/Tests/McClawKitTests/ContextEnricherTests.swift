import Testing
@testable import McClawKit

@Suite("ContextEnricher Tests")
struct ContextEnricherTests {

    let enricher = ContextEnricher()

    // MARK: - Enrichment Block Generation

    @Test("Returns nil when no preferences meet threshold")
    func emptyPreferences() {
        let result = enricher.enrichmentBlock(
            formatPreferences: [],
            stylePreferences: [],
            behaviors: []
        )
        #expect(result == nil)
    }

    @Test("Returns nil when all preferences below threshold")
    func belowThreshold() {
        let result = enricher.enrichmentBlock(
            formatPreferences: [
                (key: "response_length", value: "concise", confidence: 0.2),
                (key: "use_bullets", value: "always", confidence: 0.3),
            ],
            stylePreferences: [],
            behaviors: []
        )
        #expect(result == nil)
    }

    @Test("Includes preferences above threshold")
    func aboveThreshold() {
        let result = enricher.enrichmentBlock(
            formatPreferences: [
                (key: "response_length", value: "concise", confidence: 0.8),
            ],
            stylePreferences: [],
            behaviors: []
        )
        #expect(result != nil)
        #expect(result!.contains("[User Preferences]"))
        #expect(result!.contains("- response_length: concise"))
    }

    @Test("Mixes format, style, and behavior preferences")
    func mixedPreferences() {
        let result = enricher.enrichmentBlock(
            formatPreferences: [
                (key: "response_length", value: "concise", confidence: 0.8),
            ],
            stylePreferences: [
                (key: "tone", value: "formal", confidence: 0.7),
            ],
            behaviors: [
                (key: "ask_before_executing", value: "true", confidence: 0.6),
            ]
        )
        #expect(result != nil)
        let lines = result!.split(separator: "\n")
        #expect(lines.count == 4) // header + 3 preferences
        #expect(lines[0] == "[User Preferences]")
        #expect(lines[1] == "- response_length: concise")
        #expect(lines[2] == "- tone: formal")
        #expect(lines[3] == "- ask_before_executing: true")
    }

    @Test("Respects max format preferences limit")
    func maxFormatLimit() {
        let formats = (1...10).map { i in
            (key: "pref\(i)", value: "val\(i)", confidence: Double(i) / 10.0)
        }
        let result = enricher.enrichmentBlock(
            formatPreferences: formats,
            stylePreferences: [],
            behaviors: []
        )
        #expect(result != nil)
        let lines = result!.split(separator: "\n").filter { $0.hasPrefix("- ") }
        #expect(lines.count <= ContextEnricher.maxFormatPreferences)
    }

    @Test("Sorts by confidence descending")
    func sortedByConfidence() {
        let result = enricher.enrichmentBlock(
            formatPreferences: [
                (key: "low", value: "a", confidence: 0.5),
                (key: "high", value: "b", confidence: 0.9),
                (key: "mid", value: "c", confidence: 0.7),
            ],
            stylePreferences: [],
            behaviors: []
        )
        #expect(result != nil)
        let lines = result!.split(separator: "\n").filter { $0.hasPrefix("- ") }
        #expect(lines[0] == "- high: b")
        #expect(lines[1] == "- mid: c")
        #expect(lines[2] == "- low: a")
    }

    @Test("Custom threshold")
    func customThreshold() {
        let result = enricher.enrichmentBlock(
            formatPreferences: [
                (key: "pref", value: "val", confidence: 0.6),
            ],
            stylePreferences: [],
            behaviors: [],
            threshold: 0.7
        )
        #expect(result == nil)
    }

    @Test("Default threshold is 0.5")
    func defaultThreshold() {
        #expect(ContextEnricher.defaultThreshold == 0.5)
    }
}
