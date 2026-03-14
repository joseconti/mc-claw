import SwiftUI
import AppKit

/// Renders markdown content with support for code blocks, headers, lists, and inline formatting.
/// Splits content into blocks: code fences get a monospaced card, everything else uses AttributedString markdown.
struct MarkdownContentView: View {
    let content: String
    var fontSize: CGFloat = 16
    var fontFamily: ChatFontFamily = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let language, let code):
                    codeBlock(language: language, code: code)
                case .text(let text):
                    inlineMarkdown(text)
                case .header(let level, let text):
                    headerView(level: level, text: text)
                case .horizontalRule:
                    Divider()
                        .padding(.vertical, 4)
                case .table(let headers, let rows):
                    tableView(headers: headers, rows: rows)
                case .blockquote(let lines):
                    blockquoteView(lines: lines)
                case .list(let items):
                    listView(items: items)
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
                    .font(fontFamily.font(size: fontSize))
            } else {
                Text(trimmed)
                    .font(fontFamily.font(size: fontSize))
            }
        }
    }

    @ViewBuilder
    private func headerView(level: Int, text: String) -> some View {
        let headerSize: CGFloat = switch level {
        case 1: fontSize * 1.6
        case 2: fontSize * 1.35
        case 3: fontSize * 1.15
        default: fontSize * 1.05
        }
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(fontFamily.font(size: headerSize).bold())
                .padding(.top, level <= 2 ? 4 : 2)
        } else {
            Text(text)
                .font(fontFamily.font(size: headerSize).bold())
                .padding(.top, level <= 2 ? 4 : 2)
        }
    }

    @ViewBuilder
    private func tableView(headers: [String], rows: [[String]]) -> some View {
        let columnCount = headers.count
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header row
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { col in
                        tableCellText(headers[col], bold: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.cardBackground.opacity(0.6))
                    }
                }

                Divider()

                // Data rows
                ForEach(0..<rows.count, id: \.self) { rowIdx in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { col in
                            let cellText = col < rows[rowIdx].count ? rows[rowIdx][col] : ""
                            tableCellText(cellText, bold: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                    }
                    if rowIdx < rows.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .background(Theme.cardBackground.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func tableCellText(_ text: String, bold: Bool) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(bold ? fontFamily.font(size: fontSize - 1).bold() : fontFamily.font(size: fontSize - 1))
        } else {
            Text(text)
                .font(bold ? fontFamily.font(size: fontSize - 1).bold() : fontFamily.font(size: fontSize - 1))
        }
    }

    // MARK: - Blockquote

    @ViewBuilder
    private func blockquoteView(lines: [String]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.hasPrefix(">") {
                        // Nested blockquote: render as indented blockquote line
                        let nested = String(line.dropFirst(line.hasPrefix("> ") ? 2 : 1))
                        HStack(alignment: .top, spacing: 0) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 3)
                            inlineMarkdown(nested)
                                .padding(.leading, 8)
                        }
                    } else {
                        inlineMarkdown(line)
                    }
                }
            }
            .padding(.leading, 10)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }

    // MARK: - List

    @ViewBuilder
    private func listView(items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    listMarker(for: item)
                        .foregroundStyle(.secondary)
                    inlineMarkdown(item.text)
                }
                .padding(.leading, CGFloat(item.indent) * 20)
            }
        }
    }

    @ViewBuilder
    private func listMarker(for item: ListItem) -> some View {
        switch item.kind {
        case .bullet:
            Text("\u{2022}")
                .font(fontFamily.font(size: fontSize))
        case .numbered(let n):
            Text("\(n).")
                .font(fontFamily.font(size: fontSize))
        case .taskUnchecked:
            Image(systemName: "square")
                .font(.system(size: fontSize - 2))
        case .taskChecked:
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: fontSize - 2))
                .foregroundStyle(Color.accentColor)
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

    private static var bgColor: Color { Theme.cardBackground }
    private static var borderColor: Color { Theme.border }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.subheadline.weight(.medium))
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

    private var isDarkTheme: Bool {
        ThemeManager.shared.selectedPreset.isDark != false
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
                .font(.subheadline)
                .foregroundStyle(isDarkTheme ? .white.opacity(0.8) : Color.primary.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(isDarkTheme ? .white.opacity(0.15) : Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isDarkTheme ? .clear : Color.primary.opacity(0.15), lineWidth: 1)
                )
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

    // MARK: Theme-aware colors

    /// Whether the active theme is a light theme.
    @MainActor
    private static var isLightTheme: Bool {
        ThemeManager.shared.selectedPreset.isDark == false
    }

    // Dark theme colors
    private static let darkKeyword = NSColor(red: 0.78, green: 0.47, blue: 0.86, alpha: 1.0)   // purple
    private static let darkString = NSColor(red: 0.58, green: 0.79, blue: 0.49, alpha: 1.0)     // green
    private static let darkComment = NSColor(red: 0.45, green: 0.50, blue: 0.55, alpha: 1.0)    // gray
    private static let darkNumber = NSColor(red: 0.82, green: 0.68, blue: 0.45, alpha: 1.0)     // orange
    private static let darkFunction = NSColor(red: 0.38, green: 0.69, blue: 0.93, alpha: 1.0)   // blue
    private static let darkType = NSColor(red: 0.38, green: 0.80, blue: 0.77, alpha: 1.0)       // teal
    private static let darkVariable = NSColor(red: 0.90, green: 0.55, blue: 0.47, alpha: 1.0)   // red/coral
    private static let darkDefault = NSColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1.0)    // light gray

    // Light theme colors (high contrast on light backgrounds)
    private static let lightKeyword = NSColor(red: 0.55, green: 0.08, blue: 0.69, alpha: 1.0)   // dark purple
    private static let lightString = NSColor(red: 0.15, green: 0.50, blue: 0.13, alpha: 1.0)     // dark green
    private static let lightComment = NSColor(red: 0.42, green: 0.45, blue: 0.48, alpha: 1.0)    // medium gray
    private static let lightNumber = NSColor(red: 0.72, green: 0.42, blue: 0.00, alpha: 1.0)     // dark orange
    private static let lightFunction = NSColor(red: 0.00, green: 0.38, blue: 0.72, alpha: 1.0)   // dark blue
    private static let lightType = NSColor(red: 0.00, green: 0.50, blue: 0.47, alpha: 1.0)       // dark teal
    private static let lightVariable = NSColor(red: 0.72, green: 0.20, blue: 0.15, alpha: 1.0)   // dark red
    private static let lightDefault = NSColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1.0)    // near-black

    @MainActor private static var keywordColor: NSColor { isLightTheme ? lightKeyword : darkKeyword }
    @MainActor private static var stringColor: NSColor { isLightTheme ? lightString : darkString }
    @MainActor private static var commentColor: NSColor { isLightTheme ? lightComment : darkComment }
    @MainActor private static var numberColor: NSColor { isLightTheme ? lightNumber : darkNumber }
    @MainActor private static var functionColor: NSColor { isLightTheme ? lightFunction : darkFunction }
    @MainActor private static var typeColor: NSColor { isLightTheme ? lightType : darkType }
    @MainActor private static var variableColor: NSColor { isLightTheme ? lightVariable : darkVariable }
    @MainActor private static var defaultColor: NSColor { isLightTheme ? lightDefault : darkDefault }

    @MainActor
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

    @MainActor
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

