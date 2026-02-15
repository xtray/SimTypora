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
