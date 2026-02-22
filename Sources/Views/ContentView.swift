import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject var document: MarkdownDocument

    var body: some View {
        VStack(spacing: 0) {
            InPlaceMarkdownView(text: $document.content)
        }
        .frame(minWidth: 900, minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(document.fileURL?.lastPathComponent ?? "Markdown Demo")
                    .font(.headline)
            }
        }
    }
}

private struct InPlaceMarkdownView: View {
    @Binding var text: String

    @State private var blocks: [String] = [""]
    @State private var activeBlockIndex: Int?
    @State private var renderedHeights: [Int: CGFloat] = [:]
    @State private var keyMonitor: Any?
    @State private var pendingSelectionOffset: Int?
    @State private var pendingSyncedTexts: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    if activeBlockIndex == index {
                        let renderedHeight = max(32, renderedHeights[index] ?? 32)
                        let editorHeight = max(renderedHeight, estimatedEditorHeight(for: block))
                        BlockEditingTextView(
                            blockIndex: index,
                            text: Binding(
                                get: { blocks[index] },
                                set: { blocks[index] = $0 }
                            ),
                            desiredSelection: Binding(
                                get: { pendingSelectionOffset },
                                set: { pendingSelectionOffset = $0 }
                            ),
                            minHeight: editorHeight,
                            onReturn: { selection in
                                handleReturnInActiveBlock(blockIndex: index, selection: selection)
                            },
                            onBackspaceAtStart: { selection in
                                handleBackspaceInActiveBlock(blockIndex: index, selection: selection)
                            },
                            onEndEditing: { endedBlockIndex in
                                handleEndEditing(blockIndex: endedBlockIndex)
                            }
                        )
                        .frame(height: editorHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                    } else {
                        RenderedBlockView(
                            markdown: block,
                            onActivate: { point in
                                let blockHeight = max(32, renderedHeights[index] ?? 32)
                                activateEditing(at: index, clickPoint: point, renderedHeight: blockHeight)
                            },
                            onToggleTask: { taskIndex in
                                toggleTaskInBlock(blockIndex: index, taskIndex: taskIndex)
                            },
                            height: Binding(
                                get: { renderedHeights[index] ?? 32 },
                                set: { renderedHeights[index] = $0 }
                            )
                        )
                        .frame(height: max(32, renderedHeights[index] ?? 32))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 28)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            blocks = splitMarkdownBlocks(text)
            renderedHeights = [:]
            if text.isEmpty {
                activeBlockIndex = 0
                pendingSelectionOffset = 0
            } else {
                activeBlockIndex = nil
            }
        }
        .onChange(of: text) { newValue in
            if let idx = pendingSyncedTexts.firstIndex(of: newValue) {
                pendingSyncedTexts.remove(at: idx)
                return
            }
            pendingSyncedTexts.removeAll(keepingCapacity: true)
            let currentDraft = joinMarkdownBlocks(blocks)
            guard newValue != currentDraft else { return }
            blocks = splitMarkdownBlocks(newValue)
            renderedHeights = [:]
            if newValue.isEmpty {
                activeBlockIndex = 0
                pendingSelectionOffset = 0
            } else {
                deactivateEditing()
            }
        }
        .onChange(of: blocks) { newBlocks in
            let draft = joinMarkdownBlocks(newBlocks)
            if draft != text {
                pendingSyncedTexts.append(draft)
                text = draft
            }
        }
        .onChange(of: activeBlockIndex) { newValue in
            if newValue == nil {
                removeKeyMonitor()
            } else {
                installKeyMonitor()
            }
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func activateEditing(at index: Int, clickPoint: CGPoint, renderedHeight: CGFloat) {
        activeBlockIndex = index
        pendingSelectionOffset = estimateSelectionOffset(
            in: blocks[index],
            clickPoint: clickPoint,
            renderedHeight: renderedHeight
        )
    }

    private func toggleTaskInBlock(blockIndex: Int, taskIndex: Int) {
        guard blockIndex >= 0, blockIndex < blocks.count else { return }
        blocks[blockIndex] = toggleTaskStateAtIndex(blocks[blockIndex], taskIndex: taskIndex)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard activeBlockIndex != nil else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode
            let isExit = keyCode == 53
            let isCommit = keyCode == 36 && (flags.contains(.command) || flags.contains(.control))
            if isExit || isCommit {
                deactivateEditing()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func deactivateEditing() {
        activeBlockIndex = nil
        pendingSelectionOffset = nil
    }

    private func handleEndEditing(blockIndex: Int) {
        guard shouldDeactivateForEndedBlock(activeBlockIndex: activeBlockIndex, endedBlockIndex: blockIndex) else {
            return
        }
        deactivateEditing()
    }

    private func handleReturnInActiveBlock(blockIndex: Int, selection: Int) -> Bool {
        guard activeBlockIndex == blockIndex else { return false }
        guard blockIndex >= 0, blockIndex < blocks.count else { return false }

        let block = blocks[blockIndex]
        guard let action = makeBlockReturnAction(block: block, selection: selection) else { return false }

        if let desired = action.sameBlockSelectionInUpdatedBlock {
            let updated = block + "\n" + action.nextBlock
            blocks[blockIndex] = updated
            renderedHeights[blockIndex] = nil
            activeBlockIndex = blockIndex
            let maxSelection = (updated as NSString).length
            pendingSelectionOffset = min(max(0, desired), maxSelection)
            return true
        }

        if shouldContinueEditingInSameBlock(block: block, continuation: action.nextBlock) {
            let updated = block + "\n" + action.nextBlock
            blocks[blockIndex] = updated
            renderedHeights[blockIndex] = nil
            activeBlockIndex = blockIndex
            pendingSelectionOffset = (updated as NSString).length
            return true
        }

        blocks[blockIndex] = action.currentBlock
        blocks.insert(action.nextBlock, at: blockIndex + 1)
        renderedHeights = shiftedRenderedHeightsForInsertion(renderedHeights, at: blockIndex + 1)
        activeBlockIndex = blockIndex + 1
        pendingSelectionOffset = action.nextSelection
        return true
    }

    private func handleBackspaceInActiveBlock(blockIndex: Int, selection: Int) -> Bool {
        guard activeBlockIndex == blockIndex else { return false }
        guard blockIndex > 0, blockIndex < blocks.count else { return false }

        guard let action = makeBlockBackspaceAction(
            previousBlock: blocks[blockIndex - 1],
            currentBlock: blocks[blockIndex],
            selection: selection
        ) else {
            return false
        }

        blocks[blockIndex - 1] = action.mergedBlock
        blocks.remove(at: blockIndex)
        renderedHeights = shiftedRenderedHeightsForRemoval(renderedHeights, at: blockIndex)
        activeBlockIndex = blockIndex - 1
        pendingSelectionOffset = action.selectionInMergedBlock
        return true
    }

    private func estimateSelectionOffset(in block: String, clickPoint: CGPoint, renderedHeight: CGFloat) -> Int {
        let lines = block.components(separatedBy: "\n")
        guard !lines.isEmpty else { return 0 }

        let safeHeight = max(1, renderedHeight)
        let normalizedY = max(0, min(clickPoint.y, safeHeight))
        let lineIndex = min(lines.count - 1, Int((normalizedY / safeHeight) * CGFloat(lines.count)))
        let approxColumn = max(0, Int((clickPoint.x - 12) / 8.2))
        return characterOffset(forLine: lineIndex, column: approxColumn, in: block)
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

    private func estimatedEditorHeight(for text: String) -> CGFloat {
        let lineCount = max(1, text.components(separatedBy: "\n").count)
        return max(44, CGFloat(lineCount) * 24 + 10)
    }
}

private struct RenderedBlockView: NSViewRepresentable {
    let markdown: String
    let onActivate: (CGPoint) -> Void
    let onToggleTask: (Int) -> Void
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "toggleTask")
        userContentController.add(context.coordinator, name: "activateBlock")
        let scriptSource = """
        document.addEventListener('mousedown', function(e) {
          const target = e.target;
          if (target && target.tagName === 'INPUT' && target.type === 'checkbox') {
            const idx = target.getAttribute('data-task-index');
            if (idx !== null) {
              e.preventDefault();
              e.stopPropagation();
              window.webkit.messageHandlers.toggleTask.postMessage(parseInt(idx, 10));
            }
            return;
          }
          e.preventDefault();
          window.webkit.messageHandlers.activateBlock.postMessage({ x: e.clientX, y: e.clientY });
        }, true);
        """
        userContentController.addUserScript(
            WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        config.userContentController = userContentController

        let webView = PassthroughWKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false
        webView.enclosingScrollView?.drawsBackground = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.onActivate = onActivate
        context.coordinator.onToggleTask = onToggleTask
        context.coordinator.lastMarkdown = markdown
        context.coordinator.load(markdown: markdown, debounce: false)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onActivate = onActivate
        context.coordinator.onToggleTask = onToggleTask
        guard context.coordinator.lastMarkdown != markdown else { return }
        context.coordinator.height = 32
        context.coordinator.load(markdown: markdown, debounce: false)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat
        weak var webView: WKWebView?
        var lastMarkdown: String = ""
        var currentRenderKey: String = UUID().uuidString
        var onActivate: ((CGPoint) -> Void)?
        var onToggleTask: ((Int) -> Void)?
        private var pendingReload: DispatchWorkItem?

        init(height: Binding<CGFloat>) {
            _height = height
        }

        func load(markdown: String, debounce: Bool) {
            pendingReload?.cancel()
            lastMarkdown = markdown
            let renderKey = UUID().uuidString
            currentRenderKey = renderKey

            let work = DispatchWorkItem { [weak self] in
                guard let self, let webView else { return }
                webView.loadHTMLString(
                    MarkdownHTMLRenderer.shared.renderFragment(markdown, renderKey: renderKey),
                    baseURL: nil
                )
            }
            pendingReload = work

            if debounce {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
            } else {
                DispatchQueue.main.async(execute: work)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let measureScript = """
            (function() {
              const renderKey = document.body ? (document.body.getAttribute('data-render-key') || '') : '';
              const page = document.querySelector('.page');
              const article = document.querySelector('.markdown-body');
              function toNumber(v) {
                const n = Number.parseFloat(v || "0");
                return Number.isFinite(n) ? n : 0;
              }
              function contentHeight(node) {
                if (!node) return 0;
                const rect = node.getBoundingClientRect();
                const style = window.getComputedStyle(node);
                const mt = toNumber(style.marginTop);
                const mb = toNumber(style.marginBottom);
                return rect.height + mt + mb;
              }
              const pageH = contentHeight(page);
              const articleH = contentHeight(article);
              return { key: renderKey, height: Math.ceil(Math.max(pageH, articleH)) };
            })();
            """
            webView.evaluateJavaScript(measureScript) { result, _ in
                if let payload = result as? [String: Any],
                   let key = payload["key"] as? String,
                   let number = payload["height"] as? NSNumber {
                    guard key == self.currentRenderKey else { return }
                    let measured = CGFloat(truncating: number)
                    DispatchQueue.main.async {
                        self.height = max(32, min(10000, measured))
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "toggleTask" {
                if let index = message.body as? Int {
                    onToggleTask?(index)
                } else if let number = message.body as? NSNumber {
                    onToggleTask?(number.intValue)
                }
                return
            }

            if message.name == "activateBlock",
               let payload = message.body as? [String: Any],
               let x = payload["x"] as? CGFloat,
               let y = payload["y"] as? CGFloat {
                onActivate?(CGPoint(x: x, y: y))
            }
        }
    }
}

private struct BlockEditingTextView: NSViewRepresentable {
    let blockIndex: Int
    @Binding var text: String
    @Binding var desiredSelection: Int?
    let minHeight: CGFloat
    let onReturn: (Int) -> Bool
    let onBackspaceAtStart: (Int) -> Bool
    let onEndEditing: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = InPlaceEditingTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: max(1, textView.frame.width),
            height: .greatestFiniteMagnitude
        )
        textView.onEndEditing = { [blockIndex, onEndEditing] in
            onEndEditing(blockIndex)
        }
        textView.string = text

        let scroll = NSScrollView(frame: .zero)
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.documentView = textView
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? InPlaceEditingTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.onEndEditing = { [blockIndex, onEndEditing] in
            onEndEditing(blockIndex)
        }

        let height = max(minHeight, CGFloat(max(1, text.components(separatedBy: "\n").count)) * 24 + 10)
        let width = max(1, nsView.contentSize.width)
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        nsView.frame.size.height = height

        if let desiredSelection {
            let clamped = min(max(0, desiredSelection), (textView.string as NSString).length)
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: clamped, length: 0))
                self.desiredSelection = nil
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockEditingTextView

        init(parent: BlockEditingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let selection = textView.selectedRange()
                if selection.length == 0 {
                    return parent.onReturn(selection.location)
                }
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                let selection = textView.selectedRange()
                if selection.length == 0 {
                    return parent.onBackspaceAtStart(selection.location)
                }
            }
            return false
        }
    }
}

private final class InPlaceEditingTextView: NSTextView {
    var onEndEditing: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        let hasControl = flags.contains(.control)
        guard hasCommand || hasControl else {
            return super.performKeyEquivalent(with: event)
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        if key == "c" {
            copy(self)
            return true
        }
        if key == "v" {
            paste(self)
            return true
        }
        if key == "x", !flags.contains(.shift) {
            cut(self)
            return true
        }
        if key == "1", !flags.contains(.shift) {
            applyLineStyle(.heading(level: 1))
            return true
        }
        if key == "2", !flags.contains(.shift) {
            applyLineStyle(.heading(level: 2))
            return true
        }
        if key == "3", !flags.contains(.shift) {
            applyLineStyle(.heading(level: 3))
            return true
        }
        if key == "7", flags.contains(.shift) {
            applyLineStyle(.orderedList)
            return true
        }
        if key == "8", flags.contains(.shift) {
            applyLineStyle(.unorderedList)
            return true
        }
        if key == "9", flags.contains(.shift) {
            applyLineStyle(.blockquote)
            return true
        }
        if key == "b" {
            applyInlineStyle(.bold)
            return true
        }
        if key == "i" {
            applyInlineStyle(.italic)
            return true
        }
        if key == "k" {
            applyInlineStyle(.inlineCode)
            return true
        }
        if key == "x", flags.contains(.shift) {
            applyInlineStyle(.strikethrough)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            onEndEditing?()
        }
        return ok
    }

    private func applyInlineStyle(_ style: MarkdownInlineStyle) {
        let action = applyInlineMarkdownStyle(style, in: string, selection: selectedRange())
        let currentSelection = selectedRange()
        guard action.updatedText != string || action.updatedSelection != currentSelection else { return }

        string = action.updatedText
        setSelectedRange(action.updatedSelection)
        didChangeText()
    }

    private func applyLineStyle(_ style: MarkdownLineStyle) {
        let action = applyLineMarkdownStyle(style, in: string, selection: selectedRange())
        let currentSelection = selectedRange()
        guard action.updatedText != string || action.updatedSelection != currentSelection else { return }

        string = action.updatedText
        setSelectedRange(action.updatedSelection)
        didChangeText()
    }
}

private final class PassthroughWKWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if let superview {
            superview.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
