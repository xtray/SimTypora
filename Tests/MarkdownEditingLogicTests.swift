import Foundation

private enum TestFailure: Error {
    case failed(String)
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw TestFailure.failed("\(message)\nexpected: \(expected)\nactual:   \(actual)")
    }
}

private func expectTrue(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TestFailure.failed(message)
    }
}

private func run(_ name: String, _ body: () throws -> Void) throws {
    do {
        try body()
        print("[PASS] \(name)")
    } catch {
        print("[FAIL] \(name): \(error)")
        throw error
    }
}

#if MARKDOWN_LOGIC_TEST_MAIN
@main
struct MarkdownEditingLogicTests {
    static func main() {
        do {
            try run("split basic blocks") {
                let blocks = splitMarkdownBlocks("# Title\n\nParagraph")
                try expectEqual(blocks, ["# Title", "Paragraph"], "splitMarkdownBlocks should split on blank lines")
            }

            try run("split keeps fenced code together") {
                let markdown = "```swift\nprint(\"hi\")\n```\n\nTail"
                let blocks = splitMarkdownBlocks(markdown)
                try expectEqual(blocks, ["```swift\nprint(\"hi\")\n```", "Tail"], "fenced code block should stay in one block")
            }

            try run("split keeps trailing editable block") {
                let blocks = splitMarkdownBlocks("Hello\n\n")
                try expectEqual(blocks, ["Hello", ""], "ending with a separator should keep trailing empty block")
            }

            try run("plain paragraph enter creates next block") {
                let block = "Plain paragraph"
                let selection = (block as NSString).length
                let action = makeBlockReturnAction(block: block, selection: selection)
                try expectTrue(action != nil, "enter at paragraph end should split block")
                try expectEqual(action?.nextBlock ?? "<nil>", "", "paragraph should continue with empty block")
            }

            try run("unordered list continues marker") {
                let block = "- item"
                let action = makeBlockReturnAction(block: block, selection: (block as NSString).length)
                try expectEqual(action?.nextBlock ?? "<nil>", "- ", "unordered list should continue with same marker")
            }

            try run("task list continues unchecked item") {
                let block = "- [x] done"
                let action = makeBlockReturnAction(block: block, selection: (block as NSString).length)
                try expectEqual(action?.nextBlock ?? "<nil>", "- [ ] ", "task list should continue with unchecked marker")
            }

            try run("ordered list increments index") {
                let block = "2. second"
                let action = makeBlockReturnAction(block: block, selection: (block as NSString).length)
                try expectEqual(action?.nextBlock ?? "<nil>", "3. ", "ordered list should increment index")
            }

            try run("blockquote continues quote prefix") {
                let block = "> quoted"
                let action = makeBlockReturnAction(block: block, selection: (block as NSString).length)
                try expectEqual(action?.nextBlock ?? "<nil>", "> ", "blockquote should continue quote prefix")
            }

            try run("enter in middle should not split") {
                let block = "middle"
                let action = makeBlockReturnAction(block: block, selection: 3)
                try expectEqual(action, nil, "enter away from end should keep editing current block")
            }

            try run("task toggle updates targeted item") {
                let block = "- [ ] first\n- [x] second"
                let toggled = toggleTaskStateAtIndex(block, taskIndex: 1)
                try expectEqual(toggled, "- [ ] first\n- [ ] second", "toggle should flip task by visible index")
            }

            try run("backspace at block start merges with previous block") {
                let previous = "# Title"
                let current = "Paragraph"
                let action = makeBlockBackspaceAction(
                    previousBlock: previous,
                    currentBlock: current,
                    selection: 0
                )
                try expectTrue(action != nil, "backspace at start should merge blocks")
                try expectEqual(action?.mergedBlock ?? "<nil>", "# Title\nParagraph", "merge should remove one block separator newline")
                try expectEqual(action?.selectionInMergedBlock ?? -1, 8, "caret should land at merge boundary")
            }

            try run("backspace away from block start should not merge") {
                let action = makeBlockBackspaceAction(
                    previousBlock: "A",
                    currentBlock: "B",
                    selection: 1
                )
                try expectEqual(action, nil, "only block-start backspace should be intercepted")
            }

            try run("end editing should deactivate only active block") {
                try expectTrue(
                    shouldDeactivateForEndedBlock(activeBlockIndex: 2, endedBlockIndex: 2),
                    "ending active block should exit edit mode"
                )
                try expectTrue(
                    !shouldDeactivateForEndedBlock(activeBlockIndex: 3, endedBlockIndex: 2),
                    "stale block ending should not cancel newly activated block"
                )
                try expectTrue(
                    !shouldDeactivateForEndedBlock(activeBlockIndex: nil, endedBlockIndex: 2),
                    "no active block should remain unchanged"
                )
            }

            try run("inserting block shifts cached heights after insertion point") {
                let heights: [Int: CGFloat] = [0: 48, 1: 66, 2: 90]
                let shifted = shiftedRenderedHeightsForInsertion(heights, at: 2)
                try expectEqual(
                    shifted,
                    [0: 48, 1: 66, 3: 90],
                    "heights at and after insertion point should shift down by one index"
                )
            }

            try run("removing block shifts cached heights after removal point") {
                let heights: [Int: CGFloat] = [0: 48, 1: 66, 2: 90, 3: 120]
                let shifted = shiftedRenderedHeightsForRemoval(heights, at: 1)
                try expectEqual(
                    shifted,
                    [0: 48, 1: 90, 2: 120],
                    "heights after removed index should shift up by one index"
                )
            }

            try run("list continuation should stay in same block") {
                try expectTrue(
                    shouldContinueEditingInSameBlock(block: "- item", continuation: "- "),
                    "unordered list continuation should append in current block"
                )
                try expectTrue(
                    shouldContinueEditingInSameBlock(block: "1. item", continuation: "2. "),
                    "ordered list continuation should append in current block"
                )
                try expectTrue(
                    shouldContinueEditingInSameBlock(block: "> quote", continuation: "> "),
                    "quote continuation should append in current block"
                )
            }

            try run("non-continuation should split into next block") {
                try expectTrue(
                    !shouldContinueEditingInSameBlock(block: "# Title", continuation: ""),
                    "heading return should split block"
                )
                try expectTrue(
                    !shouldContinueEditingInSameBlock(block: "- ", continuation: ""),
                    "empty list item should exit list into next block"
                )
            }

            try run("table row enter should stay in same block") {
                try expectTrue(
                    shouldContinueEditingInSameBlock(block: "| Name | Value |", continuation: ""),
                    "table header row should continue in current block"
                )
                try expectTrue(
                    shouldContinueEditingInSameBlock(block: "Name | Value", continuation: ""),
                    "table row without boundary pipes should continue in current block"
                )
            }

            try run("table separator continues with empty row template") {
                let block = "| Name | Value |\n| --- | --- |"
                let action = makeBlockReturnAction(block: block, selection: (block as NSString).length)
                try expectEqual(
                    action?.nextBlock ?? "<nil>",
                    "|  |  |",
                    "separator row enter should prepare an editable empty row"
                )
            }

            try run("table data row enter exits to next block") {
                let block = "| Name | Value |\n| --- | --- |\n| Alice | 18 |"
                let action = makeBlockReturnAction(block: block, selection: (block as NSString).length)
                try expectEqual(
                    action?.nextBlock ?? "<nil>",
                    "",
                    "data row enter should exit table editing into the next block"
                )
                try expectTrue(
                    !shouldContinueEditingInSameBlock(block: block, continuation: action?.nextBlock ?? ""),
                    "data row should not force staying in the same block"
                )
            }

            try run("empty table row enter exits table into next block") {
                try expectTrue(
                    !shouldContinueEditingInSameBlock(block: "|  |  |", continuation: ""),
                    "empty table row should allow splitting to next block"
                )
            }

            try run("invalid separator row should not trap table editing") {
                let block = "| a | c |\n| -- | -- |"
                let action = makeBlockReturnAction(block: block, selection: (block as NSString).length)
                try expectEqual(
                    action?.nextBlock ?? "<nil>",
                    "",
                    "non-standard separator should not be treated as a valid table continuation"
                )
                try expectTrue(
                    !shouldContinueEditingInSameBlock(block: block, continuation: action?.nextBlock ?? ""),
                    "non-standard separator should allow exiting to next block"
                )
            }

            try run("code fence enter auto completes closing fence") {
                let block = "```swift"
                let action = makeBlockReturnAction(block: block, selection: (block as NSString).length)
                try expectTrue(action != nil, "fence opening line should produce return action")
                try expectEqual(
                    action?.nextBlock ?? "<nil>",
                    "\n```",
                    "fence opening return should append a closing fence template"
                )
                try expectEqual(
                    action?.sameBlockSelectionInUpdatedBlock ?? -1,
                    (block as NSString).length + 1,
                    "caret should move into the blank line between opening and closing fence"
                )
            }

            try run("closing fence enter should not auto complete again") {
                let block = "```swift\nprint(\"hi\")\n```"
                let action = makeBlockReturnAction(block: block, selection: (block as NSString).length)
                try expectTrue(action != nil, "closing fence line should still be handled")
                try expectEqual(action?.nextBlock ?? "<nil>", "", "closing fence should exit to next block")
                try expectEqual(
                    action?.sameBlockSelectionInUpdatedBlock ?? -1,
                    -1,
                    "closing fence return should not force same-block cursor placement"
                )
            }

            try run("inline bold wraps selected text") {
                let action = applyInlineMarkdownStyle(
                    .bold,
                    in: "hello world",
                    selection: NSRange(location: 0, length: 5)
                )
                try expectEqual(action.updatedText, "**hello** world", "bold shortcut should wrap selection with **")
                try expectEqual(action.updatedSelection.location, 2, "selection should move inside opening marker")
                try expectEqual(action.updatedSelection.length, 5, "selection length should keep selected text length")
            }

            try run("inline bold toggles off when selection is already wrapped") {
                let action = applyInlineMarkdownStyle(
                    .bold,
                    in: "**hello** world",
                    selection: NSRange(location: 2, length: 5)
                )
                try expectEqual(action.updatedText, "hello world", "bold shortcut should remove surrounding ** when toggling off")
                try expectEqual(action.updatedSelection.location, 0, "selection should shift left after removing opening marker")
                try expectEqual(action.updatedSelection.length, 5, "selection should remain on original content")
            }

            try run("inline italic styles current word at caret when selection is empty") {
                let action = applyInlineMarkdownStyle(
                    .italic,
                    in: "hello world",
                    selection: NSRange(location: 2, length: 0)
                )
                try expectEqual(action.updatedText, "*hello* world", "italic shortcut should style the word around caret when no selection")
                try expectEqual(action.updatedSelection.location, 1, "selection should move to the styled word content")
                try expectEqual(action.updatedSelection.length, 5, "selection should expand to the styled word length")
            }

            try run("inline italic falls back to marker pair when caret is not on a word") {
                let action = applyInlineMarkdownStyle(
                    .italic,
                    in: "hello  world",
                    selection: NSRange(location: 6, length: 0)
                )
                try expectEqual(action.updatedText, "hello ** world", "italic shortcut should insert marker pair when no word can be resolved")
                try expectEqual(action.updatedSelection.location, 7, "caret should be placed between inserted markers")
                try expectEqual(action.updatedSelection.length, 0, "fallback insertion should keep zero-length selection")
            }

            try run("inline strikethrough wraps selected text") {
                let action = applyInlineMarkdownStyle(
                    .strikethrough,
                    in: "todo item",
                    selection: NSRange(location: 0, length: 4)
                )
                try expectEqual(action.updatedText, "~~todo~~ item", "strikethrough shortcut should wrap selection with ~~")
                try expectEqual(action.updatedSelection.location, 2, "selection should move inside opening marker")
                try expectEqual(action.updatedSelection.length, 4, "selection length should keep selected text length")
            }

            try run("inline code styles current word at caret when selection is empty") {
                let action = applyInlineMarkdownStyle(
                    .inlineCode,
                    in: "hello world",
                    selection: NSRange(location: 8, length: 0)
                )
                try expectEqual(action.updatedText, "hello `world`", "inline code shortcut should style the current word")
                try expectEqual(action.updatedSelection.location, 7, "selection should move inside inserted marker")
                try expectEqual(action.updatedSelection.length, 5, "selection should cover the styled word")
            }

            try run("heading level shortcut toggles heading on and off") {
                let on = applyLineMarkdownStyle(
                    .heading(level: 2),
                    in: "Title",
                    selection: NSRange(location: 0, length: 0)
                )
                try expectEqual(on.updatedText, "## Title", "heading shortcut should prepend heading marker")

                let off = applyLineMarkdownStyle(
                    .heading(level: 2),
                    in: on.updatedText,
                    selection: NSRange(location: 0, length: 0)
                )
                try expectEqual(off.updatedText, "Title", "same heading shortcut should remove existing same-level marker")
            }

            try run("unordered list shortcut toggles plain line and can convert ordered list") {
                let on = applyLineMarkdownStyle(
                    .unorderedList,
                    in: "item",
                    selection: NSRange(location: 0, length: 0)
                )
                try expectEqual(on.updatedText, "- item", "unordered list shortcut should prepend '- '")

                let off = applyLineMarkdownStyle(
                    .unorderedList,
                    in: on.updatedText,
                    selection: NSRange(location: 0, length: 0)
                )
                try expectEqual(off.updatedText, "item", "unordered list shortcut should toggle off marker")

                let converted = applyLineMarkdownStyle(
                    .unorderedList,
                    in: "1. item",
                    selection: NSRange(location: 0, length: 0)
                )
                try expectEqual(converted.updatedText, "- item", "unordered list shortcut should convert ordered list marker")
            }

            try run("ordered list shortcut toggles plain line and can convert unordered list") {
                let on = applyLineMarkdownStyle(
                    .orderedList,
                    in: "item",
                    selection: NSRange(location: 0, length: 0)
                )
                try expectEqual(on.updatedText, "1. item", "ordered list shortcut should prepend '1. '")

                let off = applyLineMarkdownStyle(
                    .orderedList,
                    in: on.updatedText,
                    selection: NSRange(location: 0, length: 0)
                )
                try expectEqual(off.updatedText, "item", "ordered list shortcut should toggle off marker")

                let converted = applyLineMarkdownStyle(
                    .orderedList,
                    in: "- item",
                    selection: NSRange(location: 0, length: 0)
                )
                try expectEqual(converted.updatedText, "1. item", "ordered list shortcut should convert unordered list marker")
            }

            try run("blockquote shortcut toggles quote marker") {
                let on = applyLineMarkdownStyle(
                    .blockquote,
                    in: "quoted line",
                    selection: NSRange(location: 0, length: 0)
                )
                try expectEqual(on.updatedText, "> quoted line", "blockquote shortcut should prepend quote marker")

                let off = applyLineMarkdownStyle(
                    .blockquote,
                    in: on.updatedText,
                    selection: NSRange(location: 0, length: 0)
                )
                try expectEqual(off.updatedText, "quoted line", "blockquote shortcut should remove quote marker when toggled")
            }

            print("All markdown editing logic tests passed")
        } catch {
            exit(1)
        }
    }
}
#endif
