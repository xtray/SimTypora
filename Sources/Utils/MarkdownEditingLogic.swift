import Foundation

struct BlockReturnAction: Equatable {
    let currentBlock: String
    let nextBlock: String
    let sameBlockSelectionInUpdatedBlock: Int?

    init(currentBlock: String, nextBlock: String, sameBlockSelectionInUpdatedBlock: Int? = nil) {
        self.currentBlock = currentBlock
        self.nextBlock = nextBlock
        self.sameBlockSelectionInUpdatedBlock = sameBlockSelectionInUpdatedBlock
    }

    var nextSelection: Int {
        (nextBlock as NSString).length
    }
}

struct BlockBackspaceAction: Equatable {
    let mergedBlock: String
    let selectionInMergedBlock: Int
}

enum MarkdownInlineStyle: Equatable {
    case bold
    case italic
    case strikethrough
    case inlineCode

    var marker: String {
        switch self {
        case .bold:
            return "**"
        case .italic:
            return "*"
        case .strikethrough:
            return "~~"
        case .inlineCode:
            return "`"
        }
    }
}

struct InlineMarkdownStyleAction: Equatable {
    let updatedText: String
    let updatedSelection: NSRange
}

func applyInlineMarkdownStyle(
    _ style: MarkdownInlineStyle,
    in text: String,
    selection: NSRange
) -> InlineMarkdownStyleAction {
    let nsText = text as NSString
    let clampedSelection = clampedRange(selection, maxLength: nsText.length)
    let marker = style.marker
    let markerLength = (marker as NSString).length

    guard markerLength > 0 else {
        return InlineMarkdownStyleAction(updatedText: text, updatedSelection: clampedSelection)
    }

    var targetRange = clampedSelection
    if targetRange.length == 0 {
        if let wordRange = wordRangeAroundCaret(in: text, caret: targetRange.location) {
            targetRange = wordRange
        } else {
            let inserted = marker + marker
            let updated = nsText.replacingCharacters(in: targetRange, with: inserted)
            return InlineMarkdownStyleAction(
                updatedText: updated,
                updatedSelection: NSRange(location: targetRange.location + markerLength, length: 0)
            )
        }
    }

    if targetRange.length >= markerLength * 2 {
        let selected = nsText.substring(with: targetRange)
        if selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let innerRange = NSRange(
                location: targetRange.location + markerLength,
                length: targetRange.length - markerLength * 2
            )
            let unwrapped = nsText.substring(with: innerRange)
            let updated = nsText.replacingCharacters(in: targetRange, with: unwrapped)
            return InlineMarkdownStyleAction(
                updatedText: updated,
                updatedSelection: NSRange(location: targetRange.location, length: innerRange.length)
            )
        }
    }

    if targetRange.location >= markerLength,
       targetRange.location + targetRange.length + markerLength <= nsText.length {
        let beforeRange = NSRange(location: targetRange.location - markerLength, length: markerLength)
        let afterRange = NSRange(location: targetRange.location + targetRange.length, length: markerLength)
        let before = nsText.substring(with: beforeRange)
        let after = nsText.substring(with: afterRange)

        if before == marker, after == marker {
            let outerRange = NSRange(
                location: targetRange.location - markerLength,
                length: targetRange.length + markerLength * 2
            )
            let content = nsText.substring(with: targetRange)
            let updated = nsText.replacingCharacters(in: outerRange, with: content)
            return InlineMarkdownStyleAction(
                updatedText: updated,
                updatedSelection: NSRange(location: targetRange.location - markerLength, length: targetRange.length)
            )
        }
    }

    let selected = nsText.substring(with: targetRange)
    let wrapped = marker + selected + marker
    let updated = nsText.replacingCharacters(in: targetRange, with: wrapped)
    return InlineMarkdownStyleAction(
        updatedText: updated,
        updatedSelection: NSRange(location: targetRange.location + markerLength, length: targetRange.length)
    )
}

enum MarkdownLineStyle: Equatable {
    case heading(level: Int)
    case unorderedList
    case orderedList
    case blockquote
}

