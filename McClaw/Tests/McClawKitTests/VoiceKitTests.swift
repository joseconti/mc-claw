import Foundation
import Testing
@testable import McClawKit

@Suite("VoiceKit Tests")
struct VoiceKitTests {

    // MARK: - cleanForSpeech

    @Test("Removes code blocks from text")
    func cleanCodeBlocks() {
        let input = "Here is some code:\n```swift\nlet x = 1\n```\nDone."
        let result = VoiceKit.cleanForSpeech(input)
        #expect(result.contains("code block omitted"))
        #expect(!result.contains("```"))
        #expect(!result.contains("let x = 1"))
    }

    @Test("Removes inline code from text")
    func cleanInlineCode() {
        let input = "Use the `print()` function to output."
        let result = VoiceKit.cleanForSpeech(input)
        #expect(!result.contains("`"))
        #expect(result.contains("function"))
    }

    @Test("Removes markdown links, keeps text")
    func cleanMarkdownLinks() {
        let input = "Visit [Google](https://google.com) for more."
        let result = VoiceKit.cleanForSpeech(input)
        #expect(result.contains("Google"))
        #expect(!result.contains("https://"))
    }

    @Test("Removes markdown formatting characters")
    func cleanMarkdownFormatting() {
        let input = "This is **bold** and *italic* and ~~strikethrough~~."
        let result = VoiceKit.cleanForSpeech(input)
        #expect(!result.contains("**"))
        #expect(!result.contains("~~"))
        #expect(result.contains("bold"))
        #expect(result.contains("italic"))
    }

    @Test("Removes header markers")
    func cleanHeaders() {
        let input = "## Section Title\nSome content here."
        let result = VoiceKit.cleanForSpeech(input)
        #expect(!result.contains("##"))
        #expect(result.contains("Section Title"))
    }

    @Test("Removes bullet points")
    func cleanBulletPoints() {
        let input = "- First item\n- Second item\n* Third item"
        let result = VoiceKit.cleanForSpeech(input)
        #expect(!result.hasPrefix("-"))
        #expect(result.contains("First item"))
    }

    @Test("Collapses whitespace")
    func cleanWhitespace() {
        let input = "Hello   world\n\n\ntest"
        let result = VoiceKit.cleanForSpeech(input)
        #expect(!result.contains("  "))
    }

    @Test("Returns empty for empty input")
    func cleanEmpty() {
        #expect(VoiceKit.cleanForSpeech("") == "")
        #expect(VoiceKit.cleanForSpeech("   ") == "")
    }

    // MARK: - splitIntoSentences

    @Test("Splits text into sentences")
    func splitSentences() {
        let input = "Hello world. How are you? I am fine!"
        let sentences = VoiceKit.splitIntoSentences(input)
        #expect(sentences.count == 3)
    }

    @Test("Single sentence returns array with one element")
    func splitSingleSentence() {
        let input = "Hello world"
        let sentences = VoiceKit.splitIntoSentences(input)
        #expect(sentences.count == 1)
        #expect(sentences[0] == "Hello world")
    }

    @Test("Empty string returns empty array")
    func splitEmpty() {
        let sentences = VoiceKit.splitIntoSentences("")
        #expect(sentences.isEmpty)
    }

    // MARK: - matchWakeWord

    @Test("Matches wake word in transcript")
    func matchWakeWord() {
        let result = VoiceKit.matchWakeWord(
            transcript: "I said hey claw what is the weather",
            triggerWords: ["hey claw"]
        )
        #expect(result == "hey claw")
    }

    @Test("Case insensitive wake word matching")
    func matchWakeWordCaseInsensitive() {
        let result = VoiceKit.matchWakeWord(
            transcript: "HEY CLAW help me",
            triggerWords: ["hey claw"]
        )
        #expect(result == "hey claw")
    }

    @Test("No match returns nil")
    func matchWakeWordNoMatch() {
        let result = VoiceKit.matchWakeWord(
            transcript: "Hello world",
            triggerWords: ["hey claw"]
        )
        #expect(result == nil)
    }

