#!/bin/bash
# ==============================================================================
# Builds MacAmp's FFmpeg plug-in (in_ffmpeg): build/plugins/MacAmp FFmpeg.macampplugin
#
# A trimmed, LGPL-only FFmpeg (ffmpeg + ffprobe, universal arm64 + x86_64, static): demuxers and decoders for
# MKV/WebM/AVI/WMV/FLV/MPEG and WMA/APE/WavPack/TTA/AC3/DTS, muxers for MP4 and FLAC, the Mac's hardware H.264
# encoder. MacAmp runs it as a separate program to convert such files once into MP4/FLAC it can play.
# Also the encoders CD Ripping offers with the plug-in installed: MP3 (LAME, LGPL) and Ogg Vorbis (libvorbis + libogg, BSD),
# built from source and linked in statically.
# Only macOS system libraries are linked (no Homebrew): the plug-in runs on any Mac with macOS 14+.
#
# Usage: scripts/build_ffmpeg_plugin.sh   (downloads the source once into build/ffmpeg-plugin, ~10 min)
# ==============================================================================
set -euo pipefail

VERSION="9.0.2"
# ffmpeg.org release, signature checked against the FFmpeg release key FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676 58D8
SHA256="8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
MIN_MACOS="14.0"
LAME_VERSION="3.100"
LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"   # same as Debian's lame_3.100.orig.tar.gz
OGG_VERSION="1.3.6"
OGG_SHA256="5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061"    # downloads.xiph.org SHA256SUMS
VORBIS_VERSION="1.3.7"
VORBIS_SHA256="b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b" # downloads.xiph.org SHA256SUMS

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/ffmpeg-plugin"
TARBALL="$WORK/download/ffmpeg-$VERSION.tar.xz"
SRC="$WORK/src-$VERSION"
PLUGIN="$ROOT/build/plugins/MacAmp FFmpeg.macampplugin"

mkdir -p "$WORK/download"
if [ ! -f "$TARBALL" ]; then
    curl -fsSL -o "$TARBALL" "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch: $TARBALL"; exit 1; }
if [ ! -d "$SRC" ]; then
    mkdir -p "$SRC"
    tar -xJf "$TARBALL" -C "$SRC" --strip-components 1
fi

# Downloads once, checks the checksum, unpacks into $WORK/<name>
fetch() {
    local url="$1" sha="$2" file="$WORK/download/$(basename "$1")" dir="$WORK/$3"
    [ -f "$file" ] || curl -fsSL -o "$file" "$url"
    echo "$sha  $file" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch: $file"; exit 1; }
    [ -d "$dir" ] || { mkdir -p "$dir" && tar -xf "$file" -C "$dir" --strip-components 1; }
}
fetch "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz" "$LAME_SHA256" "lame-$LAME_VERSION"
fetch "https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.xz" "$OGG_SHA256" "libogg-$OGG_VERSION"
fetch "https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.xz" "$VORBIS_SHA256" "libvorbis-$VORBIS_VERSION"
# libvorbis 1.3.7's configure passes -force_cpusubtype_ALL on macOS, which today's Apple linker rejects (Homebrew drops it
# the same way). The only change to any source; SOURCE.txt in the plug-in says so.
sed -i '' 's/ -force_cpusubtype_ALL//g' "$WORK/libvorbis-$VORBIS_VERSION/configure"

# LAME, libogg, libvorbis as static libraries for one architecture into $WORK/deps-<arch>
build_deps() {
    local arch="$1" host="$2"
    local prefix="$WORK/deps-$arch"
    local common=(--host="$host" --prefix="$prefix" --disable-shared --enable-static
                  CC="clang -arch $arch" CFLAGS="-O2 -mmacosx-version-min=$MIN_MACOS" LDFLAGS="-mmacosx-version-min=$MIN_MACOS")
    rm -rf "$prefix" && mkdir -p "$prefix"
    for lib in "lame-$LAME_VERSION" "libogg-$OGG_VERSION" "libvorbis-$VORBIS_VERSION"; do
        local dir="$WORK/build-$arch-$lib"
        rm -rf "$dir" && mkdir -p "$dir" && cd "$dir"
        case "$lib" in
            lame-*) "$WORK/$lib/configure" "${common[@]}" --disable-frontend --disable-decoder --disable-gtktest > configure.log ;;
            libogg-*) "$WORK/$lib/configure" "${common[@]}" > configure.log ;;
            libvorbis-*) "$WORK/$lib/configure" "${common[@]}" --with-ogg="$prefix" --disable-docs --disable-examples --disable-oggtest > configure.log ;;
        esac
        make -j"$(sysctl -n hw.ncpu)" > make.log 2>&1
        make install >> make.log 2>&1
    done
}

