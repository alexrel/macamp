#!/bin/bash
# Builds libprojectM (Milkdrop engine, LGPL-2.1) as a universal dylib: build/projectm/install/{lib,include}
# Xcode runs this before linking. The copy in the shipped source archive builds that source directly.
set -euo pipefail

VERSION="4.1.8"
# sha256 of the GitHub release tarball, taken from a first download (not an upstream-published checksum)
SHA256="f72135e8b8e5fd807f908537255b41ac7ba4830309265e830cb756535487239e"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$SCRIPT_DIR/../build/projectm"
TARBALL="$WORK/libprojectM-$VERSION.tar.gz"
LIBRARY="$WORK/install/lib/libprojectM-4.4.dylib"
SOURCE_ARCHIVE="$WORK/projectM-source.tar.gz"
LICENSE="$WORK/projectM-LGPL-2.1.txt"

build_library() {
    local source_dir="$1" output_dir="$2" prefix="$3"
    # Xcode's Finder-launched PATH may omit Homebrew and CMake.app.
    export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/Applications/CMake.app/Contents/bin"
    command -v cmake >/dev/null || { echo "error: projectM requires CMake 3.21 or later." >&2; exit 1; }
    cmake -S "$source_dir" -B "$output_dir/cmake" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DENABLE_SYSTEM_PROJECTM_EVAL=OFF -DENABLE_PLAYLIST=OFF \
        -DBUILD_TESTING=OFF -DENABLE_SDL_UI=OFF -DBUILD_SHARED_LIBS=ON >/dev/null
    cmake --build "$output_dir/cmake" -j"$(sysctl -n hw.ncpu)" >/dev/null
    cmake --install "$output_dir/cmake" --prefix "$output_dir/install" >/dev/null
    lipo "$output_dir/install/lib/libprojectM-4.4.dylib" -verify_arch arm64 x86_64
}

if [ -f "$SCRIPT_DIR/CMakeLists.txt" ]; then
    build_library "$SCRIPT_DIR" "$SCRIPT_DIR/build-macamp" "$SCRIPT_DIR/build-macamp/install"
    exit 0
fi

mkdir -p "$WORK"
if [ "${1:-}" != --locked ]; then
    exec /usr/bin/lockf -k "$WORK/build.lock" /bin/bash "$0" --locked
fi
if [ "$LIBRARY" -nt "$0" ] && [ -f "$WORK/install/lib/libprojectM-4.dylib" ] \
    && [ "$SOURCE_ARCHIVE" -nt "$0" ] && [ "$LICENSE" -nt "$0" ]; then
    exit 0
fi

STAGING="$(mktemp -d "$WORK/.build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
verify_archive() { printf '%s  %s\n' "$SHA256" "$1" | shasum -a 256 -c - >/dev/null 2>&1; }
if ! verify_archive "$TARBALL"; then
    curl -fsSL -o "$STAGING/download.tar.gz" "https://github.com/projectM-visualizer/projectm/releases/download/v$VERSION/libprojectM-$VERSION.tar.gz"
    verify_archive "$STAGING/download.tar.gz" || { echo "error: projectM $VERSION checksum mismatch." >&2; exit 1; }
    mv -f "$STAGING/download.tar.gz" "$TARBALL"
fi

tar -xzf "$TARBALL" -C "$STAGING"
SRC="$STAGING/libprojectM-$VERSION"
# Orphan dynamic GL buffers to avoid waiting for the GPU to release the previous frame's data.
UPLOAD_PATTERN='glBufferSubData\((GL_[A-Z_]+), 0, (.+)\);'
for file in "$SRC"/src/libprojectM/MilkdropPreset/*.cpp; do
    if grep -qE "$UPLOAD_PATTERN" "$file"; then
        sed -i '' -E -e "s/$UPLOAD_PATTERN/glBufferData(\\1, \\2, GL_STREAM_DRAW);/" -e '1i\
// Modified by MacAmp on 2026-11-09 to orphan dynamic GL buffers on macOS.\
' "$file"
    fi
done

build_library "$SRC" "$STAGING" "$WORK/install"
cp "$0" "$SRC/MacAmp-build_projectm.sh"
COPYFILE_DISABLE=1 tar -czf "$STAGING/projectM-source.tar.gz" -C "$STAGING" "libprojectM-$VERSION"
mkdir -p "$WORK/install"
cp -R "$STAGING/install/." "$WORK/install/"
cp "$SRC/LICENSE.txt" "$LICENSE"
mv -f "$STAGING/projectM-source.tar.gz" "$SOURCE_ARCHIVE"
echo "[FIX] Built projectM $VERSION for arm64 and x86_64 and packaged its corresponding source."