func applyLineMarkdownStyle(
    _ style: MarkdownLineStyle,
    in text: String,
    selection: NSRange
) -> InlineMarkdownStyleAction {
    let nsText = text as NSString
    let clampedSelection = clampedRange(selection, maxLength: nsText.length)
    let targetRange = lineRangeCoveringSelection(clampedSelection, in: nsText)
    let targetText = nsText.substring(with: targetRange)

    var lines = targetText.components(separatedBy: "\n")
    let trailingNewline = targetText.hasSuffix("\n")
    if trailingNewline, !lines.isEmpty {
        lines.removeLast()
    }

    if lines.isEmpty {
        lines = [""]
    }

    let transformedLines = lines.map { transformLine($0, style: style) }
    var replacement = transformedLines.joined(separator: "\n")
    if trailingNewline {
        replacement += "\n"
    }

    let updatedText = nsText.replacingCharacters(in: targetRange, with: replacement)
    let updatedSelection = NSRange(location: targetRange.location, length: (replacement as NSString).length)
    return InlineMarkdownStyleAction(updatedText: updatedText, updatedSelection: updatedSelection)
}

func makeBlockReturnAction(block: String, selection: Int) -> BlockReturnAction? {
    let nsBlock = block as NSString
    let clamped = min(max(0, selection), nsBlock.length)
    guard clamped == nsBlock.length, selection == clamped else { return nil }
    let activeLine = trailingLine(in: block)
    guard !activeLine.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

    if let fenceAction = makeFenceAutoCompletionAction(block: block, activeLine: activeLine) {
        return fenceAction
    }

    return BlockReturnAction(
        currentBlock: block,
        nextBlock: continuationPrefix(for: activeLine, in: block)
    )
}

func makeBlockBackspaceAction(
    previousBlock: String,
    currentBlock: String,
    selection: Int
) -> BlockBackspaceAction? {
    guard selection == 0 else { return nil }
    let merged = previousBlock + "\n" + currentBlock
    let boundary = (previousBlock as NSString).length + 1
    return BlockBackspaceAction(mergedBlock: merged, selectionInMergedBlock: boundary)
}

func shouldDeactivateForEndedBlock(activeBlockIndex: Int?, endedBlockIndex: Int) -> Bool {
    activeBlockIndex == endedBlockIndex
}

func shouldContinueEditingInSameBlock(block: String, continuation: String) -> Bool {
    let line = trailingLine(in: block)
    if let table = parseTableRow(line) {
        if table.isAllEmpty {
            return false
        }
        if !continuation.isEmpty {
            return true
        }
        if hasSeparatorRowAbove(in: block) {
            return false
        }
        // Keep header -> separator flow in one block, but don't trap editing
        // when no valid separator ever appears.
        return trailingTableRowCount(in: block) == 1
    }
    guard !continuation.isEmpty else { return false }
    let trimmed = line.trimmingCharacters(in: .whitespaces)

    if trimmed.hasPrefix(">") {
        return true
    }

    if let regex = try? NSRegularExpression(pattern: #"^\s*[-+*]\s+(\[( |x|X)\]\s+)?\S.*$"#) {
        let ns = line as NSString
        if regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil {
            return true
        }
    }

    if let regex = try? NSRegularExpression(pattern: #"^\s*\d+\.\s+\S.*$"#) {
        let ns = line as NSString
        if regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil {
            return true
        }
    }

    return false
}

func shiftedRenderedHeightsForInsertion(_ heights: [Int: CGFloat], at insertedIndex: Int) -> [Int: CGFloat] {
    guard insertedIndex >= 0 else { return heights }
    var shifted: [Int: CGFloat] = [:]
    shifted.reserveCapacity(heights.count)

    for (index, height) in heights {
        if index >= insertedIndex {
            shifted[index + 1] = height
        } else {
            shifted[index] = height
        }
    }

    return shifted
}

func shiftedRenderedHeightsForRemoval(_ heights: [Int: CGFloat], at removedIndex: Int) -> [Int: CGFloat] {
    guard removedIndex >= 0 else { return heights }
    var shifted: [Int: CGFloat] = [:]
    shifted.reserveCapacity(max(0, heights.count - 1))

    for (index, height) in heights {
        if index == removedIndex {
            continue
        }
        if index > removedIndex {
            shifted[index - 1] = height
        } else {
            shifted[index] = height
        }
    }

    return shifted
}

