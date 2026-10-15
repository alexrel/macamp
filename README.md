# MacAmp

> A pixel-perfect Winamp 2.91 implementation for macOS in SwiftUI.

MacAmp is a high-fidelity recreation of the classic Winamp experience, built using modern macOS technology (SwiftUI & AppKit). It supports native Winamp skins, 1x/2x scaling, and the original interaction model.

## Quick Start

```bash
# Build the application
./build.sh app

# Run the player
./build.sh run
```

## Key Features

- **Pixel-Perfect Scaling**: Supports original 1x and modern 2x Retian scales.
- **Zero-Flash Window Management**: Native AppKit window hacks for smooth resizing and dragging.
- **Winamp Skin Support**: Fully compatible with classic BMP skin formats.

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](docs/getting-started.md) | Installation and setup |
| [UI Standards](docs/ui-development-standards.md) | Hit-testing and layering rules (Crucial) |
| [Architecture](docs/architecture.md) | Project structure and models |
| [Skin Specifications](docs/SKIN-SPECIFICATIONS.md) | BMP mapping and coordinate offsets |

## License

MIT