join() { local IFS=,; echo "$*"; }
DEMUXERS=(matroska avi asf flv mov mpegps mpegts ogg ape wv tta ac3 eac3 dts dtshd truehd mlp flac mp3 aac wav w64 aiff caf
          srt ass webvtt mpegvideo m4v h264 hevc amr)
# No h264 / hevc / vp9 decoders: those are copied into the MP4 as they are (macOS decodes them), never re-encoded
DECODERS=(vp8 mpeg4 msmpeg4v1 msmpeg4v2 msmpeg4v3 wmv1 wmv2 wmv3 vc1 mpeg1video mpeg2video mjpeg theora flv h263 h263p
          aac aac_latm mp1 mp2 mp3 mp1float mp2float mp3float ac3 eac3 dca truehd mlp opus vorbis flac alac
          wmav1 wmav2 wmapro wmavoice wmalossless ape wavpack tta amrnb amrwb adpcm_ms adpcm_ima_wav
          pcm_s16le pcm_s16be pcm_s24le pcm_s24be pcm_s32le pcm_f32le pcm_u8 pcm_alaw pcm_mulaw
          subrip srt ass ssa webvtt movtext text)
ENCODERS=(h264_videotoolbox aac flac movtext libmp3lame libvorbis)
MUXERS=(mp4 mov ipod flac null ogg mp3)
PARSERS=(h264 hevc vp8 vp9 av1 mpeg4video mpegvideo vc1 aac aac_latm ac3 dca mlp opus vorbis flac mpegaudio)
BSFS=(aac_adtstoasc h264_mp4toannexb hevc_mp4toannexb extract_extradata vp9_superframe vp9_superframe_split mpeg4_unpack_bframes null)
FILTERS=(buffer buffersink abuffer abuffersink format aformat scale aresample null anull setpts asetpts trim atrim fps)

build_arch() {
    local arch="$1"
    local dir="$WORK/build-$arch"
    local deps="$WORK/deps-$arch"
    local extra=()
    [ "$arch" = "x86_64" ] && extra=(--enable-cross-compile --disable-x86asm) # no nasm needed; slower only when re-encoding on Intel
    rm -rf "$dir" && mkdir -p "$dir" && cd "$dir"
    # pkg-config only for libvorbis, and only sees $deps (never Homebrew's libraries)
    PKG_CONFIG_LIBDIR="$deps/lib/pkgconfig" PKG_CONFIG_PATH="" \
    "$SRC/configure" --arch="$arch" --target-os=darwin --cc="clang -arch $arch" ${extra[@]+"${extra[@]}"} \
        --extra-cflags="-mmacosx-version-min=$MIN_MACOS -I$deps/include" --extra-ldflags="-mmacosx-version-min=$MIN_MACOS -L$deps/lib" \
        --pkg-config=pkg-config --pkg-config-flags=--static \
        --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-libmp3lame --enable-libvorbis \
        --enable-shared --disable-static --install-name-dir='@executable_path/../Frameworks' --prefix="$dir/install" \
        --enable-small --disable-debug --disable-doc --disable-network \
        --disable-programs --enable-ffmpeg --enable-ffprobe \
        --disable-everything --enable-protocol=file,pipe \
        --enable-demuxer="$(join "${DEMUXERS[@]}")" --enable-decoder="$(join "${DECODERS[@]}")" \
        --enable-encoder="$(join "${ENCODERS[@]}")" --enable-muxer="$(join "${MUXERS[@]}")" \
        --enable-parser="$(join "${PARSERS[@]}")" --enable-bsf="$(join "${BSFS[@]}")" --enable-filter="$(join "${FILTERS[@]}")" \
        > configure.log
    make -j"$(sysctl -n hw.ncpu)" > make.log 2>&1
    make install >> make.log 2>&1
}

