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
