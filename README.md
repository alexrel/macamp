# MacAmp

> A pixel-perfect Winamp 2.95 reproduction for macOS in SwiftUI and AppKit.

MacAmp is a high-fidelity recreation of the classic Winamp experience, built using modern macOS technology (SwiftUI & AppKit). It supports native Winamp skins, 1x/2x scaling, and the original interaction model.

## Installation

MacAmp is not signed with an Apple Developer ID, so macOS can't verify it on first launch.

1. Open the DMG and drag **MacAmp** to **Applications**. Don't run it from Downloads: macOS starts
   downloaded apps from a read-only location, and the document icon chooser (Preferences ▸ Setup ▸
   File types) can't change icons from there.
2. Launch MacAmp. When macOS says it can't verify the developer, open **System Settings ▸ Privacy &
   Security** and click **Open Anyway**.

   Or remove the quarantine flag in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/MacAmp.app
   ```

Why the document icon chooser works: Finder takes document icons from the app bundle, so MacAmp swaps
the icon inside `MacAmp.app` and re-signs itself with a local (ad-hoc) signature. That is only possible
because the app isn't signed with a Developer ID, which a local re-sign would replace.

## Quick Start

```bash
# Build the application (Debug)
./build.sh

# Build and run the player
./build.sh run

# Release build (Apple Silicon + Intel) packed into build/MacAmp-<version>.dmg
./build.sh dmg

# Run the test suite
./build.sh test
```

## Key Features

- **Pixel-Perfect Scaling**: Supports original 1x and modern 2x Retian scales.
- **Zero-Flash Window Management**: Native AppKit window hacks for smooth resizing and dragging.
- **Winamp Skin Support**: Fully compatible with classic BMP skin formats.

## License

MIT
