import Foundation

/// Pure logic for Interactive Prompts.
/// Handles model definitions, JSON extraction from AI responses, and response formatting.
/// Fully testable with no actor dependencies.
public enum InteractivePromptKit {

    // MARK: - Models

    /// An interactive prompt emitted by the AI for user input.
    public struct InteractivePrompt: Identifiable, Codable, Sendable, Equatable {
        public let id: String
        public let type: String
        public let title: String
        public let description: String?
        public let style: PromptStyle
        public let options: [PromptOption]?
        public let required: Bool
        public let groupId: String?
        public let groupIndex: Int?
        public let groupTotal: Int?

        public init(
            id: String,
            type: String = "interactive_prompt",
            title: String,
            description: String? = nil,
            style: PromptStyle,
            options: [PromptOption]? = nil,
            required: Bool = false,
            groupId: String? = nil,
            groupIndex: Int? = nil,
            groupTotal: Int? = nil
        ) {
            self.id = id
            self.type = type
            self.title = title
            self.description = description
            self.style = style
            self.options = options
            self.required = required
            self.groupId = groupId
            self.groupIndex = groupIndex
            self.groupTotal = groupTotal
        }
    }

    /// Style of the interactive prompt.
    public enum PromptStyle: String, Codable, Sendable, Equatable {
        case singleChoice = "single_choice"
        case multiChoice = "multi_choice"
        case confirmation
        case freeText = "free_text"
    }

    /// A selectable option within a prompt.
    public struct PromptOption: Codable, Sendable, Equatable, Identifiable {
        public var id: String { key }
        public let key: String
        public let label: String
        public let icon: String?
        public let isFreeText: Bool?

        public init(key: String, label: String, icon: String? = nil, isFreeText: Bool? = nil) {
            self.key = key
            self.label = label
            self.icon = icon
            self.isFreeText = isFreeText
        }
    }

    /// A user's response to a prompt.
    public struct PromptResponse: Codable, Sendable, Equatable {
        public let promptId: String
        public let selectedKeys: [String]?
        public let freeText: String?
        public let skipped: Bool

        public init(
            promptId: String,
            selectedKeys: [String]? = nil,
            freeText: String? = nil,
            skipped: Bool = false
        ) {
            self.promptId = promptId
            self.selectedKeys = selectedKeys
            self.freeText = freeText
            self.skipped = skipped
        }
    }

    // MARK: - Parsing

    /// Extract interactive prompt JSON blocks from text.
    /// Returns (cleanText, prompts). If no prompts found, returns original text and empty array.
    public static func extractPrompts(from text: String) -> (String, [InteractivePrompt]) {
        var prompts: [InteractivePrompt] = []
        var cleanText = text

        // Pattern: ```json\n{...}\n``` blocks containing "interactive_prompt"
        let codeBlockPattern = "```(?:json)?\\s*\\n(\\{[^`]*?\"type\"\\s*:\\s*\"interactive_prompt\"[^`]*?\\})\\s*\\n```"

        guard let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: [.dotMatchesLineSeparators]) else {
            return (text, [])
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        // Process matches in reverse so removal indices stay valid
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }

            let jsonRange = match.range(at: 1)
            let jsonString = nsText.substring(with: jsonRange)

            guard let jsonData = jsonString.data(using: .utf8) else { continue }

            do {
                let prompt = try JSONDecoder().decode(InteractivePrompt.self, from: jsonData)
                if prompt.type == "interactive_prompt" {
                    prompts.insert(prompt, at: 0) // Maintain order
                    // Remove the full code block from cleanText
                    let fullRange = match.range(at: 0)
                    if let swiftRange = Range(fullRange, in: cleanText) {
                        cleanText.removeSubrange(swiftRange)
                    }
                }
            } catch {
                // Malformed JSON — skip this block, leave in text
                continue
            }
        }

        // Clean up extra blank lines left after removal
        while cleanText.contains("\n\n\n") {
            cleanText = cleanText.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleanText, prompts)
    }

    // MARK: - Response Formatting

    /// Format a user's response as natural language for injection into the conversation.
    public static func formatResponse(_ response: PromptResponse, prompt: InteractivePrompt) -> String {
        if response.skipped {
            return "[\(prompt.title): Skipped]"
        }

        if let freeText = response.freeText, !freeText.isEmpty {
            return "[\(prompt.title): \(freeText)]"
        }

        guard let selectedKeys = response.selectedKeys, !selectedKeys.isEmpty,
              let options = prompt.options else {
            return "[\(prompt.title): No response]"
        }

        let labels = selectedKeys.compactMap { key in
            options.first(where: { $0.key == key })?.label
        }

        if labels.isEmpty {
            return "[\(prompt.title): \(selectedKeys.joined(separator: ", "))]"
        }

        return "[\(prompt.title): \(labels.joined(separator: ", "))]"
    }
}
