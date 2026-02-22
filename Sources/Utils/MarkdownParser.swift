import Foundation
import AppKit

final class MarkdownParser {
    static let shared = MarkdownParser()

    private init() {}

    private struct Theme {
        let baseFont = NSFont.systemFont(ofSize: 16)
        let textColor = NSColor.labelColor
        let secondaryColor = NSColor.secondaryLabelColor
        let accentColor = NSColor.systemBlue
        let borderColor = NSColor.separatorColor
        let inlineCodeBackground = NSColor.black.withAlphaComponent(0.06)
        let codeBlockBackground = NSColor(calibratedRed: 0.118, green: 0.118, blue: 0.18, alpha: 1.0)
        let codeBlockText = NSColor(calibratedRed: 0.804, green: 0.839, blue: 0.957, alpha: 1.0)
        let quoteBackground = NSColor.systemBlue.withAlphaComponent(0.04)
    }

    private let theme = Theme()

    func parse(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")

        var index = 0
        var inCodeBlock = false
        var fenceChar: Character?
        var fenceLen = 0
        var codeLines: [String] = []

        while index < lines.count {
            let line = lines[index]

            if let fence = parseFenceToken(line) {
                if !inCodeBlock {
                    inCodeBlock = true
                    fenceChar = fence.char
                    fenceLen = fence.len
                    codeLines.removeAll(keepingCapacity: true)
                } else if fence.char == fenceChar && fence.len >= fenceLen {
                    appendBlock(result, makeCodeBlock(codeLines.joined(separator: "\n")))
                    inCodeBlock = false
                    fenceChar = nil
                    fenceLen = 0
                    codeLines.removeAll(keepingCapacity: true)
                } else {
                    codeLines.append(line)
                }
                index += 1
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                index += 1
                continue
            }

            if let table = parseTable(lines: lines, startAt: index) {
                appendBlock(result, makeTable(table))
                index = table.nextIndex
                continue
            }

            if let heading = parseHeading(line) {
                appendBlock(result, makeHeading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isHorizontalRule(line) {
                appendBlock(result, makeHorizontalRule())
                index += 1
                continue
            }

            if isListItem(line) {
                let grouped = collectList(lines: lines, startAt: index)
                appendBlock(result, makeList(lines: grouped.items))
                index = grouped.nextIndex
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                let grouped = collectQuote(lines: lines, startAt: index)
                appendBlock(result, makeBlockQuote(lines: grouped.items))
                index = grouped.nextIndex
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            let grouped = collectParagraph(lines: lines, startAt: index)
            appendBlock(result, makeParagraph(grouped.items.joined(separator: " ")))
            index = grouped.nextIndex
        }

        if inCodeBlock, !codeLines.isEmpty {
            appendBlock(result, makeCodeBlock(codeLines.joined(separator: "\n")))
        }

        return result
    }

    private func appendBlock(_ result: NSMutableAttributedString, _ block: NSAttributedString) {
        if result.length > 0 {
            result.append(NSAttributedString(string: "\n"))
        }
        result.append(block)
    }

    private func parseFenceToken(_ line: String) -> (char: Character, len: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            return ("`", trimmed.prefix { $0 == "`" }.count)
        }
        if trimmed.hasPrefix("~~~") {
            return ("~", trimmed.prefix { $0 == "~" }.count)
        }
        return nil
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }

        let level = min(6, trimmed.prefix { $0 == "#" }.count)
        guard level > 0 else { return nil }

        let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let token = line.trimmingCharacters(in: .whitespaces)
        return token == "---" || token == "***" || token == "___"
    }

    private func isListItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") { return true }
        if let regex = try? NSRegularExpression(pattern: #"^\d+\.\s+"#) {
            let ns = trimmed as NSString
            return regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) != nil
        }
        return false
    }

    private func collectParagraph(lines: [String], startAt: Int) -> (items: [String], nextIndex: Int) {
        var index = startAt
        var values: [String] = []
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || parseHeading(line) != nil || isHorizontalRule(line) || isListItem(line) ||
                trimmed.hasPrefix(">") || parseFenceToken(line) != nil || parseTable(lines: lines, startAt: index) != nil {
                break
            }
            values.append(trimmed)
            index += 1
        }
        return (values, index)
    }

    private func collectQuote(lines: [String], startAt: Int) -> (items: [String], nextIndex: Int) {
        var index = startAt
        var values: [String] = []
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            values.append(body)
            index += 1
        }
        return (values, index)
    }

    private func collectList(lines: [String], startAt: Int) -> (items: [String], nextIndex: Int) {
        var index = startAt
        var values: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            if isListItem(line) || line.hasPrefix("  ") || line.hasPrefix("\t") {
                values.append(line)
                index += 1
            } else {
                break
            }
        }
        return (values, index)
    }

    private struct ParsedTable {
        let headers: [String]
        let alignments: [NSTextAlignment]
        let rows: [[String]]
        let nextIndex: Int
    }

    private func parseTable(lines: [String], startAt index: Int) -> ParsedTable? {
        guard index + 1 < lines.count,
              let headerCells = parseTableCells(lines[index]),
              let alignments = parseTableSeparator(lines[index + 1]) else {
            return nil
        }

        var rows: [[String]] = []
        var scan = index + 2
        while scan < lines.count {
            guard let cells = parseTableCells(lines[scan]) else { break }
            rows.append(cells)
            scan += 1
        }

        return ParsedTable(headers: headerCells, alignments: alignments, rows: rows, nextIndex: scan)
    }

    private func parseTableCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }

        var content = trimmed
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }

        let cells = content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        return cells.count >= 2 ? cells : nil
    }

    private func parseTableSeparator(_ line: String) -> [NSTextAlignment]? {
        guard let cells = parseTableCells(line), !cells.isEmpty else { return nil }
        var alignments: [NSTextAlignment] = []

        for cell in cells {
            let token = cell.replacingOccurrences(of: " ", with: "")
            let dashCount = token.filter { $0 == "-" }.count
            guard dashCount >= 3 else { return nil }
            guard token.allSatisfy({ $0 == "-" || $0 == ":" }) else { return nil }

            let left = token.first == ":"
            let right = token.last == ":"
            if left && right {
                alignments.append(.center)
            } else if right {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }

        return alignments
    }

    private func makeHeading(level: Int, text: String) -> NSAttributedString {
        let sizes: [CGFloat] = [26, 23, 21, 19, 17, 16]
        let font = NSFont.systemFont(ofSize: sizes[min(level - 1, sizes.count - 1)], weight: .semibold)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 6

        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: theme.textColor,
            .paragraphStyle: style
        ])
    }

    private func makeParagraph(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(attributedString: makeInline(text, baseFont: theme.baseFont, color: theme.textColor))
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        attributed.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: attributed.length))
        return attributed
    }

    private func makeBlockQuote(lines: [String]) -> NSAttributedString {
        let text = lines.joined(separator: "\n")
        let body = NSMutableAttributedString(attributedString: makeInline(text, baseFont: theme.baseFont, color: theme.secondaryColor))
        let style = NSMutableParagraphStyle()
        style.headIndent = 14
        style.firstLineHeadIndent = 14
        style.paragraphSpacing = 4

        let quoteMarker = NSAttributedString(string: "▎ ", attributes: [
            .font: theme.baseFont,
            .foregroundColor: theme.accentColor,
            .paragraphStyle: style
        ])

        body.addAttributes([
            .paragraphStyle: style,
            .backgroundColor: theme.quoteBackground
        ], range: NSRange(location: 0, length: body.length))

        let result = NSMutableAttributedString()
        result.append(quoteMarker)
        result.append(body)
        return result
    }

    private func makeCodeBlock(_ code: String) -> NSAttributedString {
        let display = code.isEmpty ? " " : code
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        style.firstLineHeadIndent = 10
        style.headIndent = 10

        return NSAttributedString(string: display, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: theme.codeBlockText,
            .backgroundColor: theme.codeBlockBackground,
            .paragraphStyle: style
        ])
    }

    private func makeHorizontalRule() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        return NSAttributedString(string: String(repeating: "─", count: 44), attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: theme.borderColor,
            .paragraphStyle: style
        ])
    }

    private func makeList(lines: [String]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (idx, line) in lines.enumerated() {
            if idx > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            let rendered = renderListLine(line)
            result.append(rendered)
        }
        return result
    }

    private func renderListLine(_ line: String) -> NSAttributedString {
        let indentCount = line.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let indent = String(repeating: " ", count: indentCount)

        if let regex = try? NSRegularExpression(pattern: #"^([-+*])\s+\[( |x|X)\]\s*(.*)$"#) {
            let ns = trimmed as NSString
            if let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges == 4 {
                let check = ns.substring(with: match.range(at: 2)).lowercased() == "x" ? "☑" : "☐"
                let content = ns.substring(with: match.range(at: 3))
                return makeInline(indent + check + " " + content, baseFont: theme.baseFont, color: theme.textColor)
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"^(\d+)\.\s+(.*)$"#) {
            let ns = trimmed as NSString
            if let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges == 3 {
                let number = ns.substring(with: match.range(at: 1))
                let content = ns.substring(with: match.range(at: 2))
                return makeInline(indent + number + ". " + content, baseFont: theme.baseFont, color: theme.textColor)
            }
        }

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            let content = String(trimmed.dropFirst(2))
            return makeInline(indent + "• " + content, baseFont: theme.baseFont, color: theme.textColor)
        }

        return makeInline(line, baseFont: theme.baseFont, color: theme.textColor)
    }

    private func makeTable(_ table: ParsedTable) -> NSAttributedString {
        let colCount = max(table.headers.count, table.alignments.count, table.rows.map { $0.count }.max() ?? 0)
        let headers = padCells(table.headers, to: colCount)
        let alignments = padAlignments(table.alignments, to: colCount)
        let rows = table.rows.map { padCells($0, to: colCount) }

        var widths = Array(repeating: 3, count: colCount)
        for row in [headers] + rows {
            for col in 0..<colCount {
                widths[col] = max(widths[col], row[col].count)
            }
        }

        let output = NSMutableAttributedString()
        let headerText = renderTableRow(cells: headers, widths: widths, alignments: alignments)
        output.append(NSAttributedString(string: headerText + "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: theme.textColor
        ]))

        output.append(NSAttributedString(string: renderTableDivider(widths: widths, alignments: alignments), attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: theme.secondaryColor
        ]))

        for row in rows {
            output.append(NSAttributedString(string: "\n" + renderTableRow(cells: row, widths: widths, alignments: alignments), attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: theme.textColor
            ]))
        }

        return output
    }

    private func renderTableRow(cells: [String], widths: [Int], alignments: [NSTextAlignment]) -> String {
        var pieces: [String] = []
        for i in 0..<widths.count {
            pieces.append(alignCell(cells[i], width: widths[i], alignment: alignments[i]))
        }
        return "| " + pieces.joined(separator: " | ") + " |"
    }

    private func renderTableDivider(widths: [Int], alignments: [NSTextAlignment]) -> String {
        var pieces: [String] = []
        for i in 0..<widths.count {
            let width = max(3, widths[i])
            switch alignments[i] {
            case .center:
                pieces.append(":" + String(repeating: "-", count: max(1, width - 2)) + ":")
            case .right:
                pieces.append(String(repeating: "-", count: max(1, width - 1)) + ":")
            default:
                pieces.append(String(repeating: "-", count: width))
            }
        }
        return "| " + pieces.joined(separator: " | ") + " |"
    }

    private func alignCell(_ text: String, width: Int, alignment: NSTextAlignment) -> String {
        let padding = max(0, width - text.count)
        switch alignment {
        case .center:
            let left = padding / 2
            let right = padding - left
            return String(repeating: " ", count: left) + text + String(repeating: " ", count: right)
        case .right:
            return String(repeating: " ", count: padding) + text
        default:
            return text + String(repeating: " ", count: padding)
        }
    }

    private func padCells(_ cells: [String], to count: Int) -> [String] {
        guard cells.count < count else { return Array(cells.prefix(count)) }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private func padAlignments(_ alignments: [NSTextAlignment], to count: Int) -> [NSTextAlignment] {
        guard alignments.count < count else { return Array(alignments.prefix(count)) }
        return alignments + Array(repeating: .left, count: count - alignments.count)
    }

    private func makeInline(_ text: String, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let output = NSMutableAttributedString(string: text, attributes: [
            .font: baseFont,
            .foregroundColor: color
        ])

        applyInlineReplacement(pattern: #"`([^`]+)`"#, in: output) { content in
            NSAttributedString(string: content, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: color,
                .backgroundColor: theme.inlineCodeBackground
            ])
        }

        applyInlineReplacement(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, in: output) { content in
            NSAttributedString(string: content, attributes: [
                .font: baseFont,
                .foregroundColor: theme.accentColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ])
        }

        applyInlineReplacement(pattern: #"\*\*(.+?)\*\*"#, in: output) { content in
            NSAttributedString(string: content, attributes: [
                .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold),
                .foregroundColor: color
            ])
        }

        applyInlineReplacement(pattern: #"__(.+?)__"#, in: output) { content in
            NSAttributedString(string: content, attributes: [
                .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold),
                .foregroundColor: color
            ])
        }

        applyInlineReplacement(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, in: output) { content in
            NSAttributedString(string: content, attributes: [
                .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .regular).italic(),
                .foregroundColor: color
            ])
        }

        applyInlineReplacement(pattern: #"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#, in: output) { content in
            NSAttributedString(string: content, attributes: [
                .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .regular).italic(),
                .foregroundColor: color
            ])
        }

        applyInlineReplacement(pattern: #"~~(.+?)~~"#, in: output) { content in
            NSAttributedString(string: content, attributes: [
                .font: baseFont,
                .foregroundColor: color,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ])
        }

        return output
    }

    private func applyInlineReplacement(
        pattern: String,
        in text: NSMutableAttributedString,
        replacement: (String) -> NSAttributedString
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let plain = text.string
        let fullRange = NSRange(location: 0, length: (plain as NSString).length)
        let matches = regex.matches(in: plain, range: fullRange)

        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let full = match.range(at: 0)
            let content = match.range(at: 1)
            guard full.location != NSNotFound, content.location != NSNotFound else { continue }
            let raw = (plain as NSString).substring(with: content)
            text.replaceCharacters(in: full, with: replacement(raw))
        }
    }
}

private extension NSFont {
    func italic() -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