func splitMarkdownBlocks(_ content: String) -> [String] {
    if content.isEmpty { return [""] }

    let lines = content.components(separatedBy: "\n")
    var blocks: [String] = []
    var current: [String] = []
    var fenceChar: Character?
    var fenceLength = 0

    func flushCurrent() {
        guard !current.isEmpty else { return }
        blocks.append(current.joined(separator: "\n"))
        current.removeAll(keepingCapacity: true)
    }

    for line in lines {
        let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
        let fence = parseFenceToken(line)

        if fenceChar == nil && isBlank {
            flushCurrent()
            continue
        }

        current.append(line)

        if let fence {
            if fenceChar == nil {
                fenceChar = fence.char
                fenceLength = fence.length
            } else if fence.char == fenceChar && fence.length >= fenceLength {
                fenceChar = nil
                fenceLength = 0
            }
        }
    }

    flushCurrent()

    if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       content.hasSuffix("\n\n"),
       (blocks.last?.isEmpty == false) {
        blocks.append("")
    }

    return blocks.isEmpty ? [""] : blocks
}

func joinMarkdownBlocks(_ blocks: [String]) -> String {
    blocks.joined(separator: "\n\n")
}

func parseFenceToken(_ line: String) -> (char: Character, length: Int)? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("```") {
        return ("`", trimmed.prefix { $0 == "`" }.count)
    }
    if trimmed.hasPrefix("~~~") {
        return ("~", trimmed.prefix { $0 == "~" }.count)
    }
    return nil
}

