import Testing
@testable import McClawKit

@Suite("CLIParser Tests")
struct CLIParserTests {

    // MARK: - parseLine() with Claude JSON

    @Test("Parse content_block_delta extracts text")
    func parseContentBlockDelta() {
        let json = #"{"type":"content_block_delta","delta":{"text":"Hello world"}}"#
        let event = CLIParser.parseLine(json, provider: "claude")
        #expect(event == .text("Hello world"))
    }

    @Test("Parse tool_use extracts name and id")
    func parseToolUse() {
        let json = #"{"type":"tool_use","name":"read_file","id":"tool_123"}"#
        let event = CLIParser.parseLine(json, provider: "claude")
        #expect(event == .toolStart(name: "read_file", id: "tool_123"))
    }

    @Test("Parse thinking extracts thought text")
    func parseThinking() {
        let json = #"{"type":"thinking","thinking":"Let me analyze this..."}"#
        let event = CLIParser.parseLine(json, provider: "claude")
        #expect(event == .thinking("Let me analyze this..."))
    }

    @Test("Parse message_stop returns done")
    func parseMessageStop() {
        let json = #"{"type":"message_stop"}"#
        let event = CLIParser.parseLine(json, provider: "claude")
        #expect(event == .done)
    }

    @Test("Parse unknown type falls through to passthrough")
    func parseUnknownType() {
        let json = #"{"type":"ping"}"#
        let event = CLIParser.parseLine(json, provider: "claude")
        #expect(event == .passthrough(json))
    }

    @Test("Non-JSON line for claude returns passthrough")
    func parseNonJsonClaude() {
        let line = "Some plain text output"
        let event = CLIParser.parseLine(line, provider: "claude")
        #expect(event == .passthrough(line))
    }

    @Test("Non-claude provider returns passthrough")
    func parseNonClaudeProvider() {
        let line = "ChatGPT response text"
        let event = CLIParser.parseLine(line, provider: "chatgpt")
        #expect(event == .passthrough(line))
    }

    @Test("Parse content_block_delta with special characters")
    func parseSpecialChars() {
        let json = #"{"type":"content_block_delta","delta":{"text":"Hello \"world\" \n\ttab"}}"#
        let event = CLIParser.parseLine(json, provider: "claude")
        #expect(event == .text("Hello \"world\" \n\ttab"))
    }

    // MARK: - buildArguments()

    @Test("Claude args with defaults")
    func buildArgsClaude() {
        let args = CLIParser.buildArguments(for: "claude", message: "hello")
        #expect(args == ["--print", "--verbose", "--output-format", "stream-json", "hello"])
    }

