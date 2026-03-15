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
        // DashScope uses OpenAI-compatible SSE streaming (handled in CLIBridge via URLSession).
        // parseLine is only called for CLI stdout; DashScope SSE parsing is in DashScopeKit.
        if provider == "dashscope" {
            let result = DashScopeKit.parseStreamLine(line)
            switch result {
            case .text(let text): return .text(text)
            case .done: return .done
            case .error(let msg): return .text("[Error] \(msg)")
            case .skip: return .passthrough("")
            }
        }

        // GitHub Copilot CLI outputs plain text
        if provider == "copilot" {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .passthrough("") }
            return .text(trimmed)
        }

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

        case "copilot":
            // GitHub Copilot CLI: `gh copilot` subcommand.
            // The binary is `gh`, so args start with ["copilot", ...].
            var args = ["copilot"]
            if let model { args += ["--model", model] }
            let planPrefix = planMode ? "[PLAN MODE]\n\(planModeSystemPrompt)\n[END PLAN MODE]\n\n" : ""
            let prefix = systemPromptPrefix(systemPrompt, provider: "copilot")
            args += [planPrefix + prefix + message + formattingHint]
            return args

        case "dashscope":
            // DashScope uses REST API (handled in CLIBridge via URLSession).
            // This case exists for interface completeness; actual dispatch is in CLIBridge.
            let planPrefix = planMode ? "[PLAN MODE]\n\(planModeSystemPrompt)\n[END PLAN MODE]\n\n" : ""
            let prefix = systemPromptPrefix(systemPrompt, provider: "dashscope")
            return [planPrefix + prefix + message]

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

    // MARK: - Background Session Arguments (Claude only)

    /// Build CLI arguments for a persistent Claude background session.
    /// Unlike `buildArguments`, this does NOT use `--print` (so the process stays alive)
    /// and adds `--input-format stream-json` so messages can be sent via stdin.
    /// This mirrors the VS Code extension's approach to Claude CLI communication.
    public static func buildBackgroundSessionArguments(
        sessionId: String,
        model: String? = nil,
        systemPrompt: String? = nil
    ) -> [String] {
        var args = ["--output-format", "stream-json", "--verbose", "--input-format", "stream-json"]
        if let model { args += ["--model", model] }
        if let systemPrompt, !systemPrompt.isEmpty {
            args += ["--system-prompt", systemPrompt]
        }
        args += ["--session-id", sessionId]
        return args
    }

    /// Encode a user message as a JSON line for stdin in stream-json input mode.
    /// Returns the JSON string with a trailing newline.
    public static func encodeStdinMessage(_ text: String) -> String {
        let payload: [String: Any] = [
            "type": "user_message",
            "message": text,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json + "\n"
    }

    /// Encode a control request (e.g. interrupt) as a JSON line for stdin.
    public static func encodeControlRequest(subtype: String, requestId: String = UUID().uuidString) -> String {
        let payload: [String: Any] = [
            "type": "control_request",
            "request_id": requestId,
            "request": ["subtype": subtype],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json + "\n"
    }

    /// Build a prefix block for providers that don't support --system-prompt natively.
    private static func systemPromptPrefix(_ systemPrompt: String?, provider: String) -> String {
        guard let prompt = systemPrompt, !prompt.isEmpty else { return "" }
        return "[System Instructions]\n\(prompt)\n[End System Instructions]\n\n"
    }
}
