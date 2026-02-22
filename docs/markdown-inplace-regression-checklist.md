# Markdown In-Place Regression Checklist

## Scope

- In-place editing/render switching for block-based Markdown editing.
- Table editing flow with standard separator row (`---`).

## Manual Cases

1. New file initial state
Create a new empty document, then confirm caret is active in the first editable block.

2. Standard table entry should render and recover
Type:
```markdown
| a | c |
| --- | --- |
| 1 | 2 |
```
Press `Enter` at end of `| 1 | 2 |`.
Expected: current table block remains rendered, and a new block is created below in raw editing mode.

3. Continue with non-table Markdown after table
In the new block below the table, type:
```markdown
## heading after table
```
Click outside current editing block.
Expected: heading is rendered in `<h2>` style, not raw markdown.

4. Invalid separator should not trap editing
Type:
```markdown
| a | c |
| -- | -- |
```
Press `Enter`.
Expected: editor exits current block to a new block, and subsequent Markdown still renders normally.
Note: `| -- | -- |` is not a valid table separator.

5. Post-table block types still render
After completing Case 2 or Case 4, add each in separate blocks:
```markdown
- list item
```
```markdown
> quote
```
~~~markdown
```swift
print("ok")
```
~~~
Expected: list, quote, and fenced code block all render normally after deactivating edit mode.

## Build Signal

Run:
```bash
xcodebuild -project SimTypora.xcodeproj -scheme SimTypora -configuration Debug -sdk macosx -derivedDataPath /tmp/SimTyporaDerivedData build
```
Expected: build succeeds and does not emit `Skipping duplicate build file in Compile Sources build phase`.
