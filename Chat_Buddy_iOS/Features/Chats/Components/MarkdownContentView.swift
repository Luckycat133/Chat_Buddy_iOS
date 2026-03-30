import SwiftUI

/// Renders Markdown-like content with code blocks, inline code, bold, italic, and links.
/// Lightweight on-device renderer (no external dependencies).
struct MarkdownContentView: View {
    let text: String
    let isUser: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let str):
                    formattedText(str)
                case .codeBlock(let lang, let code):
                    codeBlockView(language: lang, code: code)
                case .inlineCode(let code):
                    Text(code)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                }
            }
        }
    }

    // MARK: - Block Types

    private enum Block {
        case text(String)
        case codeBlock(language: String, code: String)
        case inlineCode(String)
    }

    // MARK: - Parsing

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var textBuffer = ""

        while i < lines.count {
            let line = lines[i]

            // Fenced code block: ```lang ... ```
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                // Flush text buffer
                if !textBuffer.isEmpty {
                    blocks.append(.text(textBuffer.trimmingCharacters(in: .newlines)))
                    textBuffer = ""
                }

                let langLine = line.trimmingCharacters(in: .whitespaces).dropFirst(3)
                let language = String(langLine).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1

                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }

                let code = codeLines.joined(separator: "\n")
                blocks.append(.codeBlock(language: language, code: code))
            } else {
                textBuffer += (textBuffer.isEmpty ? "" : "\n") + line
            }

            i += 1
        }

        if !textBuffer.isEmpty {
            blocks.append(.text(textBuffer.trimmingCharacters(in: .newlines)))
        }

        return blocks
    }

    // MARK: - Formatted Text

    @ViewBuilder
    private func formattedText(_ str: String) -> some View {
        let attributed = buildAttributedString(str)
        Text(attributed)
            .foregroundStyle(isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .textSelection(.enabled)
    }

    private func buildAttributedString(_ str: String) -> AttributedString {
        var result = AttributedString()
        let scanner = str[str.startIndex...]
        var current = scanner.startIndex
        let end = scanner.endIndex

        while current < end {
            // Inline code: `code`
            if scanner[current] == "`" {
                let afterTick = scanner.index(after: current)
                if afterTick < end, let closingTick = scanner[afterTick...].firstIndex(of: "`") {
                    let codeStr = String(scanner[afterTick..<closingTick])
                    var attr = AttributedString(codeStr)
                    attr.font = .system(size: 13, design: .monospaced)
                    attr.backgroundColor = .secondary.opacity(0.15)
                    result.append(attr)
                    current = scanner.index(after: closingTick)
                    continue
                }
            }

            // Bold: **text**
            if scanner[current] == "*",
               scanner.index(after: current) < end,
               scanner[scanner.index(after: current)] == "*" {
                let afterStars = scanner.index(current, offsetBy: 2)
                if afterStars < end,
                   let closing = scanner[afterStars...].range(of: "**") {
                    let boldStr = String(scanner[afterStars..<closing.lowerBound])
                    var attr = AttributedString(boldStr)
                    attr.font = .body.bold()
                    result.append(attr)
                    current = closing.upperBound
                    continue
                }
            }

            // Regular character
            result.append(AttributedString(String(scanner[current])))
            current = scanner.index(after: current)
        }

        return result
    }

    // MARK: - Code Block

    private func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language label and copy button
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(DSTypography.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, 4)
            .background(Color(uiColor: .systemGray5))

            // Code content with basic syntax coloring
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightSyntax(code, language: language))
                    .font(.system(size: 12, design: .monospaced))
                    .padding(DSSpacing.sm)
                    .textSelection(.enabled)
            }
        }
        .background(Color(uiColor: .systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
    }

    /// Lightweight keyword-based syntax highlighting using AttributedString.
    private func highlightSyntax(_ code: String, language: String) -> AttributedString {
        var result = AttributedString(code)

        let keywords: [String]
        switch language.lowercased() {
        case "swift":
            keywords = ["func", "let", "var", "class", "struct", "enum", "import", "return",
                        "if", "else", "guard", "switch", "case", "for", "while", "in",
                        "true", "false", "nil", "self", "private", "public", "static",
                        "async", "await", "throws", "try", "catch"]
        case "javascript", "js", "typescript", "ts":
            keywords = ["function", "const", "let", "var", "return", "if", "else",
                        "for", "while", "class", "import", "export", "default",
                        "async", "await", "try", "catch", "new", "this", "true", "false", "null"]
        case "python", "py":
            keywords = ["def", "class", "import", "from", "return", "if", "elif", "else",
                        "for", "while", "in", "try", "except", "with", "as", "True", "False", "None",
                        "async", "await", "yield", "lambda", "self"]
        default:
            keywords = ["function", "return", "if", "else", "for", "while", "class",
                        "true", "false", "null", "import", "export"]
        }

        for kw in keywords {
            var search = result.startIndex
            while search < result.endIndex {
                guard let range = result[search...].range(of: kw) else { break }
                // Only highlight if it's a word boundary
                let before = range.lowerBound == result.startIndex
                let after = range.upperBound == result.endIndex
                if (before || !String(result.characters[result.index(before: range.lowerBound)]).first!.isLetter)
                    && (after || !String(result.characters[range.upperBound]).first!.isLetter) {
                    result[range].foregroundColor = .purple
                    result[range].font = .system(size: 12, weight: .semibold, design: .monospaced)
                }
                search = range.upperBound
            }
        }

        // Highlight strings (basic double-quote detection)
        var sIdx = result.startIndex
        while sIdx < result.endIndex {
            guard let openQuote = result[sIdx...].range(of: "\"") else { break }
            let afterOpen = openQuote.upperBound
            if afterOpen < result.endIndex, let closeQuote = result[afterOpen...].range(of: "\"") {
                let fullRange = openQuote.lowerBound..<closeQuote.upperBound
                result[fullRange].foregroundColor = .green
                sIdx = closeQuote.upperBound
            } else {
                break
            }
        }

        // Highlight comments (// style)
        let codeLines = code.components(separatedBy: "\n")
        var offset = result.startIndex
        for line in codeLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                if let commentRange = result[offset...].range(of: line) {
                    result[commentRange].foregroundColor = .gray
                }
            }
            // Move offset past this line
            if let lineRange = result[offset...].range(of: line) {
                offset = lineRange.upperBound
            }
        }

        return result
    }
}
