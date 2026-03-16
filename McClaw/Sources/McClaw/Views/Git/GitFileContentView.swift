import SwiftUI

/// GitHub-style file content viewer with line numbers, syntax highlighting, and scrollable code.
struct GitFileContentView: View {
    let file: GitFileEntry
    let content: String?
    let isLoading: Bool
    let onClose: () -> Void
    var onSendToChat: ((String) -> Void)?

    @State private var selectedLineStart: Int?
    @State private var selectedLineEnd: Int?

    var body: some View {
        VStack(spacing: 0) {
            fileHeader
            Divider()

            if isLoading {
                loadingState
            } else if let content {
                codeView(content)
                    .contextMenu { fileContextMenu }
            } else {
                emptyState
            }
        }
    }

    // MARK: - File Header

    @ViewBuilder
    private var fileHeader: some View {
        HStack(spacing: 8) {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Image(systemName: fileIcon)
                .font(.callout)
                .foregroundStyle(fileIconColor)

            Text(file.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer()

            if let content {
                let lineCount = content.components(separatedBy: "\n").count
                Text("\(lineCount) lines", bundle: .appModule)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }

            Text(formattedSize(file.size))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if content != nil {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content ?? "", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Copy file contents", bundle: .appModule))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.3))
        .contextMenu { fileContextMenu }
    }

    // MARK: - Code View

    @ViewBuilder
    private func codeView(_ text: String) -> some View {
        let lines = text.components(separatedBy: "\n")
        let gutterWidth: CGFloat = 48  // Fixed width — fits up to 99999 lines consistently
        let lang = GitSyntaxHighlighter.language(for: file.name)
        let highlighted = GitSyntaxHighlighter.highlight(lines: lines, language: lang)

        ZStack(alignment: .bottomTrailing) {
            GeometryReader { geo in
                let minCodeWidth = max(0, geo.size.width - gutterWidth - 8 - 1) // available width after gutter+padding+separator
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 0) {
                        // Line numbers gutter (clickable for selection)
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                                let lineNum = index + 1
                                let selected = isLineSelected(lineNum)
                                Text(verbatim: "\(lineNum)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                                    .fontWeight(selected ? .semibold : .regular)
                                    .frame(height: 19, alignment: .trailing)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        handleLineClick(lineNum, shiftHeld: NSEvent.modifierFlags.contains(.shift))
                                    }
                            }
                        }
                        .frame(width: gutterWidth)
                        .padding(.trailing, 8)
                        .background(
                            Rectangle()
                                .fill(.quaternary.opacity(0.15))
                        )

                        // Separator
                        Rectangle()
                            .fill(.quaternary.opacity(0.5))
                            .frame(width: 1)

                        // Code content — fills available width, scrolls horizontally for long lines
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(highlighted.enumerated()), id: \.offset) { index, attrLine in
                                let lineNum = index + 1
                                Text(attrLine)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(height: 19, alignment: .leading)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .textSelection(.enabled)
                                    .background(isLineSelected(lineNum) ? Color.accentColor.opacity(0.1) : Color.clear)
                            }
                        }
                        .frame(minWidth: minCodeWidth, alignment: .leading)
                        .padding(.leading, 12)
                        .padding(.trailing, 16)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))