    @Test("Multiple trigger words")
    func matchMultipleTriggers() {
        let result = VoiceKit.matchWakeWord(
            transcript: "ok mcclaw do something",
            triggerWords: ["hey claw", "ok mcclaw"]
        )
        #expect(result == "ok mcclaw")
    }

    // MARK: - normalizeAudioLevel

    @Test("Normalizes audio level within range")
    func normalizeLevel() {
        #expect(VoiceKit.normalizeAudioLevel(0.05) == 0.5)
        #expect(VoiceKit.normalizeAudioLevel(0.0) == 0.0)
        #expect(VoiceKit.normalizeAudioLevel(0.1) == 1.0)
    }

    @Test("Clamps audio level to 1.0 max")
    func normalizeLevelClamp() {
        #expect(VoiceKit.normalizeAudioLevel(0.5) == 1.0)
        #expect(VoiceKit.normalizeAudioLevel(1.0) == 1.0)
    }

    @Test("Custom gain factor")
    func normalizeLevelCustomGain() {
        #expect(VoiceKit.normalizeAudioLevel(0.1, gain: 5.0) == 0.5)
    }

    // MARK: - shouldAutoSend

    @Test("Auto-send when silence exceeds threshold")
    func autoSendYes() {
        let lastSpeech = Date().addingTimeInterval(-2.0)
        #expect(VoiceKit.shouldAutoSend(lastSpeechTime: lastSpeech, now: Date(), threshold: 1.5))
    }

    @Test("No auto-send when silence is below threshold")
    func autoSendNo() {
        let lastSpeech = Date().addingTimeInterval(-0.5)
        #expect(!VoiceKit.shouldAutoSend(lastSpeechTime: lastSpeech, now: Date(), threshold: 1.5))
    }

    @Test("Auto-send exactly at threshold")
    func autoSendExact() {
        let now = Date()
        let lastSpeech = now.addingTimeInterval(-1.5)
        #expect(VoiceKit.shouldAutoSend(lastSpeechTime: lastSpeech, now: now, threshold: 1.5))
    }

    // MARK: - VoiceConfig

    @Test("VoiceConfig default values")
    func voiceConfigDefaults() {
        let config = VoiceKit.VoiceConfig()
        #expect(!config.voiceModeEnabled)
        #expect(config.selectedVoice == nil)
        #expect(config.speechRate == 180)
        #expect(config.speechVolume == 1.0)
        #expect(config.silenceThreshold == 1.5)
        #expect(config.recognitionLocale == nil)
        #expect(!config.wakeWordEnabled)
        #expect(config.triggerWords == ["hey claw"])
        #expect(!config.pushToTalkEnabled)
        #expect(config.pushToTalkKeyCode == 0x3D)
    }

    @Test("VoiceConfig encodes and decodes")
    func voiceConfigCodable() throws {
        let config = VoiceKit.VoiceConfig(
            voiceModeEnabled: true,
            selectedVoice: "com.apple.voice.compact.en-US.Samantha",
            speechRate: 200,
            speechVolume: 0.8,
            silenceThreshold: 2.0,
            recognitionLocale: "en-US",
            wakeWordEnabled: true,
            triggerWords: ["hey mcclaw"],
            pushToTalkEnabled: true,
            pushToTalkKeyCode: 0x3A
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VoiceKit.VoiceConfig.self, from: data)

        #expect(decoded == config)
        #expect(decoded.voiceModeEnabled)
        #expect(decoded.selectedVoice == "com.apple.voice.compact.en-US.Samantha")
        #expect(decoded.speechRate == 200)
        #expect(decoded.speechVolume == 0.8)
        #expect(decoded.silenceThreshold == 2.0)
        #expect(decoded.recognitionLocale == "en-US")
        #expect(decoded.wakeWordEnabled)
        #expect(decoded.triggerWords == ["hey mcclaw"])
        #expect(decoded.pushToTalkEnabled)
        #expect(decoded.pushToTalkKeyCode == 0x3A)
    }
}
