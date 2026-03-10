import SwiftUI
import AppKit

/// Renders markdown content with support for code blocks, headers, lists, and inline formatting.
/// Splits content into blocks: code fences get a monospaced card, everything else uses AttributedString markdown.
struct MarkdownContentView: View {
    let content: String
    var fontSize: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let language, let code):
                    codeBlock(language: language, code: code)
                case .text(let text):
                    inlineMarkdown(text)
                }
            }
        }
    }

    // MARK: - Parsing

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(content)
    }

    // MARK: - Rendering

    @ViewBuilder
    private func codeBlock(language: String, code: String) -> some View {
        CodeBlockView(language: language, code: code, fontSize: fontSize)
    }

    @ViewBuilder
    private func inlineMarkdown(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if let attributed = try? AttributedString(
                markdown: trimmed,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .font(.system(size: fontSize))
            } else {
                Text(trimmed)
                    .font(.system(size: fontSize))
            }
        }
    }
}

// MARK: - Syntax Highlighted Code

/// Code block with hover-to-reveal copy button that floats with scroll, styled like Claude Desktop.
private struct CodeBlockView: View {
    let language: String
    let code: String
    let fontSize: CGFloat

    @State private var isHovering = false
    @State private var copied = false

    private static let bgColor = Color(nsColor: NSColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0))
    private static let borderColor = Color(nsColor: NSColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1.0))

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Code content with syntax highlighting
            ScrollView(.horizontal, showsIndicators: false) {
                SyntaxHighlightedCode(code: code, language: language, fontSize: fontSize - 2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(Self.bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Self.borderColor, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                copyButton
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Copy")
    }
}

/// Renders code with basic syntax highlighting similar to popular editors.
struct SyntaxHighlightedCode: View {
    let code: String
    let language: String
    let fontSize: CGFloat

    var body: some View {
        Text(highlightedCode)
            .font(.system(size: fontSize, design: .monospaced))
    }

    private var highlightedCode: AttributedString {
        SyntaxHighlighter.highlight(code, language: language, fontSize: fontSize)
    }
}

// MARK: - Syntax Highlighter

enum SyntaxHighlighter {

    // MARK: Theme colors (dark background)
    private static let keywordColor = NSColor(red: 0.78, green: 0.47, blue: 0.86, alpha: 1.0)   // purple
    private static let stringColor = NSColor(red: 0.58, green: 0.79, blue: 0.49, alpha: 1.0)     // green
    private static let commentColor = NSColor(red: 0.45, green: 0.50, blue: 0.55, alpha: 1.0)    // gray
    private static let numberColor = NSColor(red: 0.82, green: 0.68, blue: 0.45, alpha: 1.0)     // orange
    private static let functionColor = NSColor(red: 0.38, green: 0.69, blue: 0.93, alpha: 1.0)   // blue
    private static let typeColor = NSColor(red: 0.38, green: 0.80, blue: 0.77, alpha: 1.0)       // teal
    private static let variableColor = NSColor(red: 0.90, green: 0.55, blue: 0.47, alpha: 1.0)   // red/coral
    private static let defaultColor = NSColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1.0)    // light gray

    static func highlight(_ code: String, language: String, fontSize: CGFloat) -> AttributedString {
        let lang = language.lowercased()
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Start with default styled text
        var base = AttributedString(code)
        base.font = font
        base.foregroundColor = Color(nsColor: defaultColor)

        let text = code as NSString

        // Apply token-based highlighting
        let rules = tokenRules(for: lang)
        for rule in rules {
            let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options)
            let matches = regex?.matches(in: code, range: NSRange(location: 0, length: text.length)) ?? []

            for match in matches {
                let range = match.range(at: rule.captureGroup)
                guard range.location != NSNotFound,
                      let swiftRange = Range(range, in: code),
                      let attrRange = Range(swiftRange, in: base) else { continue }
                base[attrRange].foregroundColor = Color(nsColor: rule.color)
            }
        }

        return base
    }

    private struct TokenRule {
        let pattern: String
        let color: NSColor
        let options: NSRegularExpression.Options
        let captureGroup: Int

        init(_ pattern: String, _ color: NSColor, options: NSRegularExpression.Options = [], captureGroup: Int = 0) {
            self.pattern = pattern
            self.color = color
            self.options = options
            self.captureGroup = captureGroup
        }
    }

    private static func tokenRules(for language: String) -> [TokenRule] {
        // Common rules applied to all languages
        var rules: [TokenRule] = []

        // Language-specific keywords
        let keywords: [String]
        switch language {
        case "swift":
            keywords = ["import", "func", "var", "let", "class", "struct", "enum", "protocol",
                        "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat",
                        "return", "throw", "throws", "try", "catch", "do", "break", "continue",
                        "self", "Self", "super", "init", "deinit", "true", "false", "nil",
                        "private", "public", "internal", "fileprivate", "open", "static",
                        "override", "mutating", "async", "await", "actor", "some", "any",
                        "where", "in", "is", "as", "typealias", "associatedtype", "extension",
                        "@MainActor", "@Observable", "@State", "@Binding", "@Published"]
        case "php":
            keywords = ["function", "class", "interface", "trait", "namespace", "use",
                        "if", "else", "elseif", "switch", "case", "default", "for", "foreach",
                        "while", "do", "return", "throw", "try", "catch", "finally",
                        "public", "private", "protected", "static", "abstract", "final",
                        "new", "echo", "print", "isset", "unset", "empty", "array",
                        "true", "false", "null", "const", "define", "require", "require_once",
                        "include", "include_once", "extends", "implements", "as", "match"]
        case "javascript", "js", "typescript", "ts":
            keywords = ["function", "const", "let", "var", "class", "extends", "import", "export",
                        "from", "if", "else", "switch", "case", "default", "for", "while", "do",
                        "return", "throw", "try", "catch", "finally", "new", "this", "super",
                        "async", "await", "yield", "typeof", "instanceof", "in", "of",
                        "true", "false", "null", "undefined", "void", "delete",
                        "interface", "type", "enum", "implements", "abstract", "readonly"]
        case "python", "py":
            keywords = ["def", "class", "import", "from", "as", "if", "elif", "else",
                        "for", "while", "with", "try", "except", "finally", "raise",
                        "return", "yield", "pass", "break", "continue", "and", "or", "not",
                        "is", "in", "lambda", "True", "False", "None", "self", "async", "await",
                        "global", "nonlocal", "del", "assert"]
        case "bash", "sh", "zsh", "shell":
            keywords = ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                        "case", "esac", "function", "return", "exit", "local", "export",
                        "source", "echo", "printf", "read", "shift", "set", "unset",
                        "true", "false", "in"]
        case "html", "xml":
            keywords = []
        case "css", "scss":
            keywords = ["import", "media", "keyframes", "font-face", "supports", "charset"]
        default:
            // Generic keywords common across languages
            keywords = ["if", "else", "for", "while", "return", "function", "class",
                        "var", "let", "const", "import", "export", "true", "false", "null",
                        "try", "catch", "throw", "new", "this", "self", "switch", "case", "default"]
        }

        // 1. Single-line comments
        switch language {
        case "html", "xml":
            rules.append(TokenRule("<!--.*?-->", commentColor, options: .dotMatchesLineSeparators))
        case "css", "scss":
            rules.append(TokenRule("/\\*.*?\\*/", commentColor, options: .dotMatchesLineSeparators))
            rules.append(TokenRule("//.*$", commentColor, options: .anchorsMatchLines))
        case "python", "py", "bash", "sh", "zsh", "shell":
            rules.append(TokenRule("#.*$", commentColor, options: .anchorsMatchLines))
        case "php":
            rules.append(TokenRule("//.*$", commentColor, options: .anchorsMatchLines))
            rules.append(TokenRule("#.*$", commentColor, options: .anchorsMatchLines))
            rules.append(TokenRule("/\\*.*?\\*/", commentColor, options: .dotMatchesLineSeparators))
        default:
            rules.append(TokenRule("//.*$", commentColor, options: .anchorsMatchLines))
            rules.append(TokenRule("/\\*.*?\\*/", commentColor, options: .dotMatchesLineSeparators))
        }

        // 2. Strings (double and single quoted)
        rules.append(TokenRule("\"(?:[^\"\\\\]|\\\\.)*\"", stringColor))
        rules.append(TokenRule("'(?:[^'\\\\]|\\\\.)*'", stringColor))
        // Backtick template strings for JS/TS
        if ["javascript", "js", "typescript", "ts"].contains(language) {
            rules.append(TokenRule("`(?:[^`\\\\]|\\\\.)*`", stringColor))
        }

        // 3. Numbers
        rules.append(TokenRule("\\b\\d+\\.?\\d*\\b", numberColor))

        // 4. Keywords (word boundary matching)
        if !keywords.isEmpty {
            let escaped = keywords.map { NSRegularExpression.escapedPattern(for: $0) }
            let pattern = "\\b(" + escaped.joined(separator: "|") + ")\\b"
            rules.append(TokenRule(pattern, keywordColor))
        }

        // 5. PHP variables ($var)
        if language == "php" {
            rules.append(TokenRule("\\$[a-zA-Z_][a-zA-Z0-9_]*", variableColor))
        }

        // 6. Function calls: word followed by (
        rules.append(TokenRule("\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(", functionColor, captureGroup: 1))

        // 7. Types (capitalized words, heuristic)
        if ["swift", "typescript", "ts", "java", "kotlin"].contains(language) {
            rules.append(TokenRule("\\b([A-Z][a-zA-Z0-9_]+)\\b", typeColor, captureGroup: 1))
        }

        // 8. HTML/XML tags
        if ["html", "xml", "php"].contains(language) {
            rules.append(TokenRule("</?([a-zA-Z][a-zA-Z0-9-]*)\\b", functionColor, captureGroup: 1))
            rules.append(TokenRule("\\b([a-zA-Z-]+)=", typeColor, captureGroup: 1))
        }

        return rules
    }
}