    @Test("Claude args with model and new session")
    func buildArgsClaudeWithModelAndNewSession() {
        let args = CLIParser.buildArguments(
            for: "claude", message: "test", model: "claude-sonnet-4-20250514", sessionId: "sess-1"
        )
        #expect(args == [
            "--print", "--verbose", "--output-format", "stream-json",
            "--model", "claude-sonnet-4-20250514",
            "--session-id", "sess-1",
            "test"
        ])
    }

    @Test("Claude args with resume existing session")
    func buildArgsClaudeWithResume() {
        let args = CLIParser.buildArguments(
            for: "claude", message: "test", sessionId: "sess-1", isResume: true
        )
        #expect(args == [
            "--print", "--verbose", "--output-format", "stream-json",
            "--resume", "sess-1",
            "test"
        ])
    }

    // Non-Claude providers append a formatting hint to the message
    private let hint = "\n\n[Format: always wrap code in markdown fences (```language\\ncode\\n```). Never output raw code without fences.]"

    @Test("ChatGPT args with defaults")
    func buildArgsChatGPT() {
        let args = CLIParser.buildArguments(for: "chatgpt", message: "hi")
        #expect(args == ["hi" + hint])
    }

    @Test("ChatGPT args with model")
    func buildArgsChatGPTWithModel() {
        let args = CLIParser.buildArguments(for: "chatgpt", message: "hi", model: "gpt-4o")
        #expect(args == ["-m", "gpt-4o", "hi" + hint])
    }

    @Test("Gemini args with defaults")
    func buildArgsGemini() {
        let args = CLIParser.buildArguments(for: "gemini", message: "hey")
        #expect(args == ["-o", "stream-json", "hey"])
    }

    @Test("Gemini args with model")
    func buildArgsGeminiWithModel() {
        let args = CLIParser.buildArguments(for: "gemini", message: "hey", model: "gemini-pro")
        #expect(args == ["-o", "stream-json", "--model", "gemini-pro", "hey"])
    }

    @Test("Ollama args with default model")
    func buildArgsOllama() {
        let args = CLIParser.buildArguments(for: "ollama", message: "test")
        #expect(args == ["run", "llama3.2", "test" + hint])
    }

    @Test("Ollama args with custom model")
    func buildArgsOllamaWithModel() {
        let args = CLIParser.buildArguments(for: "ollama", message: "test", model: "mistral")
        #expect(args == ["run", "mistral", "test" + hint])
    }

    @Test("Unknown provider returns message with hint")
    func buildArgsUnknown() {
        let args = CLIParser.buildArguments(for: "unknown", message: "hello")
        #expect(args == ["hello" + hint])
    }

    // MARK: - BitNet parseLine

    @Test("BitNet parse text line returns text")
    func parseBitNetText() {
        let event = CLIParser.parseLine("Hello from BitNet", provider: "bitnet")
        #expect(event == .text("Hello from BitNet"))
    }

    @Test("BitNet parse empty line returns passthrough")
    func parseBitNetEmpty() {
        let event = CLIParser.parseLine("", provider: "bitnet")
        #expect(event == .passthrough(""))
    }

    @Test("BitNet parse prompt marker returns done")
    func parseBitNetPrompt() {
        let event = CLIParser.parseLine("> ", provider: "bitnet")
        #expect(event == .done)
    }

    // MARK: - BitNet buildArguments

    @Test("BitNet args use run_inference.py path")
    func buildArgsBitNet() {
        let args = CLIParser.buildArguments(for: "bitnet", message: "Hello")
        #expect(args.contains("Hello"))
        #expect(args.contains(where: { $0.hasSuffix("run_inference.py") }))
    }

    @Test("BitNet args use specified model")
    func buildArgsBitNetModel() {
        let args = CLIParser.buildArguments(for: "bitnet", message: "test", model: "bitnet_b1_58-3B")
        #expect(args.contains(where: { $0.contains("bitnet_b1_58-3B") }))
    }

    // MARK: - Plan Mode buildArguments

    @Test("Claude args with plan mode")
    func buildArgsClaudePlanMode() {
        let args = CLIParser.buildArguments(for: "claude", message: "analyze this", planMode: true)
        #expect(args.contains("--permission-mode"))
        #expect(args.contains("plan"))
    }

    @Test("Claude args without plan mode omits flag")
    func buildArgsClaudeNoPlanMode() {
        let args = CLIParser.buildArguments(for: "claude", message: "hello", planMode: false)
        #expect(!args.contains("--permission-mode"))
    }

    @Test("Gemini args with plan mode")
    func buildArgsGeminiPlanMode() {
        let args = CLIParser.buildArguments(for: "gemini", message: "analyze this", planMode: true)
        #expect(args.contains("--approval-mode=plan"))
    }

    @Test("ChatGPT args with plan mode")
    func buildArgsChatGPTPlanMode() {
        let args = CLIParser.buildArguments(for: "chatgpt", message: "analyze this", planMode: true)
        #expect(args.contains("--sandbox"))
        #expect(args.contains("read-only"))
    }

    @Test("Ollama plan mode injects system prompt")
    func buildArgsOllamaPlanMode() {
        let args = CLIParser.buildArguments(for: "ollama", message: "analyze this", planMode: true)
        let joined = args.joined(separator: " ")
        #expect(joined.contains("PLAN MODE"))
    }

    @Test("BitNet plan mode injects system prompt")
    func buildArgsBitNetPlanMode() {
        let args = CLIParser.buildArguments(for: "bitnet", message: "analyze this", planMode: true)
        let joined = args.joined(separator: " ")
        #expect(joined.contains("PLAN MODE"))
    }
}