struct ListItem {
    enum Kind { case bullet, numbered(Int), taskUnchecked, taskChecked }
    let kind: Kind
    let text: String
    let indent: Int
}

enum MarkdownBlock {
    case text(String)
    case code(language: String, code: String)
    case header(level: Int, text: String)
    case horizontalRule
    case table(headers: [String], rows: [[String]])
    case blockquote(lines: [String])
    case list(items: [ListItem])
}

// MARK: - Parser

enum MarkdownBlockParser {
    /// Splits markdown content into all supported block types.
    static func parse(_ content: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeLanguage = ""
        var codeContent = ""
        var tableLines: [String] = []
        var blockquoteLines: [String] = []
        var listItems: [ListItem] = []

        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // 1. Code fences (highest priority)
            if !inCodeBlock && trimmedLine.hasPrefix("```") {
                flushAll(&currentText, &tableLines, &blockquoteLines, &listItems, into: &blocks)
                let afterFence = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLanguage = afterFence
                codeContent = ""
                inCodeBlock = true
                continue
            }
            if inCodeBlock && trimmedLine.hasPrefix("```") {
                if codeContent.hasSuffix("\n") { codeContent = String(codeContent.dropLast()) }
                blocks.append(.code(language: codeLanguage, code: codeContent))
                codeLanguage = ""
                codeContent = ""
                inCodeBlock = false
                continue
            }
            if inCodeBlock {
                codeContent += (codeContent.isEmpty ? "" : "\n") + line
                continue
            }

            // 2. Table rows
            if isTableRow(trimmedLine) {
                if tableLines.isEmpty {
                    flushBlockquote(&blockquoteLines, into: &blocks)
                    flushList(&listItems, into: &blocks)
                    flushText(&currentText, into: &blocks)
                }
                tableLines.append(trimmedLine)
                continue
            }
            flushTable(&tableLines, into: &blocks)

            // 3. Blockquote lines (> ...)
            if let bqContent = parseBlockquoteLine(trimmedLine) {
                if blockquoteLines.isEmpty {
                    flushList(&listItems, into: &blocks)
                    flushText(&currentText, into: &blocks)
                }
                blockquoteLines.append(bqContent)
                continue
            }
            flushBlockquote(&blockquoteLines, into: &blocks)

            // 4. List items (-, *, +, 1., - [ ], - [x])
            if let item = parseListItem(line) {
                if listItems.isEmpty {
                    flushText(&currentText, into: &blocks)
                }
                listItems.append(item)
                continue
            }
            flushList(&listItems, into: &blocks)

            // 5. Headers
            if let headerMatch = parseHeader(trimmedLine) {
                flushText(&currentText, into: &blocks)
                blocks.append(.header(level: headerMatch.level, text: headerMatch.text))
                continue
            }

            // 6. Horizontal rules
            if isHorizontalRule(trimmedLine) {
                flushText(&currentText, into: &blocks)
                blocks.append(.horizontalRule)
                continue
            }

            // 7. Generic text
            currentText += (currentText.isEmpty ? "" : "\n") + line
        }

