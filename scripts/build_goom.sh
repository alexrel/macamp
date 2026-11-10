#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/MacAmp/Vendor/GOOM"
WORK="$ROOT/build/goom"
LIBRARY="$WORK/libgoom.dylib"
LICENSE="$WORK/GOOM-LICENSE.txt"
ARCHIVE="$WORK/GOOM-source.zip"

mkdir -p "$WORK"
if [ "${1:-}" != --locked ]; then
    exec /usr/bin/lockf -k "$WORK/build.lock" /bin/bash "$0" --locked
fi
if [ "$LIBRARY" -nt "$0" ] && [ "$LICENSE" -nt "$0" ] && [ "$ARCHIVE" -nt "$0" ] \
    && [ -z "$(find "$SOURCE" -type f -newer "$LIBRARY" -print -quit)" ]; then
    exit 0
fi

STAGING="$(mktemp -d "$WORK/.build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
(
    cd "$SOURCE"
    xcrun clang -std=gnu11 -O2 -fwrapv -fvisibility=hidden \
        -Wno-pointer-sign -Wno-absolute-value -Wno-deprecated-non-prototype -Wno-comment \
        -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
        -dynamiclib -install_name @rpath/libgoom.dylib -current_version 1.99.4 \
        MacAmpGoom.c core/{filters,gfontlib,goom_core,graphic,ifs,ifs_display,lines,readme,surf3d,surface,tentacle3d}.c \
        -o "$STAGING/libgoom.dylib"
)
lipo "$STAGING/libgoom.dylib" -verify_arch arm64 x86_64
(
    cd "$ROOT"
    zip -qr "$STAGING/GOOM-source.zip" MacAmp/Vendor/GOOM scripts/build_goom.sh
)
cp "$SOURCE/GOOM-LICENSE.txt" "$STAGING/GOOM-LICENSE.txt"
mv -f "$STAGING/GOOM-LICENSE.txt" "$LICENSE"
mv -f "$STAGING/GOOM-source.zip" "$ARCHIVE"
mv -f "$STAGING/libgoom.dylib" "$LIBRARY"
echo "Built GOOM 1.99.4 for arm64 and x86_64 and packaged its corresponding source."
