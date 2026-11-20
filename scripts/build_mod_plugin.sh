#!/bin/bash
# ==============================================================================
# Builds MacAmp's module plug-in (in_mod): build/plugins/MacAmp Modules.macampplugin
#
# Tracker modules (MOD, XM, S3M, IT and their relatives) through libopenmpt (BSD 3-clause), universal arm64 + x86_64,
# linked statically into one small tool, scripts/in_mod/openmpt-render.c. MacAmp runs it as a separate program to
# render a module once into a WAV it plays as usual. Only macOS system libraries are linked (no Homebrew).
#
# Usage: scripts/build_mod_plugin.sh   (downloads the source once into build/mod-plugin, ~3 min)
# ==============================================================================
set -euo pipefail

VERSION="0.8.10"
# lib.openmpt.org publishes no checksum file: this is the tarball fetched over HTTPS on 2026-11-19
SHA256="976d259288c40cd285771f77d09eff3d02514511d5677ecfcfb53be5013317e2"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/mod-plugin"
TARBALL="$WORK/download/libopenmpt-$VERSION+release.autotools.tar.gz"
SRC="$WORK/src-$VERSION"
PLUGIN="$ROOT/build/plugins/MacAmp Modules.macampplugin"
TOOL="openmpt-render"

mkdir -p "$WORK/download"
if [ ! -f "$TARBALL" ]; then
    curl -fsSL -o "$TARBALL" "https://lib.openmpt.org/files/libopenmpt/src/libopenmpt-$VERSION+release.autotools.tar.gz"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch: $TARBALL"; exit 1; }
if [ ! -d "$SRC" ]; then
    mkdir -p "$SRC"
    tar -xzf "$TARBALL" -C "$SRC" --strip-components 1
fi

build_arch() {
    local arch="$1" host="$2"
    local dir="$WORK/build-$arch"
    rm -rf "$dir" && mkdir -p "$dir" && cd "$dir"
    # zlib is macOS's own (J2B and other compressed formats); mpg123 and Vorbis (MP3 / Ogg samples in MO3) are left out.
    # ZLIB_CFLAGS / ZLIB_LIBS set: configure takes them instead of asking pkg-config (which would find Homebrew's)
    "$SRC/configure" --host="$host" --prefix="$dir/install" --disable-shared --enable-static \
        --disable-openmpt123 --disable-examples --disable-tests --disable-doxygen-doc \
        --without-mpg123 --without-ogg --without-vorbis --without-vorbisfile \
        ZLIB_CFLAGS="-I$(xcrun --show-sdk-path)/usr/include" ZLIB_LIBS="-lz" \
        --without-portaudio --without-portaudiocpp --without-pulseaudio --without-sndfile --without-flac \
        CC="clang -arch $arch" CXX="clang++ -arch $arch" \
        CFLAGS="-O2 -mmacosx-version-min=$MIN_MACOS" CXXFLAGS="-O2 -mmacosx-version-min=$MIN_MACOS" \
        LDFLAGS="-mmacosx-version-min=$MIN_MACOS" PKG_CONFIG=false > configure.log
    make -j"$(sysctl -n hw.ncpu)" > make.log 2>&1
    make install >> make.log 2>&1
    clang -arch "$arch" -O2 -mmacosx-version-min="$MIN_MACOS" -I"$dir/install/include" \
        "$ROOT/scripts/in_mod/$TOOL.c" "$dir/install/lib/libopenmpt.a" -lc++ -lz -o "$dir/$TOOL"
}

build_arch arm64 aarch64-apple-darwin
build_arch x86_64 x86_64-apple-darwin

rm -rf "$PLUGIN" && mkdir -p "$PLUGIN/Contents/MacOS" "$PLUGIN/Contents/Resources"
lipo -create "$WORK/build-arm64/$TOOL" "$WORK/build-x86_64/$TOOL" -output "$PLUGIN/Contents/MacOS/$TOOL"
strip -x "$PLUGIN/Contents/MacOS/$TOOL"
cp "$SRC/LICENSE" "$PLUGIN/Contents/Resources/LICENSE.libopenmpt.txt"
cat > "$PLUGIN/Contents/Resources/SOURCE.txt" <<EOF
libopenmpt $VERSION (https://lib.openmpt.org), BSD 3-clause license (LICENSE.libopenmpt.txt).
Source: https://lib.openmpt.org/files/libopenmpt/src/libopenmpt-$VERSION+release.autotools.tar.gz (SHA-256 $SHA256)
Built by MacAmp's scripts/build_mod_plugin.sh; no source changes. The tool: scripts/in_mod/$TOOL.c.
EOF
EXTENSIONS=(mod xm s3m it mptm mtm 669 stm ult med okt far amf dmf psm umx)
cat > "$PLUGIN/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.macamp.plugin.modules</string>
    <key>CFBundleName</key><string>MacAmp Modules</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>MacAmpPluginKind</key><string>converter</string>
    <key>MacAmpPluginRenderer</key><string>$TOOL</string>
    <key>MacAmpPluginTitle</key><string>MacAmp Module Decoder 1.0 (libopenmpt $VERSION) [in_mod]</string>
    <key>MacAmpPluginAudioExtensions</key>
    <array>$(printf '<string>%s</string>' "${EXTENSIONS[@]}")</array>
</dict>
</plist>
EOF
codesign --force --sign - "$PLUGIN/Contents/MacOS/$TOOL"
# The release asset (docs/RELEASE.md): the bundle zipped as Finder would
ZIP="$ROOT/build/MacAmp-Modules-$VERSION.zip"
rm -f "$ZIP" && (cd "$(dirname "$PLUGIN")" && ditto -c -k --norsrc --noextattr --noacl --keepParent "$(basename "$PLUGIN")" "$ZIP")
du -sh "$PLUGIN" "$ZIP"
echo "Built: $PLUGIN"
