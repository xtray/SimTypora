import SwiftUI
import AppKit

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
        let textView = HoverAwareTextView(frame: .zero)
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

        textView.onMouseMoved = { [weak coordinator = context.coordinator] point in
            coordinator?.handleMouseMoved(point: point)
        }
        textView.onMouseExited = { [weak coordinator = context.coordinator] in
            coordinator?.handleMouseExited()
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

        private var isUpdating = false
        private var sourceText = ""
        private var hoveredLineIndex: Int?
        private var lastRenderedLines: [String] = []

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
        }

        func attach(to textView: NSTextView, initialText: String) {
            self.textView = textView
            sourceText = initialText
            hoveredLineIndex = nil
            renderProjection(keepSelection: false)
        }

        func applyExternalText(_ text: String) {
            guard !isUpdating, text != sourceText else { return }
            sourceText = text
            renderProjection(keepSelection: true)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // Selection moves should not force source-markup visibility.
            guard !isUpdating else { return }
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }

            let previousDisplayLines = lastRenderedLines
            let currentDisplayLines = textView.string.components(separatedBy: "\n")
            patchSourceLines(previous: previousDisplayLines, current: currentDisplayLines)

            parent.text = sourceText
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
            let sourceLines = sourceText.components(separatedBy: "\n")
            var inCodeBlock = false
            let attributed = NSMutableAttributedString()
            var renderedLines: [String] = []

            for (index, line) in sourceLines.enumerated() {
                let lineAttr: NSAttributedString
                if index == hoveredLineIndex {
                    lineAttr = MarkdownRenderer.shared.renderRawLine(line)
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
                let safeLocation = min(previousSelection.location, (textView.string as NSString).length)
                let safeLength = min(previousSelection.length, (textView.string as NSString).length - safeLocation)
                textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            } else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
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

        func handleMouseMoved(point: NSPoint) {
            guard let textView = textView, !isUpdating else { return }
            let insertionLine = lineIndex(
                of: textView.characterIndexForInsertion(at: point),
                in: textView.string
            )

            if let currentHovered = hoveredLineIndex, insertionLine == currentHovered {
                return
            }

            let newHovered: Int?
            if let hitCharIndex = contentCharacterIndex(at: point, in: textView) {
                newHovered = lineIndex(of: hitCharIndex, in: textView.string)
            } else {
                newHovered = nil
            }

            guard newHovered != hoveredLineIndex else { return }
            hoveredLineIndex = newHovered
            renderProjection(keepSelection: true)
        }

        func handleMouseExited() {
            guard hoveredLineIndex != nil else { return }
            hoveredLineIndex = nil
            renderProjection(keepSelection: true)
        }

        private func contentCharacterIndex(at point: NSPoint, in textView: NSTextView) -> Int? {
            guard
                let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else {
                return nil
            }

            let containerPoint = NSPoint(
                x: point.x - textView.textContainerInset.width,
                y: point.y - textView.textContainerInset.height
            )

            let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

            let glyphRange = NSRange(location: glyphIndex, length: 1)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer).insetBy(dx: -1, dy: -1)
            guard glyphRect.contains(containerPoint) else { return nil }

            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let nsText = textView.string as NSString
            guard charIndex < nsText.length else { return nil }

            let codeUnit = nsText.character(at: charIndex)
            guard let scalar = UnicodeScalar(codeUnit) else { return nil }
            guard !CharacterSet.whitespacesAndNewlines.contains(scalar) else { return nil }

            return charIndex
        }
    }
}

final class HoverAwareTextView: NSTextView {
    var onMouseMoved: ((NSPoint) -> Void)?
    var onMouseExited: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }

        let options: NSTrackingArea.Options = [.inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExited?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
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
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return renderUnorderedList(line)
        }
        if isOrderedList(line) {
            return renderOrderedList(line)
        }
        if line == "---" || line == "***" || line == "___" {
            return renderHorizontalRule()
        }

        return renderInlineMarkdown(line)
    }

    private func isOrderedList(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return false }
        return parts[0].allSatisfy { $0.isNumber }
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

    private func renderUnorderedList(_ line: String) -> NSAttributedString {
        let text = String(line.dropFirst(2))
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 22
        style.headIndent = 22
        style.paragraphSpacing = 4

        let prefix = NSAttributedString(string: "• ", attributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ])

        let content = NSMutableAttributedString(attributedString: renderInlineMarkdown(text))
        content.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: content.length))

        let result = NSMutableAttributedString()
        result.append(prefix)
        result.append(content)
        return result
    }

    private func renderOrderedList(_ line: String) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ".", maxSplits: 1)
        let number = parts.count > 0 ? String(parts[0]) : "1"
        let content = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : trimmed

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 22
        style.headIndent = 22
        style.paragraphSpacing = 4

        let prefix = NSAttributedString(string: number + ". ", attributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ])

        let contentAttr = NSMutableAttributedString(attributedString: renderInlineMarkdown(content))
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