            // Floating "Ask AI" button when lines are selected
            if let start = selectedLineStart, let end = selectedLineEnd {
                Button {
                    let selectedLines = Array(lines[(start - 1)...(min(end, lines.count) - 1)])
                    let code = selectedLines.joined(separator: "\n")
                    let langName = languageName(for: lang)
                    let prompt = GitPromptTemplates.askAboutLines(
                        filePath: file.path,
                        startLine: start,
                        endLine: end,
                        code: code,
                        language: langName
                    )
                    onSendToChat?(prompt)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text(String(localized: "git_action_ask_about_lines \(start) \(end)", bundle: .appModule))
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
    }

    // MARK: - Line Selection

    private func isLineSelected(_ lineNum: Int) -> Bool {
        guard let start = selectedLineStart, let end = selectedLineEnd else { return false }
        return lineNum >= start && lineNum <= end
    }

    private func handleLineClick(_ lineNum: Int, shiftHeld: Bool) {
        if shiftHeld, let start = selectedLineStart {
            // Extend selection from start to clicked line
            let newEnd = max(start, lineNum)
            let newStart = min(start, lineNum)
            selectedLineStart = newStart
            selectedLineEnd = newEnd
        } else {
            // New single-line selection (or deselect if same line)
            if selectedLineStart == lineNum && selectedLineEnd == lineNum {
                selectedLineStart = nil
                selectedLineEnd = nil
            } else {
                selectedLineStart = lineNum
                selectedLineEnd = lineNum
            }
        }
    }

    private func languageName(for lang: GitSyntaxHighlighter.Language) -> String {
        switch lang {
        case .swift: return "swift"
        case .php: return "php"
        case .javascript: return "javascript"
        case .python: return "python"
        case .ruby: return "ruby"
        case .go: return "go"
        case .rust: return "rust"
        case .cLike: return "c"
        case .html: return "html"
        case .css: return "css"
        case .json: return "json"
        case .yaml: return "yaml"
        case .shell: return "shell"
        case .markdown: return "markdown"
        case .plain: return ""
        }
    }

    // MARK: - Loading

    @ViewBuilder
    private var loadingState: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text("Loading file…", bundle: .appModule)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Unable to load file content", bundle: .appModule)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File Context Menu

    @ViewBuilder
    private var fileContextMenu: some View {
        Button {
            onSendToChat?(GitPromptTemplates.explainFile(file.path))
        } label: {
            Label(String(localized: "git_action_explain_file", bundle: .appModule), systemImage: "doc.text.magnifyingglass")
        }

        Button {
            onSendToChat?(GitPromptTemplates.findUsagesFile(file.path))
        } label: {
            Label(String(localized: "git_action_find_usages", bundle: .appModule), systemImage: "magnifyingglass")
        }

        Button {
            onSendToChat?(GitPromptTemplates.suggestImprovementsFile(file.path))
        } label: {
            Label(String(localized: "git_action_suggest_improvements_file", bundle: .appModule), systemImage: "lightbulb")
        }

        Button {
            onSendToChat?(GitPromptTemplates.writeTestsFile(file.path))
        } label: {
            Label(String(localized: "git_action_write_tests", bundle: .appModule), systemImage: "checkmark.shield")
        }
    }

    // MARK: - Helpers

    private var fileIcon: String {
        FileTreeIcons.iconName(for: file)
    }

    private var fileIconColor: Color {
        FileTreeIcons.iconColor(for: file)
    }

    private func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Syntax Highlighter

/// Lightweight regex-based syntax highlighter for common languages.
/// Produces `AttributedString` per line with colors for keywords, strings, comments, numbers, types, etc.
enum GitSyntaxHighlighter {

    enum Language {
        case swift, php, javascript, python, ruby, go, rust, cLike, html, css, json, yaml, shell, markdown, plain
    }

    static func language(for filename: String) -> Language {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "php": return .php
        case "js", "jsx", "mjs": return .javascript
        case "ts", "tsx": return .javascript
        case "py": return .python
        case "rb": return .ruby
        case "go": return .go
        case "rs": return .rust
        case "c", "cpp", "h", "hpp", "m", "mm", "java", "kt", "cs": return .cLike
        case "html", "htm", "xml", "svg": return .html
        case "css", "scss", "less": return .css
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "sh", "bash", "zsh": return .shell
        case "md", "markdown": return .markdown
        default: return .plain
        }
    }

    /// Highlight an array of lines, returning an `AttributedString` per line.
    @MainActor
    static func highlight(lines: [String], language: Language) -> [AttributedString] {
        guard language != .plain else {
            return lines.map { line in
                var attr = AttributedString(line.isEmpty ? " " : line)
                attr.foregroundColor = .primary
                return attr
            }
        }

        // Track multi-line comment state
        var inBlockComment = false
        return lines.map { line in
            let (result, stillInComment) = highlightLine(line, language: language, inBlockComment: inBlockComment)
            inBlockComment = stillInComment
            return result
        }
    }

    // MARK: - Per-line Highlighting

    @MainActor
    private static func highlightLine(_ line: String, language: Language, inBlockComment: Bool) -> (AttributedString, Bool) {
        if line.isEmpty {
            var attr = AttributedString(" ")
            attr.foregroundColor = .primary
            return (attr, inBlockComment)
        }

        // If we're inside a block comment, color the whole line as comment
        var stillInBlock = inBlockComment
        if inBlockComment {
            if let endRange = line.range(of: "*/") {
                stillInBlock = false
                // Everything up to and including */ is comment, rest is code
                let commentPart = String(line[line.startIndex..<endRange.upperBound])
                let codePart = String(line[endRange.upperBound...])
                var result = coloredString(commentPart, .comment)
                if !codePart.isEmpty {
                    let (codeAttr, _) = highlightLine(codePart, language: language, inBlockComment: false)
                    result.append(codeAttr)
                }
                return (result, stillInBlock)
            } else {
                return (coloredString(line, .comment), true)
            }
        }

        // Check for block comment start
        if line.contains("/*") && !line.contains("*/") {
            stillInBlock = true
        }

        let rules = tokenRules(for: language)
        return (applyRules(to: line, rules: rules), stillInBlock)
    }

    // MARK: - Token Types

    enum TokenType {
        case keyword, type, string, comment, number, annotation, tag, attribute, property, plain
    }

    struct TokenRule {
        let pattern: String
        let type: TokenType
    }

    // MARK: - Language Rules

    private static func tokenRules(for language: Language) -> [TokenRule] {
        // Common patterns
        let singleLineComment: TokenRule
        let strings: [TokenRule]
        let numbers = TokenRule(pattern: #"\b\d+(\.\d+)?\b"#, type: .number)

        switch language {
        case .swift:
            singleLineComment = TokenRule(pattern: #"//.*$"#, type: .comment)
            strings = [
                TokenRule(pattern: #"""".*?""""#, type: .string),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
            ]
            return strings + [
                singleLineComment,
                TokenRule(pattern: #"/\*.*?\*/"#, type: .comment),
                TokenRule(pattern: #"@\w+"#, type: .annotation),
                TokenRule(pattern: #"\b(import|func|var|let|class|struct|enum|protocol|extension|return|if|else|guard|switch|case|default|for|while|repeat|break|continue|throw|throws|try|catch|async|await|in|where|is|as|self|Self|super|init|deinit|subscript|typealias|associatedtype|private|fileprivate|internal|public|open|static|override|mutating|nonmutating|lazy|weak|unowned|inout|some|any|actor|nonisolated|sending|consuming|borrowing|final|required|convenience|dynamic|optional|indirect|precedencegroup|operator|defer|do)\b"#, type: .keyword),
                TokenRule(pattern: #"\b(Int|String|Bool|Double|Float|Array|Dictionary|Set|Optional|Any|AnyObject|Void|Never|Error|Codable|Sendable|Identifiable|Equatable|Hashable|Comparable|View|Color|Date|Data|URL|Result|Task|MainActor|Observable|Published|State|Binding|Environment|ObservedObject|StateObject)\b"#, type: .type),
                TokenRule(pattern: #"\b(true|false|nil)\b"#, type: .keyword),
                numbers,
            ]
        case .php:
            singleLineComment = TokenRule(pattern: #"(//|#).*$"#, type: .comment)
            strings = [
                TokenRule(pattern: #"'(?:[^'\\]|\\.)*'"#, type: .string),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
            ]
            return strings + [
                singleLineComment,
                TokenRule(pattern: #"/\*.*?\*/"#, type: .comment),
                TokenRule(pattern: #"\$\w+"#, type: .property),
                TokenRule(pattern: #"\b(function|class|interface|trait|enum|extends|implements|abstract|final|public|private|protected|static|const|var|return|if|else|elseif|switch|case|default|for|foreach|while|do|break|continue|throw|try|catch|finally|new|use|namespace|require|require_once|include|include_once|echo|print|array|list|isset|unset|empty|die|exit|match|fn|yield|readonly)\b"#, type: .keyword),
                TokenRule(pattern: #"\b(true|false|null|TRUE|FALSE|NULL|self|parent|static)\b"#, type: .keyword),
                TokenRule(pattern: #"<\?php|\?>"#, type: .tag),
                numbers,
            ]
        case .javascript:
            singleLineComment = TokenRule(pattern: #"//.*$"#, type: .comment)
            strings = [
                TokenRule(pattern: #"`(?:[^`\\]|\\.)*`"#, type: .string),
                TokenRule(pattern: #"'(?:[^'\\]|\\.)*'"#, type: .string),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
            ]
            return strings + [
                singleLineComment,
                TokenRule(pattern: #"/\*.*?\*/"#, type: .comment),
                TokenRule(pattern: #"@\w+"#, type: .annotation),
                TokenRule(pattern: #"\b(import|export|from|const|let|var|function|class|extends|return|if|else|switch|case|default|for|while|do|break|continue|throw|try|catch|finally|new|delete|typeof|instanceof|in|of|async|await|yield|this|super|static|get|set|interface|type|enum|implements|declare|module|namespace|abstract|readonly)\b"#, type: .keyword),
                TokenRule(pattern: #"\b(true|false|null|undefined|NaN|Infinity)\b"#, type: .keyword),
                TokenRule(pattern: #"\b(Array|Object|String|Number|Boolean|Promise|Map|Set|Date|RegExp|Error|Function|Symbol|BigInt|Proxy|Reflect|WeakMap|WeakSet|Int8Array|Uint8Array|Float32Array|Float64Array|console|Math|JSON|window|document|globalThis|process|React|Component|useState|useEffect|useRef|useMemo|useCallback)\b"#, type: .type),
                numbers,
            ]
        case .python:
            singleLineComment = TokenRule(pattern: #"#.*$"#, type: .comment)
            strings = [
                TokenRule(pattern: #"\"\"\"[\s\S]*?\"\"\""#, type: .string),
                TokenRule(pattern: #"'''[\s\S]*?'''"#, type: .string),
                TokenRule(pattern: #"f"(?:[^"\\]|\\.)*""#, type: .string),
                TokenRule(pattern: #"'(?:[^'\\]|\\.)*'"#, type: .string),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
            ]
            return strings + [
                singleLineComment,
                TokenRule(pattern: #"@\w+"#, type: .annotation),
                TokenRule(pattern: #"\b(import|from|def|class|return|if|elif|else|for|while|break|continue|pass|raise|try|except|finally|with|as|yield|lambda|global|nonlocal|del|assert|async|await|and|or|not|is|in)\b"#, type: .keyword),
                TokenRule(pattern: #"\b(True|False|None|self|cls)\b"#, type: .keyword),
                TokenRule(pattern: #"\b(int|str|float|bool|list|dict|set|tuple|bytes|type|object|Exception|print|len|range|enumerate|zip|map|filter|sorted|any|all|super|property|staticmethod|classmethod|dataclass)\b"#, type: .type),
                numbers,
            ]
        case .ruby:
            singleLineComment = TokenRule(pattern: #"#.*$"#, type: .comment)
            strings = [
                TokenRule(pattern: #"'(?:[^'\\]|\\.)*'"#, type: .string),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
            ]
            return strings + [
                singleLineComment,
                TokenRule(pattern: #"\b(def|class|module|end|return|if|elsif|else|unless|case|when|for|while|until|do|break|next|redo|retry|begin|rescue|ensure|raise|yield|include|extend|require|require_relative|attr_accessor|attr_reader|attr_writer|private|protected|public|self|super|block_given\?)\b"#, type: .keyword),
                TokenRule(pattern: #"\b(true|false|nil)\b"#, type: .keyword),
                TokenRule(pattern: #":\w+"#, type: .string),
                numbers,
            ]
        case .go:
            singleLineComment = TokenRule(pattern: #"//.*$"#, type: .comment)
            strings = [
                TokenRule(pattern: #"`[^`]*`"#, type: .string),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
            ]
            return strings + [
                singleLineComment,
                TokenRule(pattern: #"/\*.*?\*/"#, type: .comment),
                TokenRule(pattern: #"\b(package|import|func|var|const|type|struct|interface|return|if|else|switch|case|default|for|range|break|continue|go|select|chan|defer|map|make|new|append|len|cap|delete|copy|close|panic|recover|fallthrough)\b"#, type: .keyword),
                TokenRule(pattern: #"\b(true|false|nil|iota)\b"#, type: .keyword),
                TokenRule(pattern: #"\b(int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|complex64|complex128|string|bool|byte|rune|error|any|comparable)\b"#, type: .type),
                numbers,
            ]
        case .rust:
            singleLineComment = TokenRule(pattern: #"//.*$"#, type: .comment)
            strings = [
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
            ]
            return strings + [
                singleLineComment,
                TokenRule(pattern: #"/\*.*?\*/"#, type: .comment),
                TokenRule(pattern: #"#\[.*?\]"#, type: .annotation),
                TokenRule(pattern: #"\b(fn|let|mut|const|static|struct|enum|impl|trait|pub|use|mod|crate|self|Self|super|return|if|else|match|for|while|loop|break|continue|where|as|in|ref|move|async|await|unsafe|extern|type|dyn|macro_rules)\b"#, type: .keyword),
                TokenRule(pattern: #"\b(true|false|None|Some|Ok|Err)\b"#, type: .keyword),
                TokenRule(pattern: #"\b(i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|char|str|String|Vec|Box|Option|Result|HashMap|HashSet|Rc|Arc|Cell|RefCell|Mutex|Send|Sync|Clone|Copy|Debug|Display|Default|Iterator|From|Into|AsRef|AsMut)\b"#, type: .type),
                numbers,
            ]
        case .cLike:
            singleLineComment = TokenRule(pattern: #"//.*$"#, type: .comment)
            strings = [
                TokenRule(pattern: #"'(?:[^'\\]|\\.)*'"#, type: .string),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
            ]
            return strings + [
                singleLineComment,
                TokenRule(pattern: #"/\*.*?\*/"#, type: .comment),
                TokenRule(pattern: #"#\w+"#, type: .annotation),
                TokenRule(pattern: #"\b(auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto|if|inline|int|long|register|restrict|return|short|signed|sizeof|static|struct|switch|typedef|union|unsigned|void|volatile|while|class|namespace|using|template|typename|virtual|override|public|private|protected|new|delete|throw|try|catch|this|nullptr|true|false|NULL|import|package|final|abstract|interface|implements|extends|synchronized|native|transient)\b"#, type: .keyword),
                numbers,
            ]
        case .html:
            return [
                TokenRule(pattern: #"<!--.*?-->"#, type: .comment),
                TokenRule(pattern: #"</?[a-zA-Z][a-zA-Z0-9]*"#, type: .tag),
                TokenRule(pattern: #"/>"#, type: .tag),
                TokenRule(pattern: #">"#, type: .tag),
                TokenRule(pattern: #"\b[a-zA-Z-]+=(?=")"#, type: .attribute),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
                TokenRule(pattern: #"'(?:[^'\\]|\\.)*'"#, type: .string),
                TokenRule(pattern: #"&\w+;"#, type: .keyword),
            ]
        case .css:
            return [
                TokenRule(pattern: #"/\*.*?\*/"#, type: .comment),
                TokenRule(pattern: #"[.#][\w-]+"#, type: .type),
                TokenRule(pattern: #"@\w+"#, type: .keyword),
                TokenRule(pattern: #"\b(important|inherit|initial|unset|none|auto|flex|grid|block|inline|relative|absolute|fixed|sticky)\b"#, type: .keyword),
                TokenRule(pattern: #"[\w-]+(?=\s*:)"#, type: .property),
                TokenRule(pattern: #"'(?:[^'\\]|\\.)*'"#, type: .string),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
                TokenRule(pattern: #"#[0-9a-fA-F]{3,8}\b"#, type: .number),
                TokenRule(pattern: #"\b\d+(\.\d+)?(px|em|rem|%|vh|vw|s|ms|deg|fr)?\b"#, type: .number),
            ]
        case .json:
            return [
                TokenRule(pattern: #""(?:[^"\\]|\\.)*"\s*(?=:)"#, type: .property),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
                TokenRule(pattern: #"\b(true|false|null)\b"#, type: .keyword),
                TokenRule(pattern: #"-?\b\d+(\.\d+)?([eE][+-]?\d+)?\b"#, type: .number),
            ]
        case .yaml:
            return [
                TokenRule(pattern: #"#.*$"#, type: .comment),
                TokenRule(pattern: #"^[\w.-]+(?=\s*:)"#, type: .property),
                TokenRule(pattern: #"'(?:[^'\\]|\\.)*'"#, type: .string),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
                TokenRule(pattern: #"\b(true|false|null|yes|no|on|off)\b"#, type: .keyword),
                TokenRule(pattern: #"\b\d+(\.\d+)?\b"#, type: .number),
            ]
        case .shell:
            return [
                TokenRule(pattern: #"#.*$"#, type: .comment),
                TokenRule(pattern: #"'(?:[^'\\]|\\.)*'"#, type: .string),
                TokenRule(pattern: #""(?:[^"\\]|\\.)*""#, type: .string),
                TokenRule(pattern: #"\$\{?\w+\}?"#, type: .property),
                TokenRule(pattern: #"\b(if|then|else|elif|fi|for|while|until|do|done|case|esac|in|function|return|local|export|source|echo|exit|set|unset|shift|readonly|declare|typeset|eval|exec|trap|wait|cd|pwd|ls|cat|grep|sed|awk|find|xargs|sort|uniq|wc|head|tail|cut|tr|tee|chmod|chown|mkdir|rm|cp|mv|ln|test)\b"#, type: .keyword),
                TokenRule(pattern: #"\b\d+\b"#, type: .number),
            ]
        case .markdown:
            return [
                TokenRule(pattern: #"^#{1,6}\s.*$"#, type: .keyword),
                TokenRule(pattern: #"`[^`]+`"#, type: .string),
                TokenRule(pattern: #"\*\*[^*]+\*\*"#, type: .keyword),
                TokenRule(pattern: #"\*[^*]+\*"#, type: .type),
                TokenRule(pattern: #"\[.*?\]\(.*?\)"#, type: .string),
                TokenRule(pattern: #"^[-*+]\s"#, type: .keyword),
                TokenRule(pattern: #"^>\s"#, type: .comment),
            ]
        case .plain:
            return []
        }
    }

    // MARK: - Apply Rules

    @MainActor
    private static func applyRules(to line: String, rules: [TokenRule]) -> AttributedString {
        guard !line.isEmpty else {
            var attr = AttributedString(" ")
            attr.foregroundColor = .primary
            return attr
        }

        // Use Array<Character> for safe integer indexing
        let chars = Array(line)
        let charCount = chars.count
        var colorMap = Array(repeating: TokenType.plain, count: charCount)

        // Build a UTF-16 offset → character index mapping
        let utf16View = line.utf16
        var utf16ToChar = [Int: Int]()
        var charIdx = 0
        var utf16Idx = utf16View.startIndex
        while utf16Idx < utf16View.endIndex {
            let offset = utf16View.distance(from: utf16View.startIndex, to: utf16Idx)
            utf16ToChar[offset] = charIdx
            charIdx += 1
            let stringIdx = String.Index(utf16Idx, within: line) ?? line.startIndex
            let nextStringIdx = line.index(after: stringIdx)
            utf16Idx = nextStringIdx.samePosition(in: utf16View) ?? utf16View.endIndex
        }

        let nsLine = line as NSString
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) else { continue }
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                let nsRange = match.range
                guard nsRange.location != NSNotFound else { continue }
                // Convert UTF-16 range to character indices
                guard let startChar = utf16ToChar[nsRange.location] else { continue }
                let nsEnd = nsRange.location + nsRange.length
                // Find the end character index
                let endChar: Int
                if let ec = utf16ToChar[nsEnd] {
                    endChar = ec
                } else {
                    endChar = charCount // end of string
                }
                let safeEnd = min(endChar, charCount)
                for i in startChar..<safeEnd {
                    if colorMap[i] == .plain {
                        colorMap[i] = rule.type
                    }
                }
            }
        }

        // Build attributed string from runs of same token type
        var result = AttributedString()
        var runStart = 0

        while runStart < charCount {
            let runType = colorMap[runStart]
            var runEnd = runStart + 1
            while runEnd < charCount && colorMap[runEnd] == runType {
                runEnd += 1
            }
            let text = String(chars[runStart..<runEnd])
            var attr = AttributedString(text)
            attr.foregroundColor = color(for: runType)
            result.append(attr)
            runStart = runEnd
        }

        return result
    }

    // MARK: - Colors

    @MainActor
    private static var isLightTheme: Bool {
        ThemeManager.shared.selectedPreset.isDark == false
    }

    @MainActor
    private static func color(for type: TokenType) -> Color {
        if isLightTheme {
            return lightColor(for: type)
        } else {
            return darkColor(for: type)
        }
    }

    // Dark theme colors
    private static func darkColor(for type: TokenType) -> Color {
        switch type {
        case .keyword: return Color(nsColor: NSColor(red: 0.78, green: 0.35, blue: 0.78, alpha: 1.0)) // purple
        case .type: return Color(nsColor: NSColor(red: 0.31, green: 0.72, blue: 0.85, alpha: 1.0)) // cyan
        case .string: return Color(nsColor: NSColor(red: 0.80, green: 0.55, blue: 0.33, alpha: 1.0)) // orange
        case .comment: return Color(nsColor: NSColor(red: 0.45, green: 0.50, blue: 0.45, alpha: 1.0)) // gray-green
        case .number: return Color(nsColor: NSColor(red: 0.68, green: 0.82, blue: 0.45, alpha: 1.0)) // light green
        case .annotation: return Color(nsColor: NSColor(red: 0.90, green: 0.72, blue: 0.30, alpha: 1.0)) // gold
        case .tag: return Color(nsColor: NSColor(red: 0.30, green: 0.65, blue: 0.85, alpha: 1.0)) // blue
        case .attribute: return Color(nsColor: NSColor(red: 0.56, green: 0.78, blue: 0.45, alpha: 1.0)) // green
        case .property: return Color(nsColor: NSColor(red: 0.50, green: 0.69, blue: 0.89, alpha: 1.0)) // light blue
        case .plain: return .primary
        }
    }

    // Light theme colors (high contrast on light backgrounds)
    private static func lightColor(for type: TokenType) -> Color {
        switch type {
        case .keyword: return Color(nsColor: NSColor(red: 0.55, green: 0.08, blue: 0.69, alpha: 1.0)) // dark purple
        case .type: return Color(nsColor: NSColor(red: 0.00, green: 0.50, blue: 0.65, alpha: 1.0)) // dark cyan
        case .string: return Color(nsColor: NSColor(red: 0.60, green: 0.32, blue: 0.05, alpha: 1.0)) // dark orange
        case .comment: return Color(nsColor: NSColor(red: 0.42, green: 0.45, blue: 0.42, alpha: 1.0)) // gray-green
        case .number: return Color(nsColor: NSColor(red: 0.15, green: 0.50, blue: 0.13, alpha: 1.0)) // dark green
        case .annotation: return Color(nsColor: NSColor(red: 0.68, green: 0.52, blue: 0.00, alpha: 1.0)) // dark gold
        case .tag: return Color(nsColor: NSColor(red: 0.00, green: 0.38, blue: 0.72, alpha: 1.0)) // dark blue
        case .attribute: return Color(nsColor: NSColor(red: 0.22, green: 0.50, blue: 0.15, alpha: 1.0)) // dark green
        case .property: return Color(nsColor: NSColor(red: 0.10, green: 0.40, blue: 0.70, alpha: 1.0)) // dark blue
        case .plain: return .primary
        }
    }

    // MARK: - Helper

    @MainActor
    private static func coloredString(_ text: String, _ type: TokenType) -> AttributedString {
        var attr = AttributedString(text)
        attr.foregroundColor = color(for: type)
        return attr
    }
}
