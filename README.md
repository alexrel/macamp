# MacAmp

> Winamp 2.95 for the Mac: the classic skinned player, pixel for pixel, in Swift with AppKit and SwiftUI.

MacAmp is the simple, familiar Winamp on macOS. It starts fast, plays your music and stays out of the way:
the same windows, skins, menus, Preferences, dialogs and hotkeys as Winamp 2.95, and almost no CPU while idle
(paused ≈ 0.01%, playing with the visualizer ≈ 2–3% on an M1). Modern things live under the hood.

**Download:** [latest release](https://github.com/alexrel/macamp/releases/latest) (DMG, Apple Silicon and Intel,
macOS 14 Sonoma or later).

## Features

- **Main window, Equalizer and Playlist Editor** with magnetic docking, shade modes and Double Size (2x).
- **Classic skins:** any Winamp 2.x `.wsz` or skin folder, read on the fly; the base 2.91 skin is built in.
  Cyrillic titles in the skin's own font colors.
- **Playback:** MP3, AAC/M4A, FLAC, WAV/AIFF, Ogg Vorbis/Opus, MP2, AU, MIDI; crossfade and fades,
  follows the system output device.
- **10-band equalizer** with preamp, presets and auto-load by genre; DSP effects (pitch/tempo, reverb).
- **Playlists:** M3U/M3U8, PLS, XSPF and CUE sheets, authentic shuffle/repeat, sort, Jump to File/Time, bookmarks.
- **Internet radio:** SHOUTcast and Icecast streams with live titles.
- **Audio CD:** play and rip to FLAC, ALAC, AAC, WAV or AIFF, with M3U/PLS playlists of the rip.
- **Media Library** with local media, playlists and Internet Radio; **Minibrowser** and **Video** window.
- **Visualizer:** spectrum and oscilloscope in the main window, full-screen Visualizer Studio.
- **Track Info** with ID3 tag editing, Winamp-style Preferences, About, context menus and the 2.95 hotkeys
  (on any keyboard layout), global hotkeys and media keys.
- **Plug-ins:** the optional FFmpeg plug-in plays MKV/WebM/AVI/WMV and WMA/APE/WavPack (see the release assets).

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

## Building

Requires Xcode 16 or later.

```bash
./build.sh            # Debug build
./build.sh run        # build and run the player
./build.sh dmg        # Release build (Apple Silicon + Intel) packed into build/MacAmp-<version>.dmg
./build.sh test       # run the test suite
scripts/build_ffmpeg_plugin.sh   # the optional FFmpeg plug-in
```

## Credits

Winamp is a trademark of its owners; MacAmp is an independent fan project and is not affiliated with them.
Skin and behavior details were checked against [Webamp](https://github.com/captbaritone/webamp).

## License

MIT
