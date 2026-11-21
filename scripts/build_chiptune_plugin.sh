#!/bin/bash
# ==============================================================================
# Builds MacAmp's chiptune plug-in (in_gme): build/plugins/MacAmp Chiptune.macampplugin
#
# Game console music (NSF, SPC, GBS, VGM and their relatives) through Game_Music_Emu / libgme (LGPL 2.1), universal
# arm64 + x86_64, linked statically into one small tool, scripts/in_gme/gme-render.c. MacAmp runs it as a separate
# program to render a song once into a WAV it plays as usual. Only macOS system libraries are linked (zlib for VGZ).
#
# Usage: scripts/build_chiptune_plugin.sh   (downloads the source once into build/chiptune-plugin; needs CMake)
# ==============================================================================
set -euo pipefail

VERSION="0.6.5"
# The digest GitHub publishes for the release asset
SHA256="a133f19278222136ba0d8c27b64a07987ba05fec9d2e6d293ccd8cabdd97ddbb"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/chiptune-plugin"
TARBALL="$WORK/download/libgme-$VERSION-src.tar.gz"
SRC="$WORK/src-$VERSION"
PLUGIN="$ROOT/build/plugins/MacAmp Chiptune.macampplugin"
TOOL="gme-render"
SDK="$(xcrun --show-sdk-path)"

command -v cmake >/dev/null || { echo "error: libgme needs CMake (brew install cmake)" >&2; exit 1; }
mkdir -p "$WORK/download"
if [ ! -f "$TARBALL" ]; then
    curl -fsSL -o "$TARBALL" "https://github.com/libgme/game-music-emu/releases/download/$VERSION/libgme-$VERSION-src.tar.gz"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch: $TARBALL"; exit 1; }
if [ ! -d "$SRC" ]; then
    mkdir -p "$SRC"
    tar -xzf "$TARBALL" -C "$SRC" --strip-components 1
fi

# Both architectures in one pass. YM2612 (Mega Drive VGM / GYM): GENS (LGPL), libgme's default before 0.6.4; Nuked,
# the new default, is more exact but rendered a 1:37 song in 4.6 s against 0.44 s (M1), and MAME's is GPL.
# zlib is pinned to the SDK's so CMake doesn't pick up Homebrew's.
rm -rf "$WORK/cmake" "$WORK/install"
cmake -S "$SRC" -B "$WORK/cmake" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$WORK/install" \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
    -DGME_BUILD_SHARED=OFF -DGME_BUILD_STATIC=ON -DGME_BUILD_EXAMPLES=OFF -DGME_BUILD_TESTING=OFF \
    -DGME_YM2612_EMU=GENS -DGME_ZLIB=ON -DZLIB_INCLUDE_DIR="$SDK/usr/include" -DZLIB_LIBRARY="$SDK/usr/lib/libz.tbd" \
    > "$WORK/cmake.log"
cmake --build "$WORK/cmake" -j"$(sysctl -n hw.ncpu)" >> "$WORK/cmake.log" 2>&1
cmake --install "$WORK/cmake" >> "$WORK/cmake.log" 2>&1
clang -arch arm64 -arch x86_64 -O2 -mmacosx-version-min="$MIN_MACOS" -I"$WORK/install/include" \
    "$ROOT/scripts/in_gme/$TOOL.c" "$WORK/install/lib/libgme.a" -lc++ -lz -o "$WORK/$TOOL"

rm -rf "$PLUGIN" && mkdir -p "$PLUGIN/Contents/MacOS" "$PLUGIN/Contents/Resources"
cp "$WORK/$TOOL" "$PLUGIN/Contents/MacOS/$TOOL"
strip -x "$PLUGIN/Contents/MacOS/$TOOL"
cp "$SRC/license.txt" "$PLUGIN/Contents/Resources/LICENSE.libgme.txt"
cat > "$PLUGIN/Contents/Resources/SOURCE.txt" <<EOF
Game_Music_Emu (libgme) $VERSION (https://github.com/libgme/game-music-emu), LGPL 2.1 (LICENSE.libgme.txt).
Source: https://github.com/libgme/game-music-emu/releases/download/$VERSION/libgme-$VERSION-src.tar.gz (SHA-256 $SHA256)
Built by MacAmp's scripts/build_chiptune_plugin.sh; no source changes. The tool: scripts/in_gme/$TOOL.c.
EOF
EXTENSIONS=(nsf nsfe spc gbs vgm vgz gym hes kss ay sap)
# Files that hold a whole soundtrack: MacAmp lists each song as its own entry (file#track=N)
TRACK_EXTENSIONS=(nsf nsfe gbs hes kss ay sap)
cat > "$PLUGIN/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.macamp.plugin.chiptune</string>
    <key>CFBundleName</key><string>MacAmp Chiptune</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>MacAmpPluginKind</key><string>converter</string>
    <key>MacAmpPluginRenderer</key><string>$TOOL</string>
    <key>MacAmpPluginTitle</key><string>MacAmp Chiptune Decoder 1.0 (Game_Music_Emu $VERSION) [in_gme]</string>
    <key>MacAmpPluginAudioExtensions</key>
    <array>$(printf '<string>%s</string>' "${EXTENSIONS[@]}")</array>
    <key>MacAmpPluginTrackExtensions</key>
    <array>$(printf '<string>%s</string>' "${TRACK_EXTENSIONS[@]}")</array>
</dict>
</plist>
EOF
codesign --force --sign - "$PLUGIN/Contents/MacOS/$TOOL"
# The release asset (docs/RELEASE.md): the bundle zipped as Finder would
ZIP="$ROOT/build/MacAmp-Chiptune-$VERSION.zip"
rm -f "$ZIP" && (cd "$(dirname "$PLUGIN")" && ditto -c -k --norsrc --noextattr --noacl --keepParent "$(basename "$PLUGIN")" "$ZIP")
du -sh "$PLUGIN" "$ZIP"
echo "Built: $PLUGIN"
