#!/usr/bin/env bash
#
# make_debug_app.sh — isolated VoidNotch Debug companion packaging
#
# Usage:
#   scripts/make_debug_app.sh              # package build/debug/VoidNotch Debug.app
#   scripts/make_debug_app.sh --run        # package and launch the debug companion
#   scripts/make_debug_app.sh --install    # package, install, and launch the debug companion
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$REPO_ROOT/build"
DEBUG_BUILD_DIR="$BUILD_ROOT/debug"
APP_BUNDLE="$DEBUG_BUILD_DIR/VoidNotch Debug.app"
BIN_NAME="VoidNotchDebug"
BUNDLE_ID="dev.voidnotch.VoidNotch.debug"
DISPLAY_NAME="VoidNotch Debug"
INSTALL_BUNDLE="/Applications/VoidNotch Debug.app"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BUILD_VERSION="$(date -u +%Y%m%d%H%M%S)"
INSTALL=0
RUN=0

usage() {
    printf '%s\n' \
        'Usage: scripts/make_debug_app.sh [--run] [--install]' \
        '  --run       launch build/debug/VoidNotch Debug.app' \
        '  --install   copy to /Applications/VoidNotch Debug.app and launch it'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --run)
            RUN=1
            ;;
        --install)
            INSTALL=1
            RUN=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

move_existing_bundle() {
    local bundle_path="$1"
    local trash_dir="$2"
    if [ -e "$bundle_path" ]; then
        mkdir -p "$trash_dir"
        mv "$bundle_path" "$trash_dir/_DELETE_${STAMP}_$(basename "$bundle_path")"
    fi
}

stop_debug_process() {
    if pgrep -xq VoidNotchDebug; then
        pkill -x VoidNotchDebug || true
        sleep 1
    fi
}

cd "$REPO_ROOT"
printf '%s\n' '==> swift build --product VoidNotchDebug --configuration debug'
swift build --product "$BIN_NAME" --configuration debug
BIN_PATH="$REPO_ROOT/.build/debug/$BIN_NAME"

if [ ! -x "$BIN_PATH" ]; then
    printf 'Missing executable: %s\n' "$BIN_PATH" >&2
    exit 1
fi

move_existing_bundle "$APP_BUNDLE" "$BUILD_ROOT/.trash"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$BIN_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$BIN_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoidNotch Debug needs microphone access to recognize Chinese and English options. / VoidNotch Debug 需要麥克風權限以辨識中文與英文選項。</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>VoidNotch Debug needs speech recognition access to match spoken options locally. / VoidNotch Debug 需要語音辨識權限以在本機比對口述選項。</string>
</dict>
</plist>
PLIST

printf '%s\n' '==> ad-hoc signing VoidNotch Debug.app'
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --verbose=1 "$APP_BUNDLE"

if [ "$INSTALL" -eq 1 ]; then
    stop_debug_process
    move_existing_bundle "$INSTALL_BUNDLE" "$HOME/.Trash"
    ditto "$APP_BUNDLE" "$INSTALL_BUNDLE"
    printf '==> installed: %s\n' "$INSTALL_BUNDLE"
fi

if [ "$RUN" -eq 1 ]; then
    stop_debug_process
    if [ "$INSTALL" -eq 1 ]; then
        open "$INSTALL_BUNDLE"
    else
        open "$APP_BUNDLE"
    fi
fi

printf '==> packaged: %s\n' "$APP_BUNDLE"