// MARK: - Block Model

enum MarkdownBlock {
    case text(String)
    case code(language: String, code: String)
}

// MARK: - Parser

enum MarkdownBlockParser {
    /// Splits markdown content into text blocks and fenced code blocks.
    static func parse(_ content: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeLanguage = ""
        var codeContent = ""

        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if !inCodeBlock && trimmedLine.hasPrefix("```") {
                // Start of code block - flush accumulated text
                if !currentText.isEmpty {
                    blocks.append(.text(currentText))
                    currentText = ""
                }
                // Extract language from opening fence
                let afterFence = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLanguage = afterFence
                codeContent = ""
                inCodeBlock = true
            } else if inCodeBlock && trimmedLine.hasPrefix("```") {
                // End of code block
                // Remove trailing newline from code
                if codeContent.hasSuffix("\n") {
                    codeContent = String(codeContent.dropLast())
                }
                blocks.append(.code(language: codeLanguage, code: codeContent))
                codeLanguage = ""
                codeContent = ""
                inCodeBlock = false
            } else if inCodeBlock {
                codeContent += (codeContent.isEmpty ? "" : "\n") + line
            } else {
                currentText += (currentText.isEmpty ? "" : "\n") + line
            }
        }

        // Flush remaining content
        if inCodeBlock {
            // Unclosed code block - treat as code anyway
            if codeContent.hasSuffix("\n") {
                codeContent = String(codeContent.dropLast())
            }
            blocks.append(.code(language: codeLanguage, code: codeContent))
        } else if !currentText.isEmpty {
            blocks.append(.text(currentText))
        }

        return blocks
    }
}