        // Flush everything remaining
        flushAll(&currentText, &tableLines, &blockquoteLines, &listItems, into: &blocks)
        if inCodeBlock {
            if codeContent.hasSuffix("\n") { codeContent = String(codeContent.dropLast()) }
            blocks.append(.code(language: codeLanguage, code: codeContent))
        }

        return blocks
    }

    // MARK: - Flush helpers

    private static func flushAll(
        _ text: inout String,
        _ tableLines: inout [String],
        _ blockquoteLines: inout [String],
        _ listItems: inout [ListItem],
        into blocks: inout [MarkdownBlock]
    ) {
        flushTable(&tableLines, into: &blocks)
        flushBlockquote(&blockquoteLines, into: &blocks)
        flushList(&listItems, into: &blocks)
        flushText(&text, into: &blocks)
    }

    private static func flushText(_ text: inout String, into blocks: inout [MarkdownBlock]) {
        if !text.isEmpty {
            blocks.append(.text(text))
            text = ""
        }
    }

    private static func flushBlockquote(_ lines: inout [String], into blocks: inout [MarkdownBlock]) {
        guard !lines.isEmpty else { return }
        blocks.append(.blockquote(lines: lines))
        lines.removeAll()
    }

    private static func flushList(_ items: inout [ListItem], into blocks: inout [MarkdownBlock]) {
        guard !items.isEmpty else { return }
        blocks.append(.list(items: items))
        items.removeAll()
    }

    // MARK: - Line parsers

    /// Parse a header line (# to ######). Returns nil if not a header.
    private static func parseHeader(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex && line[idx] == "#" && level < 6 {
            level += 1
            idx = line.index(after: idx)
        }
        guard level > 0 else { return nil }
        guard idx == line.endIndex || line[idx] == " " else { return nil }
        let headerText = String(line[idx...]).trimmingCharacters(in: .whitespaces)
        let cleaned = headerText.replacingOccurrences(of: "#+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return (level: level, text: cleaned)
    }

    /// Check for horizontal rules: ---, ***, ___ (3+ chars, optionally spaced)
    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        let allSame = stripped.allSatisfy { $0 == stripped.first }
        return allSame && (stripped.first == "-" || stripped.first == "*" || stripped.first == "_")
    }

    /// Extract blockquote content from a line starting with >.
    /// Returns the content after stripping the > prefix, or nil if not a blockquote.
    private static func parseBlockquoteLine(_ line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        var content = String(line.dropFirst())
        if content.hasPrefix(" ") { content = String(content.dropFirst()) }
        return content
    }

    /// Parse a list item from a line. Supports bullets (-, *, +), numbered (1.), and tasks (- [ ], - [x]).
    /// Uses leading whitespace to determine indent level (every 2 spaces or 1 tab = 1 level).
    private static func parseListItem(_ line: String) -> ListItem? {
        // Count leading whitespace for indent
        let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = leadingSpaces / 2
        let trimmed = line.trimmingCharacters(in: .init(charactersIn: " \t"))

        // Task list: - [ ] text, - [x] text, * [ ] text, * [x] text
        if let taskMatch = parseTaskItem(trimmed) {
            return ListItem(kind: taskMatch.checked ? .taskChecked : .taskUnchecked,
                            text: taskMatch.text, indent: indent)
        }

        // Bullet list: - text, * text, + text
        for marker in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(marker) {
                let text = String(trimmed.dropFirst(marker.count))
                return ListItem(kind: .bullet, text: text, indent: indent)
            }
        }

        // Numbered list: 1. text, 2. text, etc.
        if let dotIdx = trimmed.firstIndex(of: ".") {
            let numPart = trimmed[trimmed.startIndex..<dotIdx]
            if let num = Int(numPart), num > 0 {
                let afterDot = trimmed.index(after: dotIdx)
                guard afterDot < trimmed.endIndex && trimmed[afterDot] == " " else { return nil }
                let text = String(trimmed[trimmed.index(after: afterDot)...])
                return ListItem(kind: .numbered(num), text: text, indent: indent)
            }
        }

        return nil
    }

    /// Parse task list items: - [ ] text, - [x] text, * [ ] text, * [x] text
    private static func parseTaskItem(_ line: String) -> (checked: Bool, text: String)? {
        for prefix in ["- ", "* ", "+ "] {
            guard line.hasPrefix(prefix) else { continue }
            let afterMarker = String(line.dropFirst(prefix.count))
            if afterMarker.hasPrefix("[ ] ") {
                return (checked: false, text: String(afterMarker.dropFirst(4)))
            }
            if afterMarker.hasPrefix("[x] ") || afterMarker.hasPrefix("[X] ") {
                return (checked: true, text: String(afterMarker.dropFirst(4)))
            }
        }
        return nil
    }

    // MARK: - Table helpers

    private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.contains("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = parseTableCells(line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: .whitespaces)
            return stripped.isEmpty || stripped.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
        }
    }

    private static func parseTableCells(_ line: String) -> [String] {
        var raw = line
        if raw.hasPrefix("|") { raw = String(raw.dropFirst()) }
        if raw.hasSuffix("|") { raw = String(raw.dropLast()) }
        return raw.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func flushTable(_ tableLines: inout [String], into blocks: inout [MarkdownBlock]) {
        guard tableLines.count >= 2 else {
            if !tableLines.isEmpty {
                let text = tableLines.joined(separator: "\n")
                blocks.append(.text(text))
                tableLines.removeAll()
            }
            return
        }

        let headers = parseTableCells(tableLines[0])
        guard isTableSeparator(tableLines[1]), !headers.isEmpty else {
            let text = tableLines.joined(separator: "\n")
            blocks.append(.text(text))
            tableLines.removeAll()
            return
        }

        var rows: [[String]] = []
        for i in 2..<tableLines.count {
            if !isTableSeparator(tableLines[i]) {
                rows.append(parseTableCells(tableLines[i]))
            }
        }

        blocks.append(.table(headers: headers, rows: rows))
        tableLines.removeAll()
    }
}
