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

# shellcheck source=lib/app_bundle.sh
source "$REPO_ROOT/scripts/lib/app_bundle.sh"

vn_derive_version
vn_assemble_bundle

echo "==> ad-hoc 簽名（同 Xcode Debug 路線；正式散佈才走 Developer ID + Notarization）"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --verbose=1 "$APP"

echo "==> 完成：${APP} (v${MARKETING_VERSION} / VERSION=${VERSION} build ${BUILD_NUMBER})"

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
