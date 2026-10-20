[Back to README](../README.md) · [Next Topic →](architecture.md)

# UI Development Standards (MacAmp)

This document outlines the strict rules for building dense Winamp-style interfaces in SwiftUI to ensure consistent hit-testing and avoid interaction regressions.

## 1. Interaction Layering (The Z-Index Rule)

To prevent invisible containers from intercepting mouse events, use explicit priority tiers:

| Tier | Z-Index | Components |
|------|---------|------------|
| **Global Controls** | `600` | Menu (Option), Mini, Shade Toggle, Close |
| **Playback Layer** | `500` | Play, Pause, Stop, Prev, Next, Eject |
| **Slider Layer** | `400` | Progress Slider, Seek Bar (Interactive) |
| **UI Interaction** | `300` | Invisible hit-test surfaces (Time toggle) |
| **Display Layer** | `250` | Numerical digits (Time), Text overlays |
| **Visualizer Layer**| `200` | Spectrum / Oscilloscope (Interactive) |
| **Sub-Controls** | `150` | Volume Slider, Balance Slider |
| **Navigation Layer**| `100` | Window Drag Areas (Draggable Overlay) |
| **Decorative** | `50` | Background images, non-interactive sprites |
| **Base** | `0` | Root Layout Background |

## 2. Hit-Test Transparency

Every non-interactive element (especially background images) **MUST** explicitly disable hit-testing:

```swift
Image("NOT_BUTTON")
    .allowsHitTesting(false)
```

## 3. Component Framing

Winamp interfaces are pixel-perfect and dense. Components must not "spill" outside their intended boundaries.

1. **Strict Frames**: Always apply `.frame(width: ..., height: ...)` matching the original BMP specification.
2. **Clipping**: Apply `.clipped()` to every component that uses offsets or internal ZStacks to prevent "ghost" hit-test zones outside the visual area.
3. **Content Shape**: For buttons with transparent parts, use `.contentShape(Rectangle())` to ensure the entire area is clickable.

## 4. Scaling Management

MacAmp supports 1x and 2x scales via `.scaleEffect`.

- **Global Scaling**: Use `.scaleEffect(scale, anchor: .topLeading)` on the root component.
- **Outer Frame**: Follow the scale effect with a frame that accounts for the scale:
  ```swift
  .scaleEffect(scale, anchor: .topLeading)
  .frame(width: originalWidth * scale, height: originalHeight * scale, alignment: .topLeading)
  ```
- **Internal Scaling**: Do NOT multiply frames inside components by `scale` if the parent is already using `scaleEffect`. This causes "double-scaling" bugs.

## 5. Window Interaction

- **Draggable Zones**: Draggable areas (Titlebar) should be implemented as clear overlays with specific dimensions.
- **Passthrough Backgrounds**: Custom AppKit window backgrounds (Resizers/Configurators) must return `nil` in `hitTest` to avoid blocking SwiftUI interactions.

---

## See Also

- [Architecture Overview](architecture.md) — How the player state and UI interact.
