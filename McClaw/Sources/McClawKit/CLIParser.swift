import Foundation

/// Parses CLI output lines and builds CLI arguments.
/// Extracted from CLIBridge for testability.
public enum CLIParser {

    /// Event types returned by `parseLine`.
    public enum StreamEvent: Sendable, Equatable {
        case text(String)
        case toolStart(name: String, id: String)
        case thinking(String)
        case done
        case passthrough(String)
    }

    /// Parse a single line of CLI output into a stream event.
    /// - Parameters:
    ///   - line: Raw output line from the CLI process
    ///   - provider: The CLI provider identifier (e.g. "claude", "chatgpt")
    /// - Returns: A parsed stream event
    public static func parseLine(_ line: String, provider: String) -> StreamEvent {
        // BitNet outputs plain text (no structured JSON)
        if provider == "bitnet" {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .passthrough("") }
            if trimmed.hasSuffix("> ") || trimmed == ">" { return .done }
            return .text(trimmed)
        }

        if provider == "claude", let data = line.data(using: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let type = json["type"] as? String {
                    switch type {
                    // Non-verbose stream-json events
                    case "content_block_delta":
                        if let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            return .text(text)
                        }
                    case "tool_use":
                        if let name = json["name"] as? String,
                           let id = json["id"] as? String {
                            return .toolStart(name: name, id: id)
                        }
                    case "thinking":
                        if let text = json["thinking"] as? String {
                            return .thinking(text)
                        }
                    case "message_stop":
                        return .done

                    // Verbose stream-json events
                    case "assistant":
                        if let message = json["message"] as? [String: Any],
                           let content = message["content"] as? [[String: Any]] {
                            // Extract text from all content blocks
                            var textParts: [String] = []
                            for block in content {
                                let blockType = block["type"] as? String
                                if blockType == "text", let t = block["text"] as? String {
                                    textParts.append(t)
                                }
                                // Thinking blocks are silently consumed (not shown to user)
                            }
                            let text = textParts.joined()
                            if !text.isEmpty {
                                return .text(text)
                            }
                        }
                        // Even if no text content, don't passthrough (could be thinking-only)
                        return .passthrough("")
                    case "result":
                        return .done
                    case "system", "rate_limit_event", "user":
                        // Ignore system init, rate limit, and user echo-back events
                        return .passthrough("")

                    default:
                        break
                    }
                }
            }
        }

        // Gemini stream-json: {"type":"message","role":"assistant","content":"...","delta":true}
        if provider == "gemini", let data = line.data(using: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                switch type {
                case "message":
                    if let role = json["role"] as? String, role == "assistant",
                       let content = json["content"] as? String, !content.isEmpty {
                        return .text(content)
                    }
                    return .passthrough("")
                case "result":
                    return .done
                case "init", "tool_use", "tool_result":
                    return .passthrough("")
                case "error":
                    if let output = json["output"] as? String {
                        return .text("[Error] \(output)")
                    }
                    return .passthrough("")
                default:
                    break
                }
            }
        }

        return .passthrough(line)
    }

    /// Build CLI arguments for a given provider.
    /// - Parameters:
    ///   - providerId: The CLI provider identifier
    ///   - message: The user message to send
    ///   - model: Optional model override
    ///   - sessionId: Optional session identifier for conversation continuity
    ///   - isResume: If true, use --resume (existing session). If false, use --session-id (new session).
    /// - Returns: Array of CLI arguments
    /// Formatting hint appended to messages for providers that output plain text.
    /// Ensures code blocks are wrapped in markdown fences for proper rendering.
    private static let formattingHint = "\n\n[Format: always wrap code in markdown fences (```language\\ncode\\n```). Never output raw code without fences.]"

    /// System prompt injected for providers without native plan mode support.
    private static let planModeSystemPrompt = """
        You are in PLAN MODE (read-only). You MUST NOT:
        - Write, create, edit, or delete any files
        - Execute any commands or scripts
        - Make any changes to the system

        You MUST ONLY:
        - Read and analyze existing files and code
        - Search for patterns and information
        - Ask clarifying questions
        - Create detailed analysis and implementation plans

        Always respond with analysis and plans, never with actions.
        """

    public static func buildArguments(
        for providerId: String,
        message: String,
        model: String? = nil,
        sessionId: String? = nil,
        isResume: Bool = false,
        systemPrompt: String? = nil,
        allowedTools: [String]? = nil,
        planMode: Bool = false
    ) -> [String] {
        switch providerId {
        case "claude":
            // Claude requires --verbose with stream-json.
            // Streaming comes from content_block_delta events within verbose output.
            var args = ["--print", "--verbose", "--output-format", "stream-json"]
            if planMode {
                args += ["--permission-mode", "plan"]
            }
            if let model { args += ["--model", model] }
            if let systemPrompt, !systemPrompt.isEmpty {
                args += ["--system-prompt", systemPrompt]
            }
            if let allowedTools, !allowedTools.isEmpty {
                for tool in allowedTools {
                    args += ["--allowedTools", tool]
                }
            }
            if let sessionId {
                if isResume {
                    // Resume an existing Claude CLI session
                    args += ["--resume", sessionId]
                } else {
                    // Start a new session with a specific ID (so we can resume later)
                    args += ["--session-id", sessionId]
                }
            }
            args += [message]
            return args

        case "chatgpt":
            var args: [String] = []
            if planMode {
                args += ["--sandbox", "read-only"]
            }
            if let model { args += ["-m", model] }
            // ChatGPT CLI has no --system-prompt; prepend to message
            let prefix = systemPromptPrefix(systemPrompt, provider: "chatgpt")
            args += [prefix + message + formattingHint]
            return args

        case "gemini":
            var args = ["-o", "stream-json"]
            if planMode {
                args += ["--approval-mode=plan"]
            }
            if let model { args += ["--model", model] }
            let prefix = systemPromptPrefix(systemPrompt, provider: "gemini")
            args += [prefix + message]
            return args

        case "ollama":
            var args = ["run"]
            args += [model ?? "llama3.2"]
            // Ollama has no native plan mode; inject system prompt fallback
            let planPrefix = planMode ? "[PLAN MODE]\n\(planModeSystemPrompt)\n[END PLAN MODE]\n\n" : ""
            let prefix = systemPromptPrefix(systemPrompt, provider: "ollama")
            args += [planPrefix + prefix + message + formattingHint]
            return args

        case "bitnet":
            // BitNet primarily uses REST server (handled in CLIBridge).
            // This builds fallback CLI args for direct inference via run_inference.py.
            let prompt = planMode ? "[PLAN MODE]\n\(planModeSystemPrompt)\n[END PLAN MODE]\n\n\(message)" : message
            return BitNetKit.buildInferenceArgs(
                modelPath: BitNetKit.Paths.resolveModelPath(model ?? "BitNet-b1.58-2B-4T"),
                prompt: prompt
            )

        default:
            let planPrefix = planMode ? "[PLAN MODE]\n\(planModeSystemPrompt)\n[END PLAN MODE]\n\n" : ""
            let prefix = systemPromptPrefix(systemPrompt, provider: "unknown")
            return [planPrefix + prefix + message + formattingHint]
        }
    }

    /// Build a prefix block for providers that don't support --system-prompt natively.
    private static func systemPromptPrefix(_ systemPrompt: String?, provider: String) -> String {
        guard let prompt = systemPrompt, !prompt.isEmpty else { return "" }
        return "[System Instructions]\n\(prompt)\n[End System Instructions]\n\n"
    }
}
