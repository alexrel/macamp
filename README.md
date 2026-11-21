# MacAmp

> Winamp 2.95 for the Mac: the classic skinned player, pixel for pixel, in Swift with AppKit and SwiftUI.

MacAmp is the simple, familiar Winamp on macOS. It starts fast, plays your music and stays out of the way:
the same windows, skins, menus, Preferences, dialogs and hotkeys as Winamp 2.95, and almost no CPU while idle
(paused ≈ 0.01%, playing with the visualizer ≈ 2–3% on an M1). Modern things live under the hood.

**Download:** [latest release](https://github.com/alexrel/macamp/releases/latest) (DMG, Apple Silicon and Intel,
macOS 14 Sonoma or later).

<p align="center"><img src=".github/screenshot.webp" width="400" alt="MacAmp main window, equalizer and playlist docked together"></p>

## Features

- **Main window, Equalizer and Playlist Editor** with magnetic docking, shade modes and Double Size (2x);
  interface scale of 100%, 150% or 200% for large and high-resolution displays.
- **Classic skins:** any Winamp 2.x `.wsz` or skin folder, read on the fly; the base 2.91 skin is built in.
  Cyrillic titles in the skin's own font colors.
- **Playback:** MP3, AAC/M4A, FLAC, WAV/AIFF, Ogg Vorbis/Opus, MP2, AU, MIDI; crossfade and fades,
  follows the system output device.
- **10-band equalizer** with preamp, presets and auto-load by genre; DSP effects (pitch/tempo, reverb).
- **Playlists:** M3U/M3U8, PLS, XSPF and CUE sheets, authentic shuffle/repeat, sort, Jump to File/Time, bookmarks.
- **Internet radio:** SHOUTcast and Icecast streams with live titles.
- **Audio CD:** play and rip to FLAC, ALAC, AAC, WAV or AIFF (Ogg Vorbis and MP3 with the FFmpeg plug-in),
  with M3U/PLS playlists of the rip.
- **Media Library** with local media, playlists, Internet Radio and your Subsonic server (Navidrome, Gonic, Airsonic); **Minibrowser** and **Video** window.
- **Visualizer:** spectrum and oscilloscope in the main window, full-screen Visualizer Studio, MilkDrop through projectM, What A Goom! 1.99.4, and Advanced Visualization Studio 2.81d with its editor.
- **Track Info** with ID3 tag editing, Winamp-style Preferences, About, context menus and the 2.95 hotkeys
  (on any keyboard layout), global hotkeys and media keys.
- **Plug-ins:** the optional FFmpeg plug-in plays MKV/WebM/AVI/WMV and WMA/APE/WavPack, the Module plug-in
  MOD/XM/S3M/IT tracker music (see the release assets);
  Album Art (Plug-ins ▸ General Purpose, off by default) shows the track's cover in a docked window;
  the Last.fm Scrobbler (same page, off by default) sends what you play to your Last.fm profile.

## What's new

### 0.12

- **Subsonic:** your own music server (Navidrome, Gonic, Airsonic) as a Media Library section: artists, albums and
  server search; tracks download as they play, so seeking, the equalizer and the visualizer work as with local files.
- **Plug-ins:** Album Art shows the playing track's cover in a docked window; the Last.fm Scrobbler sends what you
  play to your profile, with an offline queue; both are General Purpose plug-ins, off by default. The Module
  plug-in plays MOD/XM/S3M/IT tracker music, and plug-in formats show their length and tags as soon as they're added.
- **CD ripping and Disk Writer** to Ogg Vorbis and MP3, tags included, with the FFmpeg plug-in 1.1.
- **HD skins:** `.msz` skins drawn at four times the pixels, with `<Base Skin HD>` built in next to `<Base Skin>`.
- **Internet radio:** HLS stations play through the player with the equalizer and visualizer.
- **Title marquee** loops with `***` and scrolls while paused or stopped, as in Winamp 2.95.
- **Chiptune plug-in:** game console music (NSF, SPC, GBS, VGM and more); a soundtrack file lists each song as its
  own playlist entry, with its real length.
- **Plug-in pages as in Winamp 2.95:** full-height lists with Configure and About; settings open in their own window,
  and Preferences waits for it.
- **Mouse wheel** over the main window sets the volume in Winamp's steps (faster as you spin it); with the middle
  button held it seeks 5 seconds.

### 0.11

- **Visualizer Studio:** Space moves through its four groups: MacAmp's own visualizations (now with a scrolling
  Spectrogram and Waveform), MilkDrop, GOOM and AVS, with the same keys in each. One right-click menu laid out like
  AVS's picks the presets (MilkDrop's by folder, with Find Preset), and the Studio opens again where it was left.
