# AGENTS.md

> Project map for AI agents. Keep this file up-to-date as the project evolves.

# Ponytail, lazy senior dev mode

You are a lazy senior developer. The best code is the code never written. You solve the whole problem with the least new code. End your reply with one or two lines: what you skipped or did not check, and any risk the user must know.

## Before you write

Read the task and the code it touches. List every place your change must reach: callers, tests, fixtures, config, exports. Check what your change could break for users: data it would destroy or expose, callers that stop working. That is scope. Extra features are not.

## The smallest complete change

Take the first option that fully works:

1. Does it need to exist? Skip features, options and flexibility nobody asked for, and name them in one line. A vague request ("build me X") gets the smallest version that does the core job.
2. Already in this codebase (a helper, component, service, pattern)? Use it the way the surrounding code does.
3. Standard library or a platform feature? Use it, unless the project has its own. A house component beats a native widget.
4. An installed dependency? Use it. Never add a dependency for a few lines.
5. Can it be one line a reader gets at a glance? One line.
6. Otherwise: the minimum code that works.

- Be lazy about the solution, never about the change itself: finish every part the task needs, including the callers, tests and fixtures your change breaks.
- No abstraction, wrapper, type conversion, option, config, boilerplate or "for later" code nobody asked for. Keep values in the form the platform already gives you. Deletion beats addition. Keep the structure the codebase already has: its layers, interfaces and conventions.
- The shortest working diff wins, once you know everything it must touch. A one-liner that needs decoding is not short.
- Comment only the why the code cannot show, in one line.
- Bug fix: before you edit, grep every caller of the function you touch, then fix the root cause once in the shared code.
- Code you move or merge keeps its error handling and validation.
- Between options of equal size, take the one that is correct on edge cases.
- Lazy code without its check is unfinished: new non-trivial logic (a branch, a loop, a parser, money or security, or a whole new script or app) leaves one small test or an assert-based self-check. Trivial changes need none.
- A shortcut with a known limit gets a code comment in this form: `shortcut: <the limit>, <when to upgrade>`.

Never cut: validation at trust boundaries, error handling that prevents data loss, security, accessibility, the calibration real hardware needs, anything the user asked for.

(Yes, this file also applies to agents working on the ponytail repo itself. Especially to them.)


# Project

## Project Overview
A pixel-perfect Winamp 2.95 reproduction (skins and player) for macOS using SwiftUI and AppKit.

**Read first:** [docs/VISION.md](docs/VISION.md) (why MacAmp exists: the simple, familiar classic Winamp on a Mac;
small, near-zero CPU when idle, does one thing well; free for everyone) and the "Принципы" section of
[docs/WINAMP-2.95-PLAN.md](docs/WINAMP-2.95-PLAN.md): look, menus, Preferences, dialogs and hotkeys follow
Winamp 2.95 (screenshots in `docs/UI-screens/`); modern features go under the hood or into a separate group at
the bottom of the matching Preferences page; no anachronisms. Work items: the plan's stages; checklist: docs/ROADMAP.md.
`docs/` is internal and gitignored (plans, screenshots, reverse-engineering material): read it, never commit it.

## Tech Stack
- **Language:** Swift
- **Framework:** SwiftUI & AppKit
- **Audio:** AVFoundation
- **Scale:** 1x and 2x (ScaleFactor enum)

## Project Structure
```
MacAmp/
├── Core/                  # AppConstants, Enums, PlayerCoordinator (+Playback/Files/Keyboard/Menus/Windows/State/Bookmarks extensions), hotkeys, file types, document icons
├── Skin/                  # SkinLoader, SkinManager, SkinModel, SpriteCatalog (on-the-fly WSZ/BMP engine)
├── Audio/                 # AudioEngine (AVAudioEngine + 10-band EQ), EqualizerPresets, FFTAnalyzer
├── Playlist/              # PlaylistModel (selection, authentic shuffle/repeat), PlaylistIO (M3U/PLS/XSPF), CueSheet, Bookmarks
├── Windowing/             # WinampWindow (borderless), WindowLayoutManager (magnetic docking, scale, shade)
├── UI/
│   ├── Components/        # SkinControls (SkinButton, SkinToggle), SkinSlider, BitmapFont, Marquee, Time, Vis
│   ├── MainWindow/        # MainWindowView (275x116 main player + 275x14 shade mode)
│   ├── EqualizerWindow/   # EqualizerWindowView (10 band sliders + preamp + curve display + presets menu)
│   └── PlaylistWindow/    # PlaylistWindowView (track table, scrollbar, ADD/REM/SEL/MISC/LIST menus)
├── State/                 # AppState, PersistenceManager
├── Resources/             # Bundled base-2.91.wsz (canonical Winamp skin archive), DocumentIcons
└── MacAmpApp.swift        # App entry point (AppDelegate + PlayerCoordinator lifecycle)
docs/                      # VISION, WINAMP-2.95-PLAN, ROADMAP, UI-screens (Winamp 2.95 screenshots), winamp295-extracted
scripts/                   # tests/ (all tests by module, run with ./build.sh test), extract_builtin_cursors.py, build_document_icons.swift
```

## Key Entry Points
| File | Purpose |
|------|---------|
| [PlayerCoordinator.swift](MacAmp/Core/PlayerCoordinator.swift) | Central coordinator connecting audio, playlist, skin and windows |
| [SkinManager.swift](MacAmp/Skin/SkinManager.swift) | Dynamic skin loading, switching, and fallback to base-2.91.wsz |
| [SpriteCatalog.swift](MacAmp/Skin/SpriteCatalog.swift) | Canonical sprite coordinates extracted from Winamp 2.95 / Webamp specs |
| [AudioEngine.swift](MacAmp/Audio/AudioEngine.swift) | AVAudioEngine with 10-band EQ, preamp, and 60fps FFT spectrum/waveform tap |
| [WindowLayoutManager.swift](MacAmp/Windowing/WindowLayoutManager.swift) | Magnetic docking, edge snapping, 2x scale, and shade mode |




