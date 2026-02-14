# SimTypora In-Place Editing Design

## Goal
- Keep real-time markdown preview in one editor surface.
- Show raw markdown on the cursor line, keep other lines rendered.

## Architecture
- `sourceText` is the only truth.
- The text view displays a line-by-line projection of `sourceText`.
- Non-focused lines are rendered via markdown line renderer.
- Focused line is rendered as raw markdown source.

## Data Flow
1. Initial render: build display lines from `sourceText` + `focusedLineIndex`.
2. Cursor move: recompute `focusedLineIndex`, rerender projection.
3. Text edit: compute changed line range from display diff, patch `sourceText`, rerender.
4. Sync back to SwiftUI binding after each source update.

## Error Handling
- Guard invalid ranges when selection exceeds bounds.
- Ignore internal updates (`isUpdating`) to prevent feedback loops.
- Fall back to plain text line render on parse edge cases.

## Testing Strategy
- Build with local DerivedData path.
- Manual smoke checks: heading/list/quote/code lines, cursor switching, line split/merge.
