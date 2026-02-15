import SwiftUI
import AppKit
import WebKit

struct ContentView: View {
    @EnvironmentObject var document: MarkdownDocument

    var body: some View {
        VStack(spacing: 0) {
            MarkdownEditorView(text: $document.content)
        }
        .frame(minWidth: 800, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(document.fileURL?.lastPathComponent ?? "未命名")
                    .font(.headline)
            }
        }
    }
}

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ShortcutAwareTextView(frame: .zero)
        let scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.insertionPointColor = NSColor.labelColor
        textView.drawsBackground = true

        textView.textContainerInset = NSSize(width: 80, height: 40)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if let textContainer = textView.textContainer {
            textContainer.containerSize = NSSize(
                width: scrollView.contentSize.width - 160,
                height: CGFloat.greatestFiniteMagnitude
            )
            textContainer.widthTracksTextView = true
        }

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        textView.onBoldShortcut = { [weak coordinator = context.coordinator] in
            coordinator?.applyMarkdownWrap(marker: "**")
        }
        textView.onItalicShortcut = { [weak coordinator = context.coordinator] in
            coordinator?.applyMarkdownWrap(marker: "*")
        }

        context.coordinator.attach(to: textView, initialText: text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.applyExternalText(text)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: MarkdownEditorView
        private weak var textView: NSTextView?
        private weak var tableWebView: WKWebView?

        private var isUpdating = false
        private var sourceText = ""
        private var focusedLineIndex: Int?
        private var activeCodeBlockRange: ClosedRange<Int>?
        private var activeTableRange: ClosedRange<Int>?
        private var overlayTableRange: ClosedRange<Int>?
        private var lastRenderedLines: [String] = []

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
        }

        func attach(to textView: NSTextView, initialText: String) {
            self.textView = textView
            sourceText = initialText
            focusedLineIndex = 0
            installTableWebViewIfNeeded()
            updateActiveCodeBlockRange()
            updateActiveTableRange()
            renderProjection(keepSelection: false)
        }

        func applyExternalText(_ text: String) {
            guard !isUpdating, text != sourceText else { return }
            sourceText = text
            updateActiveCodeBlockRange()
            updateActiveTableRange()
            renderProjection(keepSelection: true)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let textView = textView else { return }

            // Avoid clobbering in-flight edits (for example pressing Return) by
            // re-rendering from stale sourceText before textDidChange syncs.
            let currentDisplayLines = textView.string.components(separatedBy: "\n")
            guard currentDisplayLines == lastRenderedLines else { return }

            updateFocusForCurrentSelection(shouldRender: true)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isUpdating, replacementString == "|" else { return true }
            guard affectedCharRange.length == 0 else { return true }

            let nsText = textView.string as NSString
            let lineRange = nsText.lineRange(for: NSRange(location: affectedCharRange.location, length: 0))
            let lineTextWithTerminator = nsText.substring(with: lineRange)
            let lineText = lineTextWithTerminator.trimmingCharacters(in: .newlines)
            let lineIndent = lineText.prefix { $0 == " " || $0 == "\t" }
            guard lineText.trimmingCharacters(in: .whitespaces).isEmpty else { return true }

            let currentLine = lineIndex(of: affectedCharRange.location, in: textView.string)
            guard !isInsideCodeBlock(lineIndex: currentLine) else { return true }

            let indent = String(lineIndent)
            let skeleton = [
                "\(indent)| Column 1 | Column 2 |",
                "\(indent)| --- | --- |",
                "\(indent)|  |  |"
            ].joined(separator: "\n")

            textView.insertText(skeleton, replacementRange: affectedCharRange)
            textView.setSelectedRange(NSRange(location: affectedCharRange.location + indent.count + 2, length: 0))
            return false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)), !isUpdating else {
                return false
            }

            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }

            let displayText = textView.string as NSString
            let lineRange = displayText.lineRange(for: NSRange(location: selection.location, length: 0))
            let lineTextWithTerminator = displayText.substring(with: lineRange)
            let lineText = lineTextWithTerminator.trimmingCharacters(in: .newlines)

            guard lineText == "```" else { return false }

            let lineTextLength = lineTextWithTerminator.hasSuffix("\n")
                ? (lineTextWithTerminator as NSString).length - 1
                : (lineTextWithTerminator as NSString).length
            let lineEndLocation = lineRange.location + lineTextLength
            guard selection.location == lineEndLocation else { return false }

            if let continuationPrefix = listContinuationPrefix(for: lineText) {
                textView.insertText("\n" + continuationPrefix, replacementRange: selection)
                textView.setSelectedRange(
                    NSRange(location: selection.location + 1 + continuationPrefix.count, length: 0)
                )
                updateFocusForCurrentSelection(shouldRender: true)
                return true
            }

            let currentLineIndex = lineIndex(of: selection.location, in: textView.string)
            guard isOpeningFenceLine(currentLineIndex) else { return false }

            textView.insertText("\n\n```", replacementRange: selection)
            textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            updateFocusForCurrentSelection(shouldRender: true)
            return true
        }

        private func listContinuationPrefix(for lineText: String) -> String? {
            let nsLine = lineText as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            let taskPattern = #"^([ \t]*)([-+*]) \[(?: |x|X)\](?:\s+(.+))?$"#
            if let regex = try? NSRegularExpression(pattern: taskPattern),
               let match = regex.firstMatch(in: lineText, range: fullRange),
               match.numberOfRanges >= 3 {
                let indent = nsLine.substring(with: match.range(at: 1))
                let marker = nsLine.substring(with: match.range(at: 2))
                let content = match.range(at: 3).location == NSNotFound
                    ? ""
                    : nsLine.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty else { return nil }
                return "\(indent)\(marker) [ ] "
            }

            let orderedPattern = #"^([ \t]*)(\d+)\.\s+(.+)$"#
            if let regex = try? NSRegularExpression(pattern: orderedPattern),
               let match = regex.firstMatch(in: lineText, range: fullRange),
               match.numberOfRanges == 4 {
                let indent = nsLine.substring(with: match.range(at: 1))
                let numberText = nsLine.substring(with: match.range(at: 2))
                let content = nsLine.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty, let number = Int(numberText) else { return nil }
                return "\(indent)\(number + 1). "
            }

            let unorderedPattern = #"^([ \t]*)([-+*])\s+(.+)$"#
            if let regex = try? NSRegularExpression(pattern: unorderedPattern),
               let match = regex.firstMatch(in: lineText, range: fullRange),
               match.numberOfRanges == 4 {
                let indent = nsLine.substring(with: match.range(at: 1))
                let marker = nsLine.substring(with: match.range(at: 2))
                let content = nsLine.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty else { return nil }
                return "\(indent)\(marker) "
            }

            return nil
        }

        func applyMarkdownWrap(marker: String) {
            guard !isUpdating, let textView = textView else { return }
            let selection = textView.selectedRange()
            let insertion = selection.location

            if selection.length > 0 {
                let nsText = textView.string as NSString
                let selected = nsText.substring(with: selection)
                let wrapped = marker + selected + marker
                textView.insertText(wrapped, replacementRange: selection)
                textView.setSelectedRange(NSRange(location: insertion + marker.count, length: selection.length))
            } else {
                textView.insertText(marker + marker, replacementRange: selection)
                textView.setSelectedRange(NSRange(location: insertion + marker.count, length: 0))
            }
            updateFocusForCurrentSelection(shouldRender: true)
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }

            let previousDisplayLines = lastRenderedLines
            let currentDisplayLines = textView.string.components(separatedBy: "\n")
            patchSourceLines(previous: previousDisplayLines, current: currentDisplayLines)

            parent.text = sourceText
            updateFocusForCurrentSelection(shouldRender: false)
            renderProjection(keepSelection: true)
        }

        private func patchSourceLines(previous: [String], current: [String]) {
            guard previous != current else { return }

            var sourceLines = sourceText.components(separatedBy: "\n")

            let prefixCount = commonPrefixCount(previous, current)
            let suffixCount = commonSuffixCount(previous, current, prefixCount: prefixCount)

            let previousStart = prefixCount
            let previousEnd = max(prefixCount, previous.count - suffixCount)
            let currentStart = prefixCount
            let currentEnd = max(prefixCount, current.count - suffixCount)

            let replacementLines = Array(current[currentStart..<currentEnd])
            let replaceRange = previousStart..<previousEnd

            if replaceRange.lowerBound <= sourceLines.count && replaceRange.upperBound <= sourceLines.count {
                sourceLines.replaceSubrange(replaceRange, with: replacementLines)
                sourceText = sourceLines.joined(separator: "\n")
            }
        }

        private func renderProjection(keepSelection: Bool) {
            guard let textView = textView else { return }

            isUpdating = true
            defer { isUpdating = false }

            let previousSelection = textView.selectedRange()
            let previousText = textView.string
            let previousCaret = lineAndColumn(of: previousSelection.location, in: previousText)
            let sourceLines = sourceText.components(separatedBy: "\n")
            let tablePresentation = buildTablePresentation(lines: sourceLines)
            var inCodeBlock = false
            let attributed = NSMutableAttributedString()
            var renderedLines: [String] = []

            for (index, line) in sourceLines.enumerated() {
                let lineAttr: NSAttributedString
                if shouldShowRaw(lineIndex: index) {
                    lineAttr = MarkdownRenderer.shared.renderRawLine(line)
                } else if activeTableRange == nil, let tableLine = tablePresentation[index] {
                    lineAttr = MarkdownRenderer.shared.renderHiddenTablePlaceholder(tableLine.text)
                } else {
                    lineAttr = MarkdownRenderer.shared.renderLine(line, inCodeBlock: &inCodeBlock)
                }

                attributed.append(lineAttr)
                renderedLines.append(lineAttr.string)

                if index < sourceLines.count - 1 {
                    attributed.append(NSAttributedString(string: "\n"))
                }
            }

            textView.textStorage?.setAttributedString(attributed)
            lastRenderedLines = renderedLines

            if keepSelection {
                let mappedLocation = characterOffset(
                    forLine: previousCaret.line,
                    column: previousCaret.column,
                    in: textView.string
                )
                textView.setSelectedRange(NSRange(location: mappedLocation, length: 0))
            } else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }

            updateTableWebOverlay()
        }

        private func tableWebOverlayRange(in lines: [String]) -> ClosedRange<Int>? {
            guard activeTableRange == nil else { return nil }
            return firstTableBlock(in: lines)?.range
        }

        private func shouldShowRaw(lineIndex: Int) -> Bool {
            if focusedLineIndex == lineIndex {
                return true
            }
            if let range = activeCodeBlockRange, range.contains(lineIndex) {
                return true
            }
            if let range = activeTableRange, range.contains(lineIndex) {
                return true
            }
            return false
        }

        private func updateFocusForCurrentSelection(shouldRender: Bool) {
            guard let textView = textView else { return }
            let selectedLine = lineIndex(of: textView.selectedRange().location, in: textView.string)
            let lineChanged = selectedLine != focusedLineIndex
            let previousCodeBlockRange = activeCodeBlockRange
            let previousTableRange = activeTableRange
            focusedLineIndex = selectedLine
            updateActiveCodeBlockRange()
            updateActiveTableRange()

            guard shouldRender else { return }
            if lineChanged || previousCodeBlockRange != activeCodeBlockRange || previousTableRange != activeTableRange {
                renderProjection(keepSelection: true)
            }
        }

        private func updateActiveCodeBlockRange() {
            guard let focusedLineIndex else {
                activeCodeBlockRange = nil
                return
            }

            let sourceLines = sourceText.components(separatedBy: "\n")
            activeCodeBlockRange = codeBlockRange(containing: focusedLineIndex, in: sourceLines)
        }

        private func updateActiveTableRange() {
            guard let focusedLineIndex else {
                activeTableRange = nil
                return
            }

            let sourceLines = sourceText.components(separatedBy: "\n")
            activeTableRange = tableRange(containing: focusedLineIndex, in: sourceLines)
        }

        private struct TableBlock {
            let range: ClosedRange<Int>
            let headers: [String]
            let alignments: [TableAlignment]
            let rows: [[String]]
        }

        private func installTableWebViewIfNeeded() {
            guard let textView, tableWebView == nil else { return }
            let webView = PassthroughWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            webView.setValue(false, forKey: "drawsBackground")
            webView.isHidden = true
            webView.navigationDelegate = nil
            webView.autoresizingMask = []
            textView.addSubview(webView)
            tableWebView = webView
        }

        private func updateTableWebOverlay() {
            guard let textView, let webView = tableWebView else { return }

            // Typora-like behavior: focus inside table -> raw markdown editing.
            if activeTableRange != nil {
                webView.isHidden = true
                overlayTableRange = nil
                return
            }

            let sourceLines = sourceText.components(separatedBy: "\n")
            guard let block = firstTableBlock(in: sourceLines),
                  let frame = tableFrame(for: block.range, in: textView) else {
                webView.isHidden = true
                overlayTableRange = nil
                return
            }

            if overlayTableRange != block.range {
                webView.loadHTMLString(tableHTML(for: block), baseURL: nil)
                overlayTableRange = block.range
            }

            webView.frame = frame
            webView.isHidden = false
        }

        private func firstTableBlock(in lines: [String]) -> TableBlock? {
            var inCodeBlock = false
            var index = 0

            while index < lines.count {
                let line = lines[index]
                if line.hasPrefix("```") {
                    inCodeBlock.toggle()
                    index += 1
                    continue
                }
                if inCodeBlock {
                    index += 1
                    continue
                }

                guard index + 1 < lines.count,
                      let headers = parseTableCells(lines[index]),
                      let alignments = parseTableSeparator(lines[index + 1]) else {
                    index += 1
                    continue
                }

                var rows: [[String]] = []
                var end = index + 1
                var scan = index + 2
                while scan < lines.count {
                    let rowLine = lines[scan]
                    if rowLine.hasPrefix("```") { break }
                    guard let cells = parseTableCells(rowLine) else { break }
                    rows.append(cells)
                    end = scan
                    scan += 1
                }

                return TableBlock(range: index...end, headers: headers, alignments: alignments, rows: rows)
            }

            return nil
        }

        private func tableFrame(for range: ClosedRange<Int>, in textView: NSTextView) -> NSRect? {
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
                return nil
            }
            let displayText = textView.string
            let start = characterOffset(forDisplayedLine: range.lowerBound, text: displayText)
            let end = characterOffset(forDisplayedLine: range.upperBound + 1, text: displayText)
            let charRange = NSRange(location: start, length: max(0, end - start))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height
            rect.size.width = max(200, rect.size.width)
            rect.size.height += 6
            return rect
        }

        private func characterOffset(forDisplayedLine targetLine: Int, text: String) -> Int {
            let ns = text as NSString
            guard targetLine > 0 else { return 0 }
            let length = ns.length
            var currentLine = 0
            var index = 0
            while index < length {
                if currentLine == targetLine {
                    return index
                }
                if ns.character(at: index) == 10 {
                    currentLine += 1
                }
                index += 1
            }
            if currentLine == targetLine {
                return length
            }
            return length
        }

        private func characterOffset(forLine targetLine: Int, lines: [String]) -> Int {
            guard targetLine > 0 else { return 0 }
            var offset = 0
            for idx in 0..<min(targetLine, lines.count) {
                offset += lines[idx].count
                if idx < lines.count - 1 {
                    offset += 1
                }
            }
            return offset
        }

        private func tableHTML(for block: TableBlock) -> String {
            let rowMax = block.rows.map { $0.count }.max() ?? 0
            let colCount = max(block.headers.count, max(block.alignments.count, rowMax))
            let headers = padCells(block.headers, to: colCount)
            let alignments = padAlignments(block.alignments, to: colCount)
            let rows = block.rows.map { padCells($0, to: colCount) }

            let alignmentCSS = alignments.map { alignment -> String in
                switch alignment {
                case .left: return "left"
                case .center: return "center"
                case .right: return "right"
                }
            }

            let headerHTML = headers.enumerated().map { index, cell in
                "<th style=\"text-align:\(alignmentCSS[index])\">\(escapeHTML(cell))</th>"
            }.joined()

            let bodyHTML = rows.map { row in
                let cells = row.enumerated().map { index, cell in
                    "<td style=\"text-align:\(alignmentCSS[index])\">\(escapeHTML(cell))</td>"
                }.joined()
                return "<tr>\(cells)</tr>"
            }.joined()

            return """
            <html>
              <head>
                <meta charset="utf-8">
                <style>
                  body { margin: 0; padding: 0; background: transparent; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
                  table { width: max-content; border-collapse: collapse; table-layout: auto; font-size: 13px; line-height: 1.25; color: #1f2328; }
                  th, td { border: 1px solid #d0d7de; padding: 2px 8px; vertical-align: middle; white-space: nowrap; }
                  th { background: #f6f8fa; font-weight: 600; }
                  tr:nth-child(even) td { background: #fcfcfd; }
                </style>
              </head>
              <body>
                <table>
                  <thead><tr>\(headerHTML)</tr></thead>
                  <tbody>\(bodyHTML)</tbody>
                </table>
              </body>
            </html>
            """
        }

        private func escapeHTML(_ text: String) -> String {
            text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        private func codeBlockRange(containing line: Int, in lines: [String]) -> ClosedRange<Int>? {
            guard !lines.isEmpty, line >= 0, line < lines.count else { return nil }

            var fenceStart: Int?
            for (index, content) in lines.enumerated() {
                guard content.hasPrefix("```") else { continue }
                if let start = fenceStart {
                    let range = start...index
                    if range.contains(line) {
                        return range
                    }
                    fenceStart = nil
                } else {
                    fenceStart = index
                }
            }

            if let start = fenceStart {
                let range = start...(lines.count - 1)
                if range.contains(line) {
                    return range
                }
            }

            return nil
        }

        private func isOpeningFenceLine(_ lineIndex: Int) -> Bool {
            let sourceLines = sourceText.components(separatedBy: "\n")
            guard lineIndex >= 0, lineIndex < sourceLines.count else { return false }
            guard sourceLines[lineIndex] == "```" else { return false }

            var inCodeBlock = false
            for (index, line) in sourceLines.enumerated() {
                guard line.hasPrefix("```") else { continue }
                if index == lineIndex {
                    return !inCodeBlock
                }
                inCodeBlock.toggle()
            }

            return false
        }

        private func isInsideCodeBlock(lineIndex: Int) -> Bool {
            let sourceLines = sourceText.components(separatedBy: "\n")
            return codeBlockRange(containing: lineIndex, in: sourceLines) != nil
        }

        private func tableRange(containing line: Int, in lines: [String]) -> ClosedRange<Int>? {
            guard !lines.isEmpty, line >= 0, line < lines.count else { return nil }

            var inCodeBlock = false
            var index = 0

            while index < lines.count {
                let current = lines[index]
                if current.hasPrefix("```") {
                    inCodeBlock.toggle()
                    index += 1
                    continue
                }

                if inCodeBlock {
                    index += 1
                    continue
                }

                guard index + 1 < lines.count,
                      parseTableCells(lines[index]) != nil,
                      parseTableSeparator(lines[index + 1]) != nil else {
                    index += 1
                    continue
                }

                var end = index + 1
                var scan = index + 2
                while scan < lines.count {
                    let rowLine = lines[scan]
                    if rowLine.hasPrefix("```") || parseTableCells(rowLine) == nil {
                        break
                    }
                    end = scan
                    scan += 1
                }

                let range = index...end
                if range.contains(line) {
                    return range
                }
                index = scan
            }

            return nil
        }

        private struct TableLinePresentation {
            let text: String
            let isHeader: Bool
            let isSeparator: Bool
        }

        private enum TableAlignment {
            case left
            case center
            case right
        }

        private enum TableRowKind {
            case header
            case body
            case separator
        }

        private func buildTablePresentation(lines: [String]) -> [Int: TableLinePresentation] {
            var result: [Int: TableLinePresentation] = [:]
            var inCodeBlock = false
            var index = 0

            while index < lines.count {
                let line = lines[index]
                if line.hasPrefix("```") {
                    inCodeBlock.toggle()
                    index += 1
                    continue
                }

                if inCodeBlock {
                    index += 1
                    continue
                }

                guard index + 1 < lines.count,
                      let headerCells = parseTableCells(lines[index]),
                      let alignments = parseTableSeparator(lines[index + 1]) else {
                    index += 1
                    continue
                }

                let columnCount = max(headerCells.count, alignments.count)
                var rows: [(lineIndex: Int, kind: TableRowKind, cells: [String])] = []
                rows.append((index, .header, headerCells))
                rows.append((index + 1, .separator, []))

                var scan = index + 2
                while scan < lines.count {
                    let rowLine = lines[scan]
                    if rowLine.hasPrefix("```") { break }
                    guard let rowCells = parseTableCells(rowLine) else { break }
                    rows.append((scan, .body, rowCells))
                    scan += 1
                }

                var widths = Array(repeating: 3, count: columnCount)
                for row in rows where row.kind != .separator {
                    let padded = padCells(row.cells, to: columnCount)
                    for col in 0..<columnCount {
                        widths[col] = max(widths[col], max(3, padded[col].count))
                    }
                }

                let paddedAlignments = padAlignments(alignments, to: columnCount)

                for row in rows {
                    switch row.kind {
                    case .separator:
                        result[row.lineIndex] = TableLinePresentation(
                            text: buildSeparatorRow(widths: widths, alignments: paddedAlignments),
                            isHeader: false,
                            isSeparator: true
                        )
                    case .header, .body:
                        result[row.lineIndex] = TableLinePresentation(
                            text: buildTableRow(
                                cells: row.cells,
                                widths: widths,
                                alignments: paddedAlignments
                            ),
                            isHeader: row.kind == .header,
                            isSeparator: false
                        )
                    }
                }

                index = scan
            }

            return result
        }

        private func parseTableCells(_ line: String) -> [String]? {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("|") else { return nil }

            var content = trimmed
            if content.hasPrefix("|") {
                content.removeFirst()
            }
            if content.hasSuffix("|"), !content.isEmpty {
                content.removeLast()
            }

            let parts = content
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }

            guard parts.count >= 2 else { return nil }
            return parts
        }

        private func parseTableSeparator(_ line: String) -> [TableAlignment]? {
            guard let cells = parseTableCells(line), !cells.isEmpty else { return nil }
            var alignments: [TableAlignment] = []

            for cell in cells {
                let token = cell.replacingOccurrences(of: " ", with: "")
                let dashCount = token.filter { $0 == "-" }.count
                guard dashCount >= 3 else { return nil }
                guard token.allSatisfy({ $0 == "-" || $0 == ":" }) else { return nil }

                let leftColon = token.first == ":"
                let rightColon = token.last == ":"
                if leftColon && rightColon {
                    alignments.append(.center)
                } else if rightColon {
                    alignments.append(.right)
                } else {
                    alignments.append(.left)
                }
            }

            return alignments
        }

        private func padCells(_ cells: [String], to count: Int) -> [String] {
            guard cells.count < count else { return Array(cells.prefix(count)) }
            return cells + Array(repeating: "", count: count - cells.count)
        }

        private func padAlignments(_ alignments: [TableAlignment], to count: Int) -> [TableAlignment] {
            guard alignments.count < count else { return Array(alignments.prefix(count)) }
            return alignments + Array(repeating: .left, count: count - alignments.count)
        }

        private func buildTableRow(cells: [String], widths: [Int], alignments: [TableAlignment]) -> String {
            let paddedCells = padCells(cells, to: widths.count)
            var rendered: [String] = []

            for index in 0..<widths.count {
                rendered.append(
                    alignCell(
                        paddedCells[index],
                        width: widths[index],
                        alignment: alignments[index]
                    )
                )
            }

            return "│ " + rendered.joined(separator: " │ ") + " │"
        }

        private func buildSeparatorRow(widths: [Int], alignments: [TableAlignment]) -> String {
            var cells: [String] = []
            for index in 0..<widths.count {
                let width = max(3, widths[index])
                switch alignments[index] {
                case .left:
                    cells.append(String(repeating: "-", count: width))
                case .center:
                    cells.append(":" + String(repeating: "-", count: max(1, width - 2)) + ":")
                case .right:
                    cells.append(String(repeating: "-", count: max(1, width - 1)) + ":")
                }
            }

            let converted = cells.map { segment in
                segment.replacingOccurrences(of: ":", with: "─").replacingOccurrences(of: "-", with: "─")
            }
            return "├─" + converted.joined(separator: "─┼─") + "─┤"
        }

        private func alignCell(_ text: String, width: Int, alignment: TableAlignment) -> String {
            let padding = max(0, width - text.count)
            switch alignment {
            case .left:
                return text + String(repeating: " ", count: padding)
            case .center:
                let leftPadding = padding / 2
                let rightPadding = padding - leftPadding
                return String(repeating: " ", count: leftPadding) + text + String(repeating: " ", count: rightPadding)
            case .right:
                return String(repeating: " ", count: padding) + text
            }
        }

        private func lineIndex(of characterIndex: Int, in text: String) -> Int {
            let nsText = text as NSString
            let safeIndex = min(max(characterIndex, 0), nsText.length)
            var line = 0
            var i = 0
            while i < safeIndex {
                if nsText.character(at: i) == 10 {
                    line += 1
                }
                i += 1
            }
            return line
        }

        private func lineAndColumn(of characterIndex: Int, in text: String) -> (line: Int, column: Int) {
            let nsText = text as NSString
            let safeIndex = min(max(characterIndex, 0), nsText.length)
            var line = 0
            var lineStart = 0
            var i = 0
            while i < safeIndex {
                if nsText.character(at: i) == 10 {
                    line += 1
                    lineStart = i + 1
                }
                i += 1
            }
            return (line, safeIndex - lineStart)
        }

        private func characterOffset(forLine targetLine: Int, column: Int, in text: String) -> Int {
            let nsText = text as NSString
            let length = nsText.length
            if targetLine <= 0 {
                return min(max(column, 0), length)
            }

            var line = 0
            var index = 0
            var lineStart = 0

            while index < length, line < targetLine {
                if nsText.character(at: index) == 10 {
                    line += 1
                    lineStart = index + 1
                }
                index += 1
            }

            var lineEnd = lineStart
            while lineEnd < length, nsText.character(at: lineEnd) != 10 {
                lineEnd += 1
            }

            let lineLength = max(0, lineEnd - lineStart)
            return lineStart + min(max(column, 0), lineLength)
        }

        private func commonPrefixCount(_ lhs: [String], _ rhs: [String]) -> Int {
            let maxCount = min(lhs.count, rhs.count)
            var index = 0
            while index < maxCount, lhs[index] == rhs[index] {
                index += 1
            }
            return index
        }

        private func commonSuffixCount(_ lhs: [String], _ rhs: [String], prefixCount: Int) -> Int {
            var leftIndex = lhs.count - 1
            var rightIndex = rhs.count - 1
            var count = 0

            while leftIndex >= prefixCount,
                  rightIndex >= prefixCount,
                  lhs[leftIndex] == rhs[rightIndex] {
                count += 1
                leftIndex -= 1
                rightIndex -= 1
            }

            return count
        }
    }
}