func toggleTaskStateAtIndex(_ block: String, taskIndex: Int) -> String {
    let lines = block.components(separatedBy: "\n")
    var output = lines
    var seen = 0
    var fenceChar: Character?
    var fenceLength = 0

    for i in 0..<lines.count {
        let line = lines[i]
        if let fence = parseFenceToken(line) {
            if fenceChar == nil {
                fenceChar = fence.char
                fenceLength = fence.length
            } else if fence.char == fenceChar && fence.length >= fenceLength {
                fenceChar = nil
                fenceLength = 0
            }
        }
        if fenceChar != nil { continue }

        if let regex = try? NSRegularExpression(pattern: #"^(\s*[-*+]\s+\[)( |x|X)(\]\s.*)$"#) {
            let ns = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges == 4 {
                if seen == taskIndex {
                    let prefix = ns.substring(with: match.range(at: 1))
                    let mark = ns.substring(with: match.range(at: 2))
                    let suffix = ns.substring(with: match.range(at: 3))
                    let next = mark.lowercased() == "x" ? " " : "x"
                    output[i] = prefix + next + suffix
                    return output.joined(separator: "\n")
                }
                seen += 1
                continue
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"^(\s*\d+\.\s+\[)( |x|X)(\]\s.*)$"#) {
            let ns = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges == 4 {
                if seen == taskIndex {
                    let prefix = ns.substring(with: match.range(at: 1))
                    let mark = ns.substring(with: match.range(at: 2))
                    let suffix = ns.substring(with: match.range(at: 3))
                    let next = mark.lowercased() == "x" ? " " : "x"
                    output[i] = prefix + next + suffix
                    return output.joined(separator: "\n")
                }
                seen += 1
                continue
            }
        }
    }

    return block
}

private func continuationPrefix(for line: String, in block: String) -> String {
    if let task = captureGroups(
        pattern: #"^(\s*)([-+*])\s+\[( |x|X)\]\s*(.*)$"#,
        in: line
    ), task.count == 4 {
        if task[3].trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        return task[0] + task[1] + " [ ] "
    }

    if let unordered = captureGroups(
        pattern: #"^(\s*)([-+*])\s+(.*)$"#,
        in: line
    ), unordered.count == 3 {
        if unordered[2].trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        return unordered[0] + unordered[1] + " "
    }

    if let ordered = captureGroups(
        pattern: #"^(\s*)(\d+)\.\s+(.*)$"#,
        in: line
    ), ordered.count == 3 {
        if ordered[2].trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        let current = Int(ordered[1]) ?? 1
        return ordered[0] + "\(current + 1). "
    }

    if let quote = captureGroups(
        pattern: #"^(\s*(?:>\s*)+)(.*)$"#,
        in: line
    ), quote.count == 2 {
        if quote[1].trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        return quote[0].hasSuffix(" ") ? quote[0] : quote[0] + " "
    }

    if let table = parseTableRow(line) {
        if table.isAllEmpty {
            return ""
        }
        if table.isSeparatorRow {
            return makeEmptyTableRow(columnCount: table.cells.count, indent: table.indent)
        }
        if hasSeparatorRowAbove(in: block) {
            // Leaving a populated table row should exit table editing into next block.
            return ""
        }
        return ""
    }

    return ""
}

private func makeFenceAutoCompletionAction(block: String, activeLine: String) -> BlockReturnAction? {
    guard let fence = parseFenceToken(activeLine) else { return nil }
    let lines = block.components(separatedBy: "\n")
    guard let lastLine = lines.last, lastLine == activeLine else { return nil }

    var openFenceChar: Character?
    var openFenceLength = 0
    for line in lines.dropLast() {
        guard let token = parseFenceToken(line) else { continue }
        if openFenceChar == nil {
            openFenceChar = token.char
            openFenceLength = token.length
            continue
        }
        if token.char == openFenceChar, token.length >= openFenceLength {
            openFenceChar = nil
            openFenceLength = 0
        }
    }

    // Only auto-close when the trailing fence is opening a new code block.
    guard openFenceChar == nil else { return nil }

    let indent = String(lastLine.prefix { $0 == " " || $0 == "\t" })
    let marker = String(repeating: String(fence.char), count: fence.length)
    let closingFence = indent + marker
    let selection = (block as NSString).length + 1
    return BlockReturnAction(
        currentBlock: block,
        nextBlock: "\n" + closingFence,
        sameBlockSelectionInUpdatedBlock: selection
    )
}

private func hasSeparatorRowAbove(in block: String) -> Bool {
    let lines = block.components(separatedBy: "\n")
    return lines.dropLast().contains { candidate in
        guard let row = parseTableRow(candidate) else { return false }
        return row.isSeparatorRow
    }
}

private func trailingTableRowCount(in block: String) -> Int {
    let lines = block.components(separatedBy: "\n")
    var count = 0
    for line in lines.reversed() {
        guard parseTableRow(line) != nil else { break }
        count += 1
    }
    return count
}

private func trailingLine(in block: String) -> String {
    if let range = block.range(of: "\n", options: .backwards) {
        return String(block[range.upperBound...])
    }
    return block
}

private func looksLikeTableRow(_ line: String) -> Bool {
    parseTableRow(line) != nil
}

private struct TableRow {
    let cells: [String]
    let indent: String
    let isSeparatorRow: Bool
    let isAllEmpty: Bool
}

private func parseTableRow(_ line: String) -> TableRow? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, trimmed.contains("|") else { return nil }
    let likelyTableSyntax = trimmed.hasPrefix("|")
        || trimmed.hasSuffix("|")
        || trimmed.contains(" | ")
        || trimmed.contains("| ")
        || trimmed.contains(" |")
    guard likelyTableSyntax else { return nil }

    var body = trimmed
    if body.hasPrefix("|") { body.removeFirst() }
    if body.hasSuffix("|") { body.removeLast() }

    let rawCells = body.split(separator: "|", omittingEmptySubsequences: false)
    guard rawCells.count >= 2 else { return nil }
    let cells = rawCells.map { String($0).trimmingCharacters(in: .whitespaces) }

    let isSeparatorRow = cells.allSatisfy { cell in
        let token = cell.replacingOccurrences(of: " ", with: "")
        let dashCount = token.filter { $0 == "-" }.count
        guard dashCount >= 3 else { return false }
        return token.allSatisfy { $0 == "-" || $0 == ":" }
    }
    let isAllEmpty = cells.allSatisfy { $0.isEmpty }
    let indent = String(line.prefix { $0 == " " || $0 == "\t" })
    return TableRow(cells: cells, indent: indent, isSeparatorRow: isSeparatorRow, isAllEmpty: isAllEmpty)
}

private func makeEmptyTableRow(columnCount: Int, indent: String) -> String {
    guard columnCount > 0 else { return "" }
    let cells = Array(repeating: "", count: columnCount).joined(separator: " | ")
    return indent + "| " + cells + " |"
}

private func captureGroups(pattern: String, in text: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = text as NSString
    guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
          match.numberOfRanges >= 2 else {
        return nil
    }

    var output: [String] = []
    for i in 1..<match.numberOfRanges {
        output.append(ns.substring(with: match.range(at: i)))
    }
    return output
}

private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
    let safeLocation = min(max(0, range.location), maxLength)
    let maxSelectionLength = max(0, maxLength - safeLocation)
    let safeLength = min(max(0, range.length), maxSelectionLength)
    return NSRange(location: safeLocation, length: safeLength)
}

