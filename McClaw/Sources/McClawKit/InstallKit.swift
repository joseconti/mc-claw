import Foundation

/// Pure logic for the Agent Install feature.
/// Handles JSON parsing from AI responses, command splitting, plan validation,
/// and system prompt construction. Fully testable with no actor dependencies.
public enum InstallKit {

    // MARK: - JSON Parsing

    /// Intermediate struct for decoding the AI-generated install plan JSON.
    public struct ParsedPlan: Codable, Sendable {
        public let name: String
        public let description: String
        public let steps: [ParsedStep]
        public let warnings: [String]?

        public init(name: String, description: String, steps: [ParsedStep], warnings: [String]? = nil) {
            self.name = name
            self.description = description
            self.steps = steps
            self.warnings = warnings
        }
    }

    /// A single step parsed from the AI response.
    public struct ParsedStep: Codable, Sendable {
        public let description: String
        public let command: String
        public let workingDirectory: String?

        enum CodingKeys: String, CodingKey {
            case description
            case command
            case workingDirectory = "working_directory"
        }

        public init(description: String, command: String, workingDirectory: String? = nil) {
            self.description = description
            self.command = command
            self.workingDirectory = workingDirectory
        }
    }

    /// Extract and parse a JSON install plan from an AI response string.
    /// Handles markdown code fences, preamble text, and raw JSON.
    public static func parseInstallPlanJSON(_ response: String) throws -> ParsedPlan {
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8) else {
            throw InstallKitError.invalidJSON("Could not convert response to data")
        }

        do {
            return try JSONDecoder().decode(ParsedPlan.self, from: data)
        } catch {
            throw InstallKitError.invalidJSON("Failed to decode install plan: \(error.localizedDescription)")
        }
    }

    /// Extract a JSON object from a string that may contain markdown fences or surrounding text.
    public static func extractJSON(from text: String) -> String {
        // Try to find JSON inside markdown code fences first
        let fencePattern = #"```(?:json)?\s*\n?([\s\S]*?)\n?```"#
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Find the first { and last } to extract raw JSON
        if let firstBrace = text.firstIndex(of: "{"),
           let lastBrace = text.lastIndex(of: "}") {
            return String(text[firstBrace...lastBrace])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Command Splitting

    /// Split a shell command string into executable and arguments.
    /// Handles basic quoting (single and double quotes).
    public static func splitCommand(_ command: String) -> (executable: String, arguments: [String]) {
        let parts = shellSplit(command)
        guard let first = parts.first else {
            return (executable: command, arguments: [])
        }
        return (executable: first, arguments: Array(parts.dropFirst()))
    }

    /// Shell-style word splitting that respects single and double quotes.
    public static func shellSplit(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false

        for char in input {
            if escaped {
                current.append(char)
                escaped = false
                continue
            }

            if char == "\\" && !inSingleQuote {
                escaped = true
                continue
            }

            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }

            if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }

            if char == " " && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                continue
            }

            current.append(char)
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }

    // MARK: - Plan Validation

    /// Dangerous command patterns that should generate warnings.
    private static let dangerousPatterns: [(pattern: String, warning: String)] = [
        ("sudo ", "Uses elevated privileges (sudo)"),
        ("rm -rf /", "Recursively deletes from root directory"),
        ("rm -rf ~", "Recursively deletes home directory"),
        ("rm -rf /*", "Recursively deletes from root directory"),
        ("> /dev/sda", "Writes directly to disk device"),
        ("mkfs.", "Formats a filesystem"),
        ("dd if=", "Low-level disk copy (dd)"),
        (":(){ :|:& };:", "Fork bomb"),
        ("chmod 777", "Sets overly permissive file permissions"),
        ("curl|bash", "Pipes remote script directly to shell"),
        ("curl|sh", "Pipes remote script directly to shell"),
        ("wget|bash", "Pipes remote script directly to shell"),
        ("wget|sh", "Pipes remote script directly to shell"),
    ]

    /// Validate an install plan and return warnings for potentially dangerous commands.
    public static func validatePlan(_ plan: ParsedPlan) -> [String] {
        var warnings: [String] = []

        for step in plan.steps {
            let cmd = step.command.lowercased().replacingOccurrences(of: " ", with: "")
            let cmdOriginal = step.command.lowercased()

            for (pattern, warning) in dangerousPatterns {
                let normalizedPattern = pattern.lowercased().replacingOccurrences(of: " ", with: "")
                if cmd.contains(normalizedPattern) || cmdOriginal.contains(pattern.lowercased()) {
                    warnings.append("Step \(step.description): \(warning)")
                }
            }

            // Detect pipe-to-shell patterns (curl ... | bash, wget ... | sh, etc.)
            if hasPipeToShell(cmdOriginal) {
                warnings.append("Step \(step.description): Pipes remote content to shell interpreter")
            }
        }

        // Add plan-level warnings from AI
        if let aiWarnings = plan.warnings {
            warnings.append(contentsOf: aiWarnings)
        }

        return warnings
    }

    /// Detect patterns like `curl URL | bash` or `wget URL | sh`.
    public static func hasPipeToShell(_ command: String) -> Bool {
        let shells = ["bash", "sh", "zsh", "dash"]
        let pipes = command.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard pipes.count >= 2 else { return false }

        let lastPipe = pipes.last?.lowercased() ?? ""
        let firstPipe = pipes.first?.lowercased() ?? ""
        let isRemoteFetch = firstPipe.hasPrefix("curl") || firstPipe.hasPrefix("wget")
        let isShell = shells.contains(where: { lastPipe == $0 || lastPipe.hasPrefix($0 + " ") })

        return isRemoteFetch && isShell
    }

    // MARK: - System Prompt

    /// Build the system prompt that instructs the AI to analyze an install prompt
    /// and return a structured JSON plan.
    public static func buildParsingSystemPrompt() -> String {
        """
        You are an installation assistant. The user will paste an "install prompt" from a website \
        that describes software to install. Your job is to analyze it and output a structured JSON plan.

        Output ONLY a valid JSON object (no markdown fences, no explanation) with this exact structure:
        {
          "name": "Short name of the software",
          "description": "What this software does (1-2 sentences)",
          "steps": [
            {
              "description": "Human-readable description of this step",
              "command": "The exact shell command to run",
              "working_directory": "/optional/path or null"
            }
          ],
          "warnings": ["Any security concerns or important notes"]
        }

        Rules:
        - Break the installation into individual shell commands (one per step)
        - Use standard package managers when possible (brew, npm, pip, etc.)
        - Do NOT combine commands with && or ; — one command per step
        - Include any necessary configuration steps
        - Add warnings for commands that require elevated privileges, modify system files, or download remote scripts
        - If the prompt asks to read a URL for setup instructions, include a step to fetch it
        - The working_directory field is optional — omit or set to null if not needed
        """
    }

    // MARK: - Errors

    public enum InstallKitError: Error, LocalizedError, Sendable {
        case invalidJSON(String)
        case emptyPlan
        case noSteps

        public var errorDescription: String? {
            switch self {
            case .invalidJSON(let detail):
                return "Invalid JSON in AI response: \(detail)"
            case .emptyPlan:
                return "The AI returned an empty install plan"
            case .noSteps:
                return "The install plan has no steps"
            }
        }
    }
}
