# Typora In-Place Line Focus Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make SimTypora behave like Typora line-focus editing: rendered preview for non-focus lines and raw markdown for the cursor line.

**Architecture:** Maintain canonical markdown in `sourceText`, render a projection for display, and patch source from focused-line edits via line-diff mapping.

**Tech Stack:** SwiftUI, AppKit (`NSTextView`), regex-based markdown line renderer.

---

### Task 1: Replace fragile hover-toggle logic with line-focus projection

**Files:**
- Modify: `Sources/Views/ContentView.swift`

**Step 1: Write failing behavior checklist**
- Current code rewrites displayed text and loses source markdown fidelity after edit.

**Step 2: Implement projection model**
- Add `DisplayState` with `sourceText`, `displayLines`, `focusedLineIndex`.
- Render non-focused lines with markdown renderer, focused line as raw text.

**Step 3: Add selection-driven focus updates**
- Implement `textViewDidChangeSelection` to refresh focused line projection.

**Step 4: Verify build**
Run: `xcodebuild -project SimTypora.xcodeproj -scheme SimTypora -configuration Debug -sdk macosx -derivedDataPath /tmp/SimTyporaDerivedData build`
Expected: `** BUILD SUCCEEDED **`

### Task 2: Preserve source text while editing focused line

**Files:**
- Modify: `Sources/Views/ContentView.swift`

**Step 1: Add line-diff patching**
- On `textDidChange`, compare previous display lines and current lines.
- Replace matching source line range with edited lines only.

**Step 2: Sync state**
- Update `parent.text` from canonical `sourceText` only.

**Step 3: Verify behavior manually**
- Switch cursor between lines, edit heading/list/quote lines, confirm source line is editable raw markdown.

### Task 3: Cleanup and robustness

**Files:**
- Modify: `Sources/Views/ContentView.swift`

**Step 1: Remove old mouse tracking/source syntax injection path**
- Delete tracking area and hover replacement code.

**Step 2: Add safe guards**
- Bound-check line/selection indexes and no-op for internal updates.

**Step 3: Final verification**
Run same build command and spot-check app launch.
