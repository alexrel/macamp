#!/bin/bash
# ==============================================================================
# MacAmp Build & Run Script
# ==============================================================================
# Usage:
#   ./build.sh              # Fast Debug build (default)
#   ./build.sh run          # Build Debug and launch MacAmp.app
#   ./build.sh release      # Build Release configuration
#   ./build.sh run-release  # Build Release and launch MacAmp.app
#   ./build.sh clean        # Clean build artifacts (DerivedData & build)
#   ./build.sh dmg          # Build Release and generate DMG installer
#   ./build.sh help         # Show help and available options
# ==============================================================================

set -euo pipefail

APP_NAME="MacAmp"
SCHEME="MacAmp"
VERSION="2.91"

BUILD_DIR="build"
DERIVED_DATA="DerivedData"
DEBUG_APP="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
RELEASE_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/${APP_NAME}-v${VERSION}.dmg"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}ℹ️  $1${NC}"; }
log_step()  { echo -e "${YELLOW}⚡ $1...${NC}"; }
log_ok()    { echo -e "${GREEN}✅ $1${NC}"; }
log_err()   { echo -e "${RED}❌ $1${NC}" >&2; }

print_banner() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}   MacAmp 2.91 macOS — Build Tool${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

clean_artifacts() {
    log_step "Cleaning build artifacts"
    rm -rf "$DERIVED_DATA" "$BUILD_DIR"
    log_ok "Build artifacts cleaned"
}

build_debug() {
    log_step "Building Debug configuration"
    rm -rf "$DEBUG_APP"
    xcodebuild -scheme "$SCHEME" \
               -configuration Debug \
               -derivedDataPath "$DERIVED_DATA" \
               build | grep -E '\*\*\s*BUILD|error:|warning:' || true
    
    if [ -d "$DEBUG_APP" ]; then
        mkdir -p "$BUILD_DIR"
        rm -rf "$BUILD_DIR/$APP_NAME.app"
        cp -R "$DEBUG_APP" "$BUILD_DIR/"
        ln -sf "$BUILD_DIR/$APP_NAME.app" "./$APP_NAME.app"
        log_ok "Debug build succeeded: $BUILD_DIR/$APP_NAME.app (and ./$APP_NAME.app)"
    else
        log_err "Debug build failed"
        exit 1
    fi
}

build_release() {
    log_step "Building Release configuration"
    xcodebuild -scheme "$SCHEME" \
               -configuration Release \
               -derivedDataPath "$DERIVED_DATA" \
               build | grep -E '\*\*\s*BUILD|error:|warning:' || true
    
    if [ -d "$RELEASE_APP" ]; then
        mkdir -p "$BUILD_DIR"
        rm -rf "$BUILD_DIR/$APP_NAME.app"
        cp -R "$RELEASE_APP" "$BUILD_DIR/"
        ln -sf "$BUILD_DIR/$APP_NAME.app" "./$APP_NAME.app"
        log_ok "Release build succeeded: $BUILD_DIR/$APP_NAME.app (and ./$APP_NAME.app)"
    else
        log_err "Release build failed"
        exit 1
    fi
}

run_app() {
    local target_app="$1"
    if [ ! -d "$target_app" ]; then
        log_err "Application bundle not found at $target_app"
        exit 1
    fi
    
    log_step "Closing any existing MacAmp instance"
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    
    log_step "Launching $target_app"
    open "$target_app"
    log_ok "MacAmp launched successfully!"
}

build_dmg() {
    build_release
    
    log_step "Creating DMG package"
    mkdir -p "$BUILD_DIR"
    
    # Detach any existing mounts
    for dev in $(hdiutil info | grep -i "$APP_NAME" | awk '{print $1}'); do
        hdiutil detach -force "$dev" 2>/dev/null || true
    done
    
    local temp_dir staging dmg_temp mount_dir
    temp_dir="$(mktemp -d)"
    staging="$temp_dir/dmg"
    mkdir -p "$staging"
    
    cp -R "$RELEASE_APP" "$staging/"
    ln -s /Applications "$staging/Applications"
    
    dmg_temp="$temp_dir/${APP_NAME}-temp.dmg"
    rm -f "$DMG_PATH" "$dmg_temp"
    
    hdiutil create -volname "$APP_NAME" \
                   -srcfolder "$staging" \
                   -ov -format UDRW \
                   "$dmg_temp" >/dev/null
    
    mount_dir="/Volumes/${APP_NAME}-dmg-$$"
    [ -d "$mount_dir" ] && hdiutil detach -force "$mount_dir" 2>/dev/null || true
    
    hdiutil attach "$dmg_temp" -mountpoint "$mount_dir" -nobrowse >/dev/null
    
    # Detach and convert to compressed UDZO
    sync
    hdiutil detach "$mount_dir" >/dev/null 2>&1 || diskutil unmount force "$mount_dir" >/dev/null 2>&1 || true
    
    hdiutil convert "$dmg_temp" \
                   -format UDZO \
                   -imagekey zlib-level=9 \
                   -o "$DMG_PATH" >/dev/null
    
    rm -rf "$temp_dir"
    log_ok "DMG package created: $DMG_PATH"
}

run_tests() {
    build_debug
    log_step "Compiling & executing verification test suite"
    mkdir -p "$DERIVED_DATA/ModuleCache"
    local obj_files
    obj_files=$(ls "$DERIVED_DATA"/Build/Intermediates.noindex/MacAmp.build/Debug/MacAmp.build/Objects-normal/arm64/*.o | grep -v 'MacAmpApp.o')
    swiftc -module-cache-path "$DERIVED_DATA/ModuleCache" \
           -target arm64-apple-macos14.0 \
           -I "$DERIVED_DATA/Build/Products/Debug/" \
           -framework Cocoa -framework AVFoundation -framework AppKit -framework WebKit -framework Carbon \
           $obj_files scripts/run_all_tests.swift -o "$BUILD_DIR/run_all_tests"
    
    "$BUILD_DIR/run_all_tests"
    log_ok "All MacAmp tests passed successfully!"
}

show_help() {
    print_banner
    echo "Usage: ./build.sh [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  (none) / build   Fast incremental Debug build (default)"
    echo "  run              Build Debug and launch MacAmp"
    echo "  test             Run test suite and verification checks"
    echo "  release          Build optimized Release configuration"
    echo "  run-release      Build Release and launch MacAmp"
    echo "  clean            Remove DerivedData and build directories"
    echo "  dmg              Build Release and create distributable DMG"
    echo "  help             Show this help message"
    echo ""
}

# Main Command Dispatch
COMMAND="${1:-build}"

case "$COMMAND" in
    build|debug|"")
        print_banner
        build_debug
        ;;
    run)
        print_banner
        build_debug
        run_app "$DEBUG_APP"
        ;;
    test|tests)
        print_banner
        run_tests
        ;;
    release)
        print_banner
        build_release
        ;;
    run-release)
        print_banner
        build_release
        run_app "$RELEASE_APP"
        ;;
    clean)
        print_banner
        clean_artifacts
        ;;
    dmg)
        print_banner
        build_dmg
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        log_err "Unknown command: '$COMMAND'"
        echo ""
        show_help
        exit 1
        ;;
esac