import Foundation
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

    // MARK: - Background Session Arguments

    @Test("Background session args use pure interactive PTY mode")
    func buildBackgroundSessionArgs() {
        let args = CLIParser.buildBackgroundSessionArguments(sessionId: "bg-123")
        // PTY mode: pure interactive — no output format, no input format, no verbose
        #expect(!args.contains("--print"))
        #expect(!args.contains("--input-format"))
        #expect(!args.contains("--output-format"))
        #expect(!args.contains("--verbose"))
        // Must include session ID
        #expect(args.contains("--session-id"))
        #expect(args.contains("bg-123"))
    }

    @Test("Background session args with model")
    func buildBackgroundSessionArgsWithModel() {
        let args = CLIParser.buildBackgroundSessionArguments(
            sessionId: "bg-456", model: "claude-sonnet-4-20250514"
        )
        #expect(args.contains("--model"))
        #expect(args.contains("claude-sonnet-4-20250514"))
        #expect(!args.contains("--print"))
    }

    @Test("Background session args in PTY mode have no system prompt support")
    func buildBackgroundSessionArgsNoSystemPrompt() {
        // PTY interactive mode doesn't support --system-prompt (not applicable)
        let args = CLIParser.buildBackgroundSessionArguments(sessionId: "bg-000")
        #expect(!args.contains("--system-prompt"))
    }

    // MARK: - Codex parseLine

    @Test("Codex parse text line returns text")
    func parseCodexText() {
        let event = CLIParser.parseLine("Refactored the function.", provider: "codex")
        #expect(event == .text("Refactored the function."))
    }

    @Test("Codex parse empty line returns passthrough")
    func parseCodexEmpty() {
        let event = CLIParser.parseLine("", provider: "codex")
        #expect(event == .passthrough(""))
    }

    // MARK: - Codex buildArguments

    @Test("Codex args default mode uses full-auto approval")
    func buildArgsCodex() {
        let args = CLIParser.buildArguments(for: "codex", message: "refactor this")
        #expect(args.contains("--approval-mode"))
        #expect(args.contains("full-auto"))
        #expect(args.contains("--quiet"))
        #expect(args.last?.contains("refactor this") == true)
    }

    @Test("Codex args with model")
    func buildArgsCodexWithModel() {
        let args = CLIParser.buildArguments(for: "codex", message: "test", model: "o4-mini")
        #expect(args.contains("--model"))
        #expect(args.contains("o4-mini"))
    }

    @Test("Codex args in plan mode uses suggest approval")
    func buildArgsCodexPlanMode() {
        let args = CLIParser.buildArguments(for: "codex", message: "analyze", planMode: true)
        #expect(args.contains("--approval-mode"))
        #expect(args.contains("suggest"))
        #expect(!args.contains("full-auto"))
    }

    // MARK: - Amazon Q parseLine

    @Test("Amazon Q parse text line returns text")
    func parseAmazonQText() {
        let event = CLIParser.parseLine("Here is the answer.", provider: "amazonq")
        #expect(event == .text("Here is the answer."))
    }

    @Test("Amazon Q parse empty line returns passthrough")
    func parseAmazonQEmpty() {
        let event = CLIParser.parseLine("", provider: "amazonq")
        #expect(event == .passthrough(""))
    }

    // MARK: - Amazon Q buildArguments

    @Test("Amazon Q args use chat --no-interactive")
    func buildArgsAmazonQ() {
        let args = CLIParser.buildArguments(for: "amazonq", message: "hello")
        #expect(args.first == "chat")
        #expect(args.contains("--no-interactive"))
        #expect(args.last?.contains("hello") == true)
    }

    @Test("Amazon Q plan mode injects system prompt")
    func buildArgsAmazonQPlanMode() {
        let args = CLIParser.buildArguments(for: "amazonq", message: "analyze", planMode: true)
        let joined = args.joined(separator: " ")
        #expect(joined.contains("PLAN MODE"))
    }

    // MARK: - Gemini parseLine

    @Test("Gemini parse init JSON returns passthrough empty")
    func parseGeminiInit() {
        let json = #"{"type":"init","timestamp":"2026-03-16T20:35:10.834Z","session_id":"abc","model":"gemini-3"}"#
        let event = CLIParser.parseLine(json, provider: "gemini")
        #expect(event == .passthrough(""))
    }

    @Test("Gemini parse message JSON returns text")
    func parseGeminiMessage() {
        let json = #"{"type":"message","role":"assistant","content":"Hello!","delta":true}"#
        let event = CLIParser.parseLine(json, provider: "gemini")
        #expect(event == .text("Hello!"))
    }

    @Test("Gemini parse result JSON returns done")
    func parseGeminiResult() {
        let json = #"{"type":"result"}"#
        let event = CLIParser.parseLine(json, provider: "gemini")
        #expect(event == .done)
    }

    @Test("Gemini parse mixed line with MCP warning and init JSON suppresses both")
    func parseGeminiMixedMCPInit() {
        let line = #"MCP issues detected. Run /mcp list for status.{"type":"init","timestamp":"2026-03-16T20:35:10.834Z","session_id":"abc","model":"gemini-3"}"#
        let event = CLIParser.parseLine(line, provider: "gemini")
        #expect(event == .passthrough(""))
    }

    @Test("Gemini parse mixed line with text prefix and message JSON returns text")
    func parseGeminiMixedTextMessage() {
        let line = #"some warning{"type":"message","role":"assistant","content":"Hi","delta":true}"#
        let event = CLIParser.parseLine(line, provider: "gemini")
        #expect(event == .text("Hi"))
    }

    @Test("Gemini parse error JSON returns error text")
    func parseGeminiError() {
        let json = #"{"type":"error","output":"Something went wrong"}"#
        let event = CLIParser.parseLine(json, provider: "gemini")
        #expect(event == .text("[Error] Something went wrong"))
    }

    // MARK: - Stdin JSON encoding

    @Test("encodeStdinMessage produces valid JSON with newline")
    func encodeStdinMessage() {
        let encoded = CLIParser.encodeStdinMessage("Hello world")
        #expect(encoded.hasSuffix("\n"))
        let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = trimmed.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "user_message")
        #expect(json["message"] as? String == "Hello world")
    }

    @Test("encodeStdinMessage handles special characters")
    func encodeStdinMessageSpecialChars() {
        let encoded = CLIParser.encodeStdinMessage("Hello \"world\" with\nnewlines")
        #expect(!encoded.isEmpty)
        let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = trimmed.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["message"] as? String == "Hello \"world\" with\nnewlines")
    }

    @Test("encodeControlRequest produces valid JSON")
    func encodeControlRequest() {
        let encoded = CLIParser.encodeControlRequest(subtype: "interrupt", requestId: "req-42")
        #expect(encoded.hasSuffix("\n"))
        let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = trimmed.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "control_request")
        #expect(json["request_id"] as? String == "req-42")
        let request = json["request"] as! [String: Any]
        #expect(request["subtype"] as? String == "interrupt")
    }
}
