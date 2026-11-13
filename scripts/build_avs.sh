#!/bin/bash
# Builds libavs (Advanced Visualization Studio 2.81d, grandchild/vis_avs fork) as a universal dylib.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/MacAmp/Vendor/AVS"
WORK="$ROOT/build/avs"
LIBRARY="$WORK/libavs.dylib"
LICENSE="$WORK/AVS-LICENSES.txt"
JOBS="$(sysctl -n hw.ncpu)"

mkdir -p "$WORK"
if [ "${1:-}" != --locked ]; then
    exec /usr/bin/lockf -k "$WORK/build.lock" /bin/bash "$0" --locked
fi
if [ "$LIBRARY" -nt "$0" ] && [ "$LICENSE" -nt "$0" ] \
    && [ -z "$(find "$SOURCE" -type f -newer "$LIBRARY" -print -quit)" ]; then
    exit 0
fi

STAGING="$(mktemp -d "$WORK/.build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
cd "$SOURCE/avs"
CXX_SOURCES=(vis_avs/*.cpp uuid.cpp 3rdparty/md_fft.cpp 3rdparty/pevents.cpp)
C_SOURCES=(platform.c platform_macos.c 3rdparty/WDL-EEL2/eel2/nseel-*.c)
# NO_MMX: the C fallbacks of the old MMX asm. EEL_TARGET_PORTABLE: EEL2 interprets expressions, no executable memory.
COMMON=(-O2 -fvisibility=hidden -w -mmacosx-version-min=14.0 -DNO_MMX -DNO_FFMPEG -D_USE_MATH_DEFINES -DWFMO
        -DEEL_TARGET_PORTABLE -DSIMD_MODE_X86_SSE)

for ARCH in arm64 x86_64; do
    if [ "$ARCH" = arm64 ]; then FLAGS=(-arch arm64 -I"$SOURCE/compat/arm64"); else FLAGS=(-arch x86_64 -mssse3); fi
    OBJ="$STAGING/$ARCH"
    mkdir -p "$OBJ"
    export OBJ
    printf '%s\n' "${CXX_SOURCES[@]}" | xargs -P "$JOBS" -I{} /bin/bash -c \
        'xcrun clang++ -std=c++14 "$@" -c "{}" -o "$OBJ/$(echo "{}" | tr / _).o"' _ "${COMMON[@]}" "${FLAGS[@]}"
    printf '%s\n' "${C_SOURCES[@]}" | xargs -P "$JOBS" -I{} /bin/bash -c \
        'xcrun clang -std=gnu11 "$@" -c "{}" -o "$OBJ/$(echo "{}" | tr / _).o"' _ "${COMMON[@]}" "${FLAGS[@]}"
    xcrun clang++ -arch "$ARCH" -mmacosx-version-min=14.0 -dynamiclib -install_name @rpath/libavs.dylib \
        -current_version 2.82 "$OBJ"/*.o -o "$STAGING/libavs-$ARCH.dylib"
done
lipo -create "$STAGING/libavs-arm64.dylib" "$STAGING/libavs-x86_64.dylib" -output "$STAGING/libavs.dylib"
lipo "$STAGING/libavs.dylib" -verify_arch arm64 x86_64

{
    for notice in "$SOURCE/AVS-LICENSE.txt" 3rdparty/WDL-EEL2/LICENSE.txt "$SOURCE/compat/arm64/SSE2NEON-LICENSE.txt" \
        3rdparty/LICENSE.json.txt 3rdparty/LICENSE.pevents.txt 3rdparty/LICENSE.stb_image.txt; do
        printf '==== %s ====\n\n' "$(basename "$notice")"
        cat "$notice"
        printf '\n\n'
    done
} > "$STAGING/AVS-LICENSES.txt"
mv -f "$STAGING/AVS-LICENSES.txt" "$LICENSE"
mv -f "$STAGING/libavs.dylib" "$LIBRARY"
echo "Built libavs (AVS 2.81d) for arm64 and x86_64."
