#!/bin/bash
# ==============================================================================
# Builds MacAmp's FFmpeg plug-in (in_ffmpeg): build/plugins/MacAmp FFmpeg.macampplugin
#
# A trimmed, LGPL-only FFmpeg (ffmpeg + ffprobe, universal arm64 + x86_64, static): demuxers and decoders for
# MKV/WebM/AVI/WMV/FLV/MPEG and WMA/APE/WavPack/TTA/AC3/DTS, muxers for MP4 and FLAC, the Mac's hardware H.264
# encoder. MacAmp runs it as a separate program to convert such files once into MP4/FLAC it can play.
# Only macOS system libraries are linked (no Homebrew): the plug-in runs on any Mac with macOS 14+.
#
# Usage: scripts/build_ffmpeg_plugin.sh   (downloads the source once into build/ffmpeg-plugin, ~10 min)
# ==============================================================================
set -euo pipefail

VERSION="9.0.2"
# ffmpeg.org release, signature checked against the FFmpeg release key FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676 58D8
SHA256="8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
MIN_MACOS="14.0"

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

join() { local IFS=,; echo "$*"; }
DEMUXERS=(matroska avi asf flv mov mpegps mpegts ogg ape wv tta ac3 eac3 dts dtshd truehd mlp flac mp3 aac wav w64 aiff caf
          srt ass webvtt mpegvideo m4v h264 hevc amr)
# No h264 / hevc / vp9 decoders: those are copied into the MP4 as they are (macOS decodes them), never re-encoded
DECODERS=(vp8 mpeg4 msmpeg4v1 msmpeg4v2 msmpeg4v3 wmv1 wmv2 wmv3 vc1 mpeg1video mpeg2video mjpeg theora flv h263 h263p
          aac aac_latm mp1 mp2 mp3 mp1float mp2float mp3float ac3 eac3 dca truehd mlp opus vorbis flac alac
          wmav1 wmav2 wmapro wmavoice wmalossless ape wavpack tta amrnb amrwb adpcm_ms adpcm_ima_wav
          pcm_s16le pcm_s16be pcm_s24le pcm_s24be pcm_s32le pcm_f32le pcm_u8 pcm_alaw pcm_mulaw
          subrip srt ass ssa webvtt movtext text)
ENCODERS=(h264_videotoolbox aac flac movtext)
MUXERS=(mp4 mov ipod flac null)
PARSERS=(h264 hevc vp8 vp9 av1 mpeg4video mpegvideo vc1 aac aac_latm ac3 dca mlp opus vorbis flac mpegaudio)
BSFS=(aac_adtstoasc h264_mp4toannexb hevc_mp4toannexb extract_extradata vp9_superframe vp9_superframe_split mpeg4_unpack_bframes null)
FILTERS=(buffer buffersink abuffer abuffersink format aformat scale aresample null anull setpts asetpts trim atrim fps)

build_arch() {
    local arch="$1"
    local dir="$WORK/build-$arch"
    local extra=()
    [ "$arch" = "x86_64" ] && extra=(--enable-cross-compile --disable-x86asm) # no nasm needed; slower only when re-encoding on Intel
    rm -rf "$dir" && mkdir -p "$dir" && cd "$dir"
    "$SRC/configure" --arch="$arch" --target-os=darwin --cc="clang -arch $arch" ${extra[@]+"${extra[@]}"} \
        --extra-cflags="-mmacosx-version-min=$MIN_MACOS" --extra-ldflags="-mmacosx-version-min=$MIN_MACOS" \
        --pkg-config=false --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-zlib \
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

build_arch arm64
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
cat > "$PLUGIN/Contents/Resources/SOURCE.txt" <<EOF
FFmpeg $VERSION (https://ffmpeg.org), licensed under the LGPL v2.1 or later.
Source: https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz (SHA-256 $SHA256)
Built by MacAmp's scripts/build_ffmpeg_plugin.sh with only LGPL components; no source changes.
EOF
cat > "$PLUGIN/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.macamp.plugin.ffmpeg</string>
    <key>CFBundleName</key><string>MacAmp FFmpeg</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>MacAmpPluginKind</key><string>converter</string>
    <key>MacAmpPluginTitle</key><string>MacAmp FFmpeg Decoder 1.0 (FFmpeg $VERSION) [in_ffmpeg]</string>
    <key>MacAmpPluginAudioExtensions</key>
    <array><string>wma</string><string>ape</string><string>wv</string><string>tta</string><string>ac3</string><string>dts</string><string>mka</string><string>amr</string></array>
    <key>MacAmpPluginVideoExtensions</key>
    <array><string>mkv</string><string>webm</string><string>avi</string><string>wmv</string><string>asf</string><string>flv</string><string>mpg</string><string>mpeg</string><string>vob</string><string>ts</string><string>m2ts</string><string>mts</string><string>3gp</string><string>ogv</string></array>
</dict>
</plist>
EOF
codesign --force --sign - "$PLUGIN/Contents/Frameworks/"*.dylib "$PLUGIN/Contents/MacOS/ffmpeg" "$PLUGIN/Contents/MacOS/ffprobe"
du -sh "$PLUGIN"
echo "Built: $PLUGIN"