private func lineRangeCoveringSelection(_ selection: NSRange, in nsText: NSString) -> NSRange {
    guard nsText.length > 0 else { return NSRange(location: 0, length: 0) }

    let startLocation = min(max(0, selection.location), nsText.length)
    let endLocation = min(nsText.length, selection.location + selection.length)

    let startLine = nsText.lineRange(for: NSRange(location: startLocation, length: 0))
    let endProbeLocation = selection.length > 0 ? max(startLocation, endLocation - 1) : endLocation
    let endLine = nsText.lineRange(for: NSRange(location: endProbeLocation, length: 0))
    return NSUnionRange(startLine, endLine)
}

private func transformLine(_ line: String, style: MarkdownLineStyle) -> String {
    switch style {
    case .heading(let level):
        return toggleHeadingLine(line, level: level)
    case .unorderedList:
        return toggleUnorderedListLine(line)
    case .orderedList:
        return toggleOrderedListLine(line)
    case .blockquote:
        return toggleBlockquoteLine(line)
    }
}

private func toggleHeadingLine(_ line: String, level: Int) -> String {
    let safeLevel = min(max(1, level), 6)
    let marker = String(repeating: "#", count: safeLevel) + " "
    let (indent, content) = splitLeadingIndent(line)

    if content.hasPrefix(marker) {
        return indent + String(content.dropFirst(marker.count))
    }

    let normalized = content.replacingOccurrences(
        of: #"^#{1,6}\s+"#,
        with: "",
        options: .regularExpression
    )
    return indent + marker + normalized
}

private func toggleUnorderedListLine(_ line: String) -> String {
    if let unordered = captureGroups(pattern: #"^(\s*)[-+*]\s+(.*)$"#, in: line), unordered.count == 2 {
        return unordered[0] + unordered[1]
    }

    if let ordered = captureGroups(pattern: #"^(\s*)\d+\.\s+(.*)$"#, in: line), ordered.count == 2 {
        return ordered[0] + "- " + ordered[1]
    }

    let (indent, content) = splitLeadingIndent(line)
    return indent + "- " + content
}

private func toggleOrderedListLine(_ line: String) -> String {
    if let ordered = captureGroups(pattern: #"^(\s*)\d+\.\s+(.*)$"#, in: line), ordered.count == 2 {
        return ordered[0] + ordered[1]
    }

    if let unordered = captureGroups(pattern: #"^(\s*)[-+*]\s+(.*)$"#, in: line), unordered.count == 2 {
        return unordered[0] + "1. " + unordered[1]
    }

    let (indent, content) = splitLeadingIndent(line)
    return indent + "1. " + content
}

private func toggleBlockquoteLine(_ line: String) -> String {
    if let quote = captureGroups(pattern: #"^(\s*)>\s?(.*)$"#, in: line), quote.count == 2 {
        return quote[0] + quote[1]
    }

    let (indent, content) = splitLeadingIndent(line)
    return indent + "> " + content
}

private func splitLeadingIndent(_ line: String) -> (indent: String, content: String) {
    let indent = String(line.prefix { $0 == " " || $0 == "\t" })
    let content = String(line.dropFirst(indent.count))
    return (indent, content)
}

private func wordRangeAroundCaret(in text: String, caret: Int) -> NSRange? {
    let nsText = text as NSString
    let length = nsText.length
    guard length > 0 else { return nil }

    let clampedCaret = min(max(0, caret), length)
    var candidates: [Int] = [clampedCaret]
    if clampedCaret > 0 {
        candidates.append(clampedCaret - 1)
    }

    for candidate in candidates {
        if let range = wordRange(in: text, containingUTF16Index: candidate) {
            return range
        }
    }
    return nil
}

private func wordRange(in text: String, containingUTF16Index index: Int) -> NSRange? {
    guard !text.isEmpty else { return nil }
    var match: NSRange?
    text.enumerateSubstrings(
        in: text.startIndex..<text.endIndex,
        options: [.byWords, .substringNotRequired]
    ) { _, range, _, stop in
        let nsRange = NSRange(range, in: text)
        guard nsRange.length > 0 else { return }
        let upperBound = nsRange.location + nsRange.length
        if nsRange.location <= index && index < upperBound {
            match = nsRange
            stop = true
        }
    }
    return match
}