- **MilkDrop presets:** projectM's 9,795 Cream of the Crop presets install as a plug-in (see the release assets).
- **Playlist:** Play, Pause, Stop, Next and Previous bring the playing track back into view, centered.
- **Shortcuts** as in Winamp 2.95: Page Up/Down, ⌃W, ⇧L Open Directory, ⌃L Open location with its history, ⌃⌥A.

### 0.10

- Advanced Visualization Studio 2.81d as a third visualization plug-in, native on Apple Silicon and
  Intel: the AVS window's menu and hotkeys, random preset switching with a dissolve, the Winamp AVS Editor, and 35
  presets. The Visualizer Studio window docks to the player windows like Winamp's AVS window.

### 0.9.3

- The About box banner is animated as in Winamp 2.95 (its lens warp recovered from winamp.exe) and
  rests sharp; the empty Video window shows the Nullsoft Video picture. Pictures keep their contents in scaled
  dialogs; the close cursor shows over the close button of the Library, Video, Minibrowser and Studio frames.

### 0.9.2

- Skins whose bitmaps are smaller than the standard keep their own look instead of borrowing the base
  skin's; time digits come from NUMS_EX.BMP when the skin has it; every skin bitmap is shown in one colour space.
  The visualizer no longer follows the volume, fills its background while playing, freezes on pause, and the
  oscilloscope is drawn as in Winamp. No see-through strokes in window frames at 150%; dialogs stay sharp at 150%
  and 200%; all windows repaint at once when the skin changes.

### 0.9.1

- Windows docked together stop together at the menu bar; the playlist no longer slides under the
  main window.

### 0.9

- **Interface scale:** Preferences ▸ Display ▸ Interface scale makes every window and dialog 100%, 150% or 200%;
  Double Size still works on top of it.
- **Big folders:** a dropped or added folder shows up in the playlist one directory at a time, the way Winamp
  did it, and track lengths fill in afterwards. A music share with thousands of files no longer looks frozen.
  Clearing the playlist stops a folder that is still loading.
- **Playlist:** smooth trackpad scrolling, and the list only redraws the part that changed.
- **Llama:** the first launch plays the Winamp intro, then leaves it in the playlist as an ordinary entry.
- **Big folders, continued:** rows on screen get their lengths first, wherever the list is scrolled.
- **Menu bar menu:** a long track title scrolls while the menu is open, as it does in the main window; the Dock
  menu cuts it to the same width.
- **Tag editor:** a long file path no longer stretches the window; a genre picked from the list replaces what
  was typed; the genre list button sits inside its field.
- **Dialogs:** a button that opens another dialog no longer stays pressed.
- **New versions:** MacAmp checks GitHub once a day at startup and offers to download a newer release
  (Preferences ▸ Setup; "Check now" asks at once). It opens the disk image and never replaces itself.
- **Fixed:** the playlist keeps its height after leaving shade mode; title bar buttons follow the window's
  focus; window title bars stay reachable when the windows don't fit the screen.

## Roadmap

Planned, in no fixed order:

- A song lyrics window (synced lyrics highlighted line by line), off by default.

Not planned: Winamp 3/5 "Modern" skins and a Linux or Windows version.

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

## Visualization

MacAmp ships with GOOM and its effects, the projectM engine for MilkDrop, and Advanced Visualization Studio
(Nullsoft's AVS 2.81d source, BSD, through the libavs fork) with 35 presets from the same release. The app bundle
includes the libraries' licenses; GOOM and projectM also ship their matching source archives.

Download MilkDrop presets separately. In **Preferences ▸ Plug-ins ▸ Visualization**, choose
**Open presets folder** and extract the pack there. The folder is
`~/Library/Application Support/MacAmp/Milkdrop`. Use [Cream of the Crop](https://github.com/projectM-visualizer/presets-cream-of-the-crop)
or the [original MilkDrop pack](https://github.com/projectM-visualizer/presets-milkdrop-original)
with its [texture pack](https://github.com/projectM-visualizer/presets-milkdrop-texture-pack).

Press **Tab** to switch Studio modes. In MilkDrop and GOOM, **L** opens the list, and the highlighted
preset or effect applies immediately. Close the list with **L**, **Return** or **Esc**.

AVS works as in Winamp 2.95: right-click its window for presets and the AVS Editor (also **Configure plug-in**,
⌥K). **Space** picks a random preset, **U** / **Y** step through them, **R** toggles random switching, and
F1–F12 or 0–9 load a hotkey preset (⌃ saves it). Its presets live in `~/Library/Application Support/MacAmp/AVS`;
**Import presets...** copies `.avs` files or a whole Winamp `Plugins\avs` folder there.

## Building

Requires Xcode 16 and CMake 3.21 or later. The first build downloads and builds the pinned projectM release for MilkDrop.

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