build_deps arm64 aarch64-apple-darwin
build_arch arm64
build_deps x86_64 x86_64-apple-darwin
build_arch x86_64

rm -rf "$PLUGIN" && mkdir -p "$PLUGIN/Contents/MacOS" "$PLUGIN/Contents/Frameworks" "$PLUGIN/Contents/Resources"
# FFmpeg's libraries once, shared by ffmpeg and ffprobe (@executable_path/../Frameworks)
for tool in ffmpeg ffprobe; do
    lipo -create "$WORK/build-arm64/install/bin/$tool" "$WORK/build-x86_64/install/bin/$tool" -output "$PLUGIN/Contents/MacOS/$tool"
    strip -x "$PLUGIN/Contents/MacOS/$tool"
done
for lib in "$WORK/build-arm64/install/lib/"lib*.[0-9]*.dylib; do
    name="$(basename "$lib")"
    case "$name" in *.*.*.*.dylib) continue ;; esac  # libavcodec.62.dylib only, not libavcodec.62.28.102.dylib
    lipo -create "$lib" "$WORK/build-x86_64/install/lib/$name" -output "$PLUGIN/Contents/Frameworks/$name"
    strip -x "$PLUGIN/Contents/Frameworks/$name"
done
cp "$SRC/COPYING.LGPLv2.1" "$PLUGIN/Contents/Resources/LICENSE.LGPLv2.1.txt"
cp "$WORK/lame-$LAME_VERSION/COPYING" "$PLUGIN/Contents/Resources/LICENSE.LAME.txt"
cp "$WORK/libogg-$OGG_VERSION/COPYING" "$PLUGIN/Contents/Resources/LICENSE.libogg.txt"
cp "$WORK/libvorbis-$VORBIS_VERSION/COPYING" "$PLUGIN/Contents/Resources/LICENSE.libvorbis.txt"
cat > "$PLUGIN/Contents/Resources/SOURCE.txt" <<EOF
FFmpeg $VERSION (https://ffmpeg.org), licensed under the LGPL v2.1 or later.
Source: https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz (SHA-256 $SHA256)
With LAME $LAME_VERSION (MP3 encoder, LGPL, https://lame.sourceforge.io), libogg $OGG_VERSION and libvorbis $VORBIS_VERSION
(Ogg Vorbis encoder, BSD, https://xiph.org) linked in statically.
Built by MacAmp's scripts/build_ffmpeg_plugin.sh with only LGPL / BSD components. No source changes, except that
libvorbis's configure has its -force_cpusubtype_ALL flag removed (today's Apple linker rejects it).
EOF
cat > "$PLUGIN/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.macamp.plugin.ffmpeg</string>
    <key>CFBundleName</key><string>MacAmp FFmpeg</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>MacAmpPluginKind</key><string>converter</string>
    <key>MacAmpPluginTitle</key><string>MacAmp FFmpeg Decoder 1.1 (FFmpeg $VERSION) [in_ffmpeg]</string>
    <key>MacAmpPluginEncoders</key>
    <array><string>ogg</string><string>mp3</string></array>
    <key>MacAmpPluginAudioExtensions</key>
    <array><string>wma</string><string>ape</string><string>wv</string><string>tta</string><string>ac3</string><string>dts</string><string>mka</string><string>amr</string></array>
    <key>MacAmpPluginVideoExtensions</key>
    <array><string>mkv</string><string>webm</string><string>avi</string><string>wmv</string><string>asf</string><string>flv</string><string>mpg</string><string>mpeg</string><string>vob</string><string>ts</string><string>m2ts</string><string>mts</string><string>3gp</string><string>ogv</string></array>
</dict>
</plist>
EOF
codesign --force --sign - "$PLUGIN/Contents/Frameworks/"*.dylib "$PLUGIN/Contents/MacOS/ffmpeg" "$PLUGIN/Contents/MacOS/ffprobe"
# The release asset (docs/RELEASE.md): the bundle zipped as Finder would
ZIP="$ROOT/build/MacAmp-FFmpeg-$VERSION.zip"
rm -f "$ZIP" && (cd "$(dirname "$PLUGIN")" && ditto -c -k --norsrc --noextattr --noacl --keepParent "$(basename "$PLUGIN")" "$ZIP")
du -sh "$PLUGIN" "$ZIP"
echo "Built: $PLUGIN"
