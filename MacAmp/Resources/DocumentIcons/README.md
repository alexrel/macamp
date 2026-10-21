# Document icons

Finder icons for files that open in MacAmp (Preferences ▸ Setup ▸ File types).

- `Source/winamp-icon-<ID>.png` — the 256-color 32 px frame of each `RT_GROUP_ICON` in the original
  Winamp 2.95 `winamp.exe` (IDs 102, 131, 162–164, 178–182), decoded to RGBA. Not bundled.
- `Choices/winamp-icon-<ID>.icns` — the File icon / Playlist icon slider choices, built from `Source/` by
  `scripts/build_document_icons.swift` (enlarged without smoothing to keep the pixel art).
- `WinampAudioFile.icns` (#131), `WinampPlaylist.icns` (#102), `WinampSkin.icns` (#164) — what the
  Info.plist document types point to. Moving a slider overwrites the first two inside the built app
  (`DocumentIconManager`).

Build from the PNGs, not from .ico files: ImageIO returns the frames of a multi-frame .ico in its own order,
and picking "the last 32 px frame" can give the 16-color version.

The artwork is Nullsoft's Winamp iconography.
