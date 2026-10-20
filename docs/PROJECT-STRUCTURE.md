# PROJECT-STRUCTURE.md

This document provides a concise map of the MacAmp codebase and the purpose of each file in the pixel-perfect WinAmp 2.91 implementation.

---

## 📂 Root
- **MacAmpApp.swift**: The app's entry point. Defines `WindowGroup` scenes for `Main`, `Equalizer`, and `Playlist`.
- **ContentView.swift**: A base container used for hosting window content (legacy or placeholder).
- **MacAmp.entitlements**: App permissions and sandbox configuration.
- **Info.plist**: Bundle configuration and application metadata.

## 📂 Models
- **WindowLayoutManager.swift**: The **Magnetic Graph Engine**. Manages snapping, rigid movement chains, and window hierarchies.
- **PlayerEnums.swift**: Core enums (AudioMode, VisualizerMode, ScaleFactor).
- **Track.swift**: Metadata model for audio tracks (ID, Title, Duration, URL).
- **Playlist.swift**: Management of track queues and history.
- **FFTAnalyzer.swift**: Real-time Fast Fourier Transform logic for the visualizer.

## 📂 ViewModels
- **PlayerViewModel.swift**: The central state of truth. Bridges the Audio Engine with the UI, managing playback state and visualizer data.

## 📂 Services
- **AudioPlayerService.swift**: High-level wrapper for `AVFoundation`. Handles playback, seeking, and hardware interaction.
- **PersistenceService.swift**: Manages `UserDefaults` for window positions, docking chains, and volume settings.

## 📂 Views
- **MainPlayerView.swift**: The root view for the main WinAmp window.
- **EqualizerView.swift**: Scene for the EQ window.
- **PlaylistView.swift**: Scene for the Playlist editor window.

## 📂 Views/Components (Pixel-Perfect Sprites)
- **TitleBarView.swift**: Custom window header with dragging logic and buttons.
- **InfoDisplayView.swift**: The main LCD-style panel (Title, Bitrate, Sample Rate).
- **TimeDisplayView.swift**: Sprite-based playback timer (minutes/seconds).
- **VisualizerView.swift**: Oscilloscope and Spectrum Analyzer implementation.
- **ControlButtonsView.swift**: Playback transport (Play, Pause, Stop, Prev, Next).
- **VolumeSliderView.swift**: Horizontal slider for volume (uses `VOLUME.BMP`).
- **BalanceSliderView.swift**: Center-zero slider for audio balance (`BALANCE.BMP`).
- **SeekBarView.swift**: Main progress bar.
- **ClutterbarView.swift**: The small utility buttons (O, A, I, D, V).
- **PlaybackIndicatorView.swift**: Tiny status icons (Playing, Paused, Stopped).
- **MonoStereoIndicatorView.swift**: Audio channel status displays.
- **SpriteCharView.swift**: Single character rendering from `TEXT.BMP`.
- **SpriteDigitView.swift**: Individual number rendering from `NUMBERS.BMP`.
- **SpriteButtonView.swift**: Reusable generic sprite button with hover/press states.
- **ShadeTimeDisplayView.swift**: Compact timer for Shade Mode.
- **PlaylistEqButtonsView.swift**: Toggle buttons for showing/hiding slaves.

---

## 📂 Assets.xcassets
Contains all WinAmp 2.91 source BMP files (MAIN, TITLEBAR, EQMAIN, PLEDIT, etc.), sliced and categorized by UI state.

---

## 🛠️ Helpers & Documentation
- **WindowDragHelper.swift**: AppKit logic to allow dragging windows from within SwiftUI views.
- **docs/ui-development-standards.md**: Mandatory rules for hit-testing and layering.
- **AGENTS.md**: High-level project map for AI agents.