final class MarkdownRenderer {
    static let shared = MarkdownRenderer()

    private init() {}

    func renderRawLine(_ line: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.textBackgroundColor,
            .paragraphStyle: style
        ]
        return NSAttributedString(string: line, attributes: attributes)
    }

    func renderLine(_ line: String, inCodeBlock: inout Bool) -> NSAttributedString {
        if line.hasPrefix("```") {
            inCodeBlock.toggle()
            return NSAttributedString(string: "")
        }

        if inCodeBlock {
            return renderCodeLine(line)
        }

        if line.hasPrefix("#") {
            return renderHeading(line)
        }
        if line.hasPrefix(">") {
            return renderBlockquote(line)
        }
        if let listLine = parseListLine(line) {
            return renderListLine(listLine)
        }
        if line == "---" || line == "***" || line == "___" {
            return renderHorizontalRule()
        }

        return renderInlineMarkdown(line)
    }

    func renderTableLine(_ line: String, isHeader: Bool, isSeparator: Bool) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4

        if isSeparator {
            return NSAttributedString(string: line, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.separatorColor,
                .paragraphStyle: style
            ])
        }

        return NSAttributedString(string: line, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: isHeader ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: isHeader ? NSColor.controlBackgroundColor : NSColor.textBackgroundColor,
            .paragraphStyle: style
        ])
    }

    func renderHiddenTablePlaceholder(_ line: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        return NSAttributedString(string: line, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.clear,
            .backgroundColor: NSColor.clear,
            .paragraphStyle: style
        ])
    }

    private func renderHeading(_ line: String) -> NSAttributedString {
        var level = 0
        for char in line {
            if char == "#" { level += 1 } else { break }
        }

        let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        let font: NSFont

        switch level {
        case 1: font = .systemFont(ofSize: 30, weight: .bold)
        case 2: font = .systemFont(ofSize: 26, weight: .bold)
        case 3: font = .systemFont(ofSize: 22, weight: .semibold)
        case 4: font = .systemFont(ofSize: 20, weight: .semibold)
        case 5: font = .systemFont(ofSize: 18, weight: .medium)
        default: font = .systemFont(ofSize: 16, weight: .medium)
        }

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 10
        style.paragraphSpacing = 6

        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ])
    }

    private func renderBlockquote(_ line: String) -> NSAttributedString {
        let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 18
        style.headIndent = 18
        style.paragraphSpacing = 6

        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style
        ])
    }

    private struct ListLine {
        let indentCount: Int
        let marker: String
        let text: String
    }

    private func parseListLine(_ line: String) -> ListLine? {
        let indentCount = line.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let nsTrimmed = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsTrimmed.length)
        if let taskRegex = try? NSRegularExpression(pattern: #"^([-+*])\s*\[( |x|X)?\]\s*(.*)$"#),
           let taskMatch = taskRegex.firstMatch(in: trimmed, range: fullRange),
           taskMatch.numberOfRanges == 4 {
            let state = taskMatch.range(at: 2).location == NSNotFound
                ? ""
                : nsTrimmed.substring(with: taskMatch.range(at: 2))
            let marker = state.lowercased() == "x" ? "☑" : "☐"
            let content = nsTrimmed.substring(with: taskMatch.range(at: 3))
            return ListLine(indentCount: indentCount, marker: marker, text: content)
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return ListLine(indentCount: indentCount, marker: "•", text: String(trimmed.dropFirst(2)))
        }

        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)\.\s+(.+)$"#),
              let match = regex.firstMatch(in: trimmed, range: fullRange),
              match.numberOfRanges == 3 else {
            return nil
        }
        let number = nsTrimmed.substring(with: match.range(at: 1))
        let content = nsTrimmed.substring(with: match.range(at: 2))
        return ListLine(indentCount: indentCount, marker: "\(number).", text: content)
    }

    private func renderListLine(_ listLine: ListLine) -> NSAttributedString {
        let indentLevel = listLine.indentCount / 2
        let baseIndent: CGFloat = 22
        let nestedOffset = CGFloat(indentLevel) * 18
        let markerWidth: CGFloat = listLine.marker.count > 1 ? 26 : 20

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = baseIndent + nestedOffset
        style.headIndent = baseIndent + nestedOffset + markerWidth
        style.paragraphSpacing = 4

        let prefix = NSAttributedString(string: listLine.marker + " ", attributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ])

        let contentAttr = NSMutableAttributedString(attributedString: renderInlineMarkdown(listLine.text))
        contentAttr.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: contentAttr.length))

        let result = NSMutableAttributedString()
        result.append(prefix)
        result.append(contentAttr)
        return result
    }

    private func renderHorizontalRule() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 12

        return NSAttributedString(string: "────────────────────", attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.separatorColor,
            .paragraphStyle: style
        ])
    }

    private func renderCodeLine(_ line: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.paragraphSpacing = 2

        return NSAttributedString(string: line, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.quaternaryLabelColor,
            .paragraphStyle: style
        ])
    }

    private func renderInlineMarkdown(_ line: String) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: 16)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ]

        let result = NSMutableAttributedString(string: line, attributes: baseAttrs)

        applyInlineReplacement(
            pattern: "`([^`]+)`",
            on: result
        ) { text in
            NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.quaternaryLabelColor
            ])
        }

        applyInlineReplacement(
            pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
            on: result
        ) { text in
            NSAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ])
        }

        applyInlineReplacement(
            pattern: "\\*\\*(.+?)\\*\\*",
            on: result
        ) { text in
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ])
        }

        applyInlineReplacement(
            pattern: "__(.+?)__",
            on: result
        ) { text in
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ])
        }

        applyInlineReplacement(
            pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)",
            on: result
        ) { text in
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .regular).italic(),
                .foregroundColor: NSColor.labelColor
            ])
        }

        applyInlineReplacement(
            pattern: "(?<!_)_(?!_)(.+?)(?<!_)_(?!_)",
            on: result
        ) { text in
            NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .regular).italic(),
                .foregroundColor: NSColor.labelColor
            ])
        }

        applyInlineReplacement(
            pattern: "~~(.+?)~~",
            on: result
        ) { text in
            NSAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ])
        }

        return result
    }

    private func applyInlineReplacement(
        pattern: String,
        on attributed: NSMutableAttributedString,
        replacementBuilder: (String) -> NSAttributedString
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let plain = attributed.string
        let fullRange = NSRange(location: 0, length: (plain as NSString).length)
        let matches = regex.matches(in: plain, range: fullRange)

        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let full = match.range(at: 0)
            let content = match.range(at: 1)
            guard full.location != NSNotFound, content.location != NSNotFound else { continue }

            let text = (plain as NSString).substring(with: content)
            let replacement = replacementBuilder(text)
            attributed.replaceCharacters(in: full, with: replacement)
        }
    }
}

final class PassthroughWKWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class ShortcutAwareTextView: NSTextView {
    var onBoldShortcut: (() -> Void)?
    var onItalicShortcut: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let usesBoldItalicShortcut = flags == [.control] || flags == [.command]
        if usesBoldItalicShortcut, let chars = event.charactersIgnoringModifiers?.lowercased() {
            if chars == "b" {
                onBoldShortcut?()
                return
            }
            if chars == "i" {
                onItalicShortcut?()
                return
            }
        }
        super.keyDown(with: event)
    }
}
