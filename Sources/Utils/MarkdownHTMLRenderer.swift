import Foundation

final class MarkdownHTMLRenderer {
    static let shared = MarkdownHTMLRenderer()

    private init() {}

    func renderDocument(_ markdown: String) -> String {
        let body = renderBody(markdown)
        return renderHTML(body: body, isFragment: false, renderKey: nil)
    }

    func renderFragment(_ markdown: String, renderKey: String? = nil) -> String {
        let body = renderBody(markdown.isEmpty ? " " : markdown)
        return renderHTML(body: body, isFragment: true, renderKey: renderKey)
    }

    private func renderHTML(body: String, isFragment: Bool, renderKey: String?) -> String {
        let pagePadding = isFragment ? "0" : "30px 56px 44px"
        let pageWidth = isFragment ? "100%" : "920px"
        let overflow = isFragment ? "hidden" : "auto"
        let bodyAttr = renderKey.map { " data-render-key=\"\($0)\"" } ?? ""
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset=\"utf-8\" />
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
          <style>
            :root {
              --text-primary: #111827;
              --text-secondary: #4b5563;
              --accent-color: #0b74ff;
              --border-color: #d1d5db;
              --bg: #ffffff;
            }
            html, body {
              margin: 0;
              padding: 0;
              background: var(--bg);
              color: var(--text-primary);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              overflow: \(overflow);
            }
            .page {
              max-width: \(pageWidth);
              margin: 0 auto;
              padding: \(pagePadding);
            }
            .markdown-body {
              display: flow-root;
              line-height: 1.58;
              word-wrap: break-word;
              overflow-wrap: break-word;
              font-size: 16px;
            }
            .markdown-body > :first-child { margin-top: 0 !important; }
            .markdown-body > :last-child { margin-bottom: 0 !important; }
            .markdown-body p { margin: 0 0 0.55em; }
            .markdown-body h1,
            .markdown-body h2,
            .markdown-body h3,
            .markdown-body h4,
            .markdown-body h5,
            .markdown-body h6 {
              margin: 0.65em 0 0.25em;
              font-weight: 600;
              line-height: 1.3;
            }
            .markdown-body h1 { font-size: 1.3em; }
            .markdown-body h2 { font-size: 1.15em; }
            .markdown-body h3 { font-size: 1.05em; }
            .markdown-body h4,
            .markdown-body h5,
            .markdown-body h6 { font-size: 1em; }
            .markdown-body h1:first-child,
            .markdown-body h2:first-child,
            .markdown-body h3:first-child,
            .markdown-body h4:first-child,
            .markdown-body h5:first-child,
            .markdown-body h6:first-child { margin-top: 0; }
            .markdown-body ul,
            .markdown-body ol {
              margin: 0.25em 0;
              padding-left: 1.35em;
            }
            .markdown-body li { margin: 0.1em 0; }
            .markdown-body li:last-child { margin-bottom: 0; }
            .markdown-body li > p { margin: 0; }
            .markdown-body blockquote {
              margin: 0.45em 0;
              padding: 0.42em 0.9em;
              border-left: 3px solid var(--accent-color);
              background: rgba(11, 116, 255, 0.05);
              border-radius: 0 6px 6px 0;
              color: var(--text-secondary);
            }
            .markdown-body blockquote p { margin: 0; }
            .markdown-body code {
              background: rgba(0, 0, 0, 0.06);
              padding: 2px 6px;
              border-radius: 4px;
              font-size: 0.88em;
              font-family: 'SF Mono', 'Fira Code', 'Consolas', monospace;
            }
            .markdown-body pre {
              margin: 0.45em 0;
              padding: 14px 16px;
              background: #1e1e2e;
              color: #cdd6f4;
              border-radius: 10px;
              overflow-x: auto;
              font-size: 0.84em;
              line-height: 1.5;
            }
            .markdown-body pre code {
              background: none;
              padding: 0;
              color: inherit;
              font-size: inherit;
            }
            .markdown-body table {
              width: 100%;
              border-collapse: collapse;
              margin: 0.55em 0;
              font-size: 0.9em;
            }
            .markdown-body th,
            .markdown-body td {
              padding: 8px 12px;
              border: 1px solid var(--border-color);
              text-align: left;
              vertical-align: top;
            }
            .markdown-body th {
              background: rgba(0, 0, 0, 0.03);
              font-weight: 600;
            }
            .markdown-body hr {
              margin: 0.75em 0;
              border: none;
              border-top: 1px solid var(--border-color);
            }
            .markdown-body a {
              color: var(--accent-color);
              text-decoration: none;
            }
            .markdown-body a:hover { text-decoration: underline; }
            .markdown-body strong { font-weight: 600; }
            .markdown-body input[type='checkbox'] {
              transform: translateY(1px);
              margin-right: 8px;
              cursor: pointer;
            }
          </style>
        </head>
        <body\(bodyAttr)>
          <main class=\"page\">
            <article class=\"markdown-body\">\(body)</article>
          </main>
        </body>
        </html>
        """
    }

    private func renderBody(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = parseFenceToken(trimmed) {
                let code = collectFencedCode(lines: lines, startIndex: i + 1, fence: fence)
                let langClass = code.language.isEmpty ? "" : " class=\"language-\(escapeHTML(code.language))\""
                html.append("<pre><code\(langClass)>\(escapeHTML(code.content))</code></pre>")
                i = code.nextIndex
                continue
            }

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                html.append("<hr />")
                i += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                html.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
                i += 1
                continue
            }

            if let table = parseTable(lines: lines, start: i) {
                html.append(renderTable(table))
                i = table.nextIndex
                continue
            }

            if trimmed.hasPrefix(">") {
                let quote = collectQuote(lines: lines, start: i)
                html.append("<blockquote><p>\(renderInline(quote.joined(separator: "<br />")))</p></blockquote>")
                i += quote.count
                continue
            }

            if isListItem(trimmed) {
                let grouped = collectList(lines: lines, start: i)
                html.append(renderList(grouped.items))
                i = grouped.nextIndex
                continue
            }

            let paragraph = collectParagraph(lines: lines, start: i)
            html.append("<p>\(renderInline(paragraph.items.joined(separator: " ")))</p>")
            i = paragraph.nextIndex
        }

        return html.joined(separator: "\n")
    }

    private func parseFenceToken(_ line: String) -> (char: Character, len: Int, lang: String)? {
        guard line.hasPrefix("```") || line.hasPrefix("~~~") else { return nil }
        let marker = line.first ?? "`"
        let len = line.prefix { $0 == marker }.count
        let lang = String(line.dropFirst(len)).trimmingCharacters(in: .whitespaces)
        return (marker, len, lang)
    }

    private func collectFencedCode(lines: [String], startIndex: Int, fence: (char: Character, len: Int, lang: String)) -> (content: String, nextIndex: Int, language: String) {
        var body: [String] = []
        var i = startIndex

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.first == fence.char, trimmed.prefix(while: { $0 == fence.char }).count >= fence.len {
                return (body.joined(separator: "\n"), i + 1, fence.lang)
            }
            body.append(lines[i])
            i += 1
        }

        return (body.joined(separator: "\n"), i, fence.lang)
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        line == "---" || line == "***" || line == "___"
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        let level = min(6, line.prefix { $0 == "#" }.count)
        let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private struct TableModel {
        let headers: [String]
        let alignments: [String]
        let rows: [[String]]
        let nextIndex: Int
    }

    private func parseTable(lines: [String], start: Int) -> TableModel? {
        guard start + 1 < lines.count,
              let headers = parseTableCells(lines[start]),
              let alignments = parseTableAlignments(lines[start + 1]) else {
            return nil
        }

        var rows: [[String]] = []
        var i = start + 2
        while i < lines.count {
            guard let row = parseTableCells(lines[i]) else { break }
            rows.append(row)
            i += 1
        }

        return TableModel(headers: headers, alignments: alignments, rows: rows, nextIndex: i)
    }

    private func parseTableCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }

        var body = trimmed
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }

        let parts = body.split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        return parts.count >= 2 ? parts : nil
    }

    private func parseTableAlignments(_ line: String) -> [String]? {
        guard let cells = parseTableCells(line) else { return nil }
        var alignments: [String] = []

        for cell in cells {
            let token = cell.replacingOccurrences(of: " ", with: "")
            let dashCount = token.filter { $0 == "-" }.count
            guard dashCount >= 3 else { return nil }
            guard token.allSatisfy({ $0 == "-" || $0 == ":" }) else { return nil }

            let left = token.first == ":"
            let right = token.last == ":"
            if left && right {
                alignments.append("center")
            } else if right {
                alignments.append("right")
            } else {
                alignments.append("left")
            }
        }

        return alignments
    }

    private func renderTable(_ table: TableModel) -> String {
        let colCount = max(table.headers.count, table.alignments.count, table.rows.map { $0.count }.max() ?? 0)

        func pad(_ values: [String], to count: Int) -> [String] {
            if values.count >= count { return Array(values.prefix(count)) }
            return values + Array(repeating: "", count: count - values.count)
        }

        let headers = pad(table.headers, to: colCount)
        let aligns = pad(table.alignments, to: colCount)

        let head = headers.enumerated().map { idx, value in
            "<th style=\"text-align:\(aligns[idx]);\">\(renderInline(value))</th>"
        }.joined()

        let body = table.rows.map { row -> String in
            let padded = pad(row, to: colCount)
            let cells = padded.enumerated().map { idx, value in
                "<td style=\"text-align:\(aligns[idx]);\">\(renderInline(value))</td>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }.joined()

        return "<table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table>"
    }

    private func isListItem(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { return true }
        if let regex = try? NSRegularExpression(pattern: #"^\d+\.\s+"#) {
            let ns = line as NSString
            return regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
        }
        return false
    }

    private struct ListLine {
        let ordered: Bool
        let content: String
        let indent: Int
        let taskChecked: Bool?
    }

    private func parseListLine(_ line: String) -> ListLine? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let regex = try? NSRegularExpression(pattern: #"^[-+*]\s+\[( |x|X)\]\s*(.*)$"#) {
            let ns = trimmed as NSString
            if let m = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges == 3 {
                let checked = ns.substring(with: m.range(at: 1)).lowercased() == "x"
                let text = ns.substring(with: m.range(at: 2))
                return ListLine(ordered: false, content: text, indent: indent, taskChecked: checked)
            }
        }

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return ListLine(ordered: false, content: String(trimmed.dropFirst(2)), indent: indent, taskChecked: nil)
        }

        if let regex = try? NSRegularExpression(pattern: #"^(\d+)\.\s+(.*)$"#) {
            let ns = trimmed as NSString
            if let m = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges == 3 {
                return ListLine(ordered: true, content: ns.substring(with: m.range(at: 2)), indent: indent, taskChecked: nil)
            }
        }

        return nil
    }

    private func collectList(lines: [String], start: Int) -> (items: [ListLine], nextIndex: Int) {
        var items: [ListLine] = []
        var i = start

        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }

            if let parsed = parseListLine(line) {
                items.append(parsed)
                i += 1
                continue
            }

            if let last = items.last, (line.hasPrefix("  ") || line.hasPrefix("\t")) {
                let merged = ListLine(
                    ordered: last.ordered,
                    content: last.content + " " + line.trimmingCharacters(in: .whitespaces),
                    indent: last.indent,
                    taskChecked: last.taskChecked
                )
                items[items.count - 1] = merged
                i += 1
                continue
            }

            break
        }

        return (items, i)
    }

    private func renderList(_ items: [ListLine]) -> String {
        guard !items.isEmpty else { return "" }

        var html: [String] = []
        var i = 0
        var taskCounter = 0
        while i < items.count {
            let ordered = items[i].ordered
            let tag = ordered ? "ol" : "ul"
            html.append("<\(tag)>")
            while i < items.count, items[i].ordered == ordered {
                let indentStyle = items[i].indent > 0 ? " style=\"margin-left:\(items[i].indent * 8)px;\"" : ""
                if let checked = items[i].taskChecked {
                    let flag = checked ? " checked" : ""
                    html.append("<li\(indentStyle)><input type=\"checkbox\" data-task-index=\"\(taskCounter)\"\(flag) />\(renderInline(items[i].content))</li>")
                    taskCounter += 1
                } else {
                    html.append("<li\(indentStyle)>\(renderInline(items[i].content))</li>")
                }
                i += 1
            }
            html.append("</\(tag)>")
        }

        return html.joined()
    }

    private func collectQuote(lines: [String], start: Int) -> [String] {
        var items: [String] = []
        var i = start
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            items.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            i += 1
        }
        return items
    }

    private func collectParagraph(lines: [String], start: Int) -> (items: [String], nextIndex: Int) {
        var items: [String] = []
        var i = start

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isHorizontalRule(trimmed) || parseHeading(trimmed) != nil ||
                trimmed.hasPrefix(">") || isListItem(trimmed) || parseFenceToken(trimmed) != nil ||
                parseTable(lines: lines, start: i) != nil {
                break
            }
            items.append(trimmed)
            i += 1
        }

        return (items, i)
    }

    private func renderInline(_ text: String) -> String {
        var output = escapeHTML(text)

        output = replace(pattern: #"`([^`]+)`"#, in: output) { groups in
            "<code>\(groups[0])</code>"
        }

        output = replace(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, in: output) { groups in
            "<a href=\"\(groups[1])\">\(groups[0])</a>"
        }

        output = replace(pattern: #"\*\*(.+?)\*\*"#, in: output) { groups in
            "<strong>\(groups[0])</strong>"
        }

        output = replace(pattern: #"__(.+?)__"#, in: output) { groups in
            "<strong>\(groups[0])</strong>"
        }

        output = replace(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, in: output) { groups in
            "<em>\(groups[0])</em>"
        }

        output = replace(pattern: #"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#, in: output) { groups in
            "<em>\(groups[0])</em>"
        }

        output = replace(pattern: #"~~(.+?)~~"#, in: output) { groups in
            "<del>\(groups[0])</del>"
        }

        return output
    }

    private func replace(pattern: String, in text: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            var groups: [String] = []
            for idx in 1..<match.numberOfRanges {
                groups.append((output as NSString).substring(with: match.range(at: idx)))
            }
            output = (output as NSString).replacingCharacters(in: match.range(at: 0), with: transform(groups))
        }
        return output
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
