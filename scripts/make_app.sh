#!/usr/bin/env bash
#
# make_app.sh — 免開 Xcode 的 CLI 打包：swift build → VoidNotch.app → ad-hoc 簽名
#
# 需求：機器裝有完整 Xcode 工具鏈（xcode-select -p 指向 Xcode.app），
#       因 DynamicNotchKit 使用 SwiftUI @Entry 巨集，CommandLineTools-only 編不過。
#
# 用法：
#   scripts/make_app.sh              # 打包到 build/VoidNotch.app
#   scripts/make_app.sh --install    # 打包 + 掛到 /Applications 並啟動
#   scripts/make_app.sh --run        # 打包 + 直接啟動 build 內的 bundle
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
APP="$BUILD_DIR/VoidNotch.app"
BIN_NAME="VoidNotch"
BUNDLE_ID="dev.voidnotch.VoidNotch"
ENTITLEMENTS="$REPO_ROOT/App/VoidNotch.entitlements"
STAMP="$(date +%Y%m%d%H%M%S)"

cd "$REPO_ROOT"

VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

echo "==> swift build -c release --product $BIN_NAME"
swift build -c release --product "$BIN_NAME"
BIN_PATH="$(swift build -c release --product "$BIN_NAME" --show-bin-path)/$BIN_NAME"

# 專案禁 rm：舊 bundle 移到 build/.trash 留回溯線
mkdir -p "$BUILD_DIR"
if [ -d "$APP" ]; then
    mkdir -p "$BUILD_DIR/.trash"
    mv "$APP" "$BUILD_DIR/.trash/VoidNotch.app.$STAMP"
fi

echo "==> 組裝 $APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key>          <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>                <string>VoidNotch</string>
    <key>CFBundleDisplayName</key>         <string>VoidNotch</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>$VERSION</string>
    <key>CFBundleVersion</key>             <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSHumanReadableCopyright</key>    <string>Copyright © 2026 CYHsieh. All rights reserved.</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc 簽名（同 Xcode Debug 路線；正式散佈才走 Developer ID + Notarization）"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --verbose=1 "$APP"

echo "==> 完成：${APP} (v${VERSION} build ${BUILD_NUMBER})"

case "${1:-}" in
    --install)
        if pgrep -xq "$BIN_NAME"; then
            echo "==> 停止執行中的 VoidNotch"
            pkill -x "$BIN_NAME" || true
            sleep 1
        fi
        if [ -d "/Applications/VoidNotch.app" ]; then
            mv "/Applications/VoidNotch.app" "$HOME/.Trash/VoidNotch.app.$STAMP"
        fi
        ditto "$APP" "/Applications/VoidNotch.app"
        echo "==> 已掛載 /Applications/VoidNotch.app，啟動中"
        open "/Applications/VoidNotch.app"
        ;;
    --run)
        if pgrep -xq "$BIN_NAME"; then
            pkill -x "$BIN_NAME" || true
            sleep 1
        fi
        open "$APP"
        ;;
    "") ;;
    *)
        echo "未知參數：$1（支援 --install / --run）" >&2
        exit 2
        ;;
esac
