# SimTypora

A lightweight macOS Markdown editor prototype with Typora-like in-place rendering.

## Requirements

- macOS 13.0+
- Xcode 15+
- Command line tools: `xcodebuild`

## Build And Run (Xcode)

1. Open `SimTypora.xcodeproj` in Xcode.
2. Select scheme: `SimTypora`.
3. Select destination: `My Mac`.
4. Press `Run` (`Cmd + R`).

## Build From Command Line

Run from project root:

```bash
xcodebuild \
  -project SimTypora.xcodeproj \
  -scheme SimTypora \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath /tmp/SimTyporaDerivedData \
  build
```

Expected result:

- Output contains: `** BUILD SUCCEEDED **`
- App path: `/tmp/SimTyporaDerivedData/Build/Products/Debug/SimTypora.app`

## Notes

- If default DerivedData path is not writable in your environment, keep using `-derivedDataPath /tmp/SimTyporaDerivedData`.

## Regression Checklist

- In-place markdown editing/rendering regression checklist: `docs/markdown-inplace-regression-checklist.md`

## Keyboard Shortcuts

- `Cmd/Ctrl + C`: Copy
- `Cmd/Ctrl + V`: Paste
- `Cmd/Ctrl + X`: Cut
- `Cmd/Ctrl + B`: Toggle bold (`**text**`)
- `Cmd/Ctrl + I`: Toggle italic (`*text*`)
- `Cmd/Ctrl + Shift + X`: Toggle strikethrough (`~~text~~`)
- `Cmd/Ctrl + K`: Toggle inline code (`` `code` ``)
- `Cmd/Ctrl + 1 / 2 / 3`: Toggle heading level `H1 / H2 / H3` on current line(s)
- `Cmd/Ctrl + Shift + 7`: Toggle ordered list on current line(s)
- `Cmd/Ctrl + Shift + 8`: Toggle unordered list on current line(s)
- `Cmd/Ctrl + Shift + 9`: Toggle blockquote on current line(s)

Notes:
- With no selection, inline style shortcuts (B/I/Shift+X/K) first try to style the word under caret; if no word is detected, they insert paired markdown markers at caret.
- Line-style shortcuts (`1/2/3`, `Shift+7/8/9`) apply to the current line or all selected lines.

## GitHub Release (macOS package)

This repository includes a workflow at `.github/workflows/release-macos.yml`.

When you push a tag like `v1.0.0`, GitHub Actions will:

1. Build `SimTypora.app` in `Release` mode on macOS.
2. Zip it as `SimTypora-v1.0.0-macOS.zip`.
3. Create/update a GitHub Release and upload the zip as a release asset.

Example:

```bash
git tag v1.0.0
git push origin v1.0.0
```
