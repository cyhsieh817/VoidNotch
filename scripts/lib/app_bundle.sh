# app_bundle.sh — 共用函式庫：swift build → 組裝 VoidNotch.app
#
# 由 scripts/make_app.sh（ad-hoc 路徑）與 scripts/release_app.sh（Developer ID
# 正式發布路徑）共同 source，避免資產清單漂移（FACTNOTE 紅線 #10）。
#
# 共用函式庫也固定啟用嚴格模式；由呼叫端 source 時沿用相同設定。
# 本檔不做任何 codesign；簽章留給各呼叫端依自己的簽章策略處理。
#
# 呼叫前，呼叫端須先設好以下全域變數：
#   REPO_ROOT   — 專案根目錄絕對路徑
#   BUILD_DIR   — 通常為 "$REPO_ROOT/build"
#   APP         — 通常為 "$BUILD_DIR/VoidNotch.app"
#   BIN_NAME    — 通常為 "VoidNotch"
#   BUNDLE_ID   — 通常為 "dev.voidnotch.VoidNotch"
#   STAMP       — 通常為 "$(date +%Y%m%d%H%M%S)"（供舊 bundle mv 時間戳用）
#
# 提供兩個函式：
#   vn_derive_version    — 推導 VERSION / MARKETING_VERSION / BUILD_NUMBER
#   vn_assemble_bundle   — 組裝 .app（swift build + 複製資產 + 產生 Info.plist）

set -euo pipefail

# 版號：VERSION 檔（權威，見 VERSIONING.md）→ 可達 git tag → 0.0.0
vn_derive_version() {
    if [ -f "$REPO_ROOT/VERSION" ]; then
        VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
    elif TAG_VER="$(git describe --tags --abbrev=0 2>/dev/null)"; then
        VERSION="${TAG_VER#v}"
    else
        VERSION="0.0.0"
    fi
    # Info.plist 行銷版號去掉 -dev 後綴（建置序另用 CFBundleVersion）
    MARKETING_VERSION="${VERSION%-dev}"
    BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
}

vn_assemble_bundle() {
    echo "==> swift build -c release --product ${BIN_NAME}"
    swift build -c release --product "$BIN_NAME"
    BIN_PATH="$(swift build -c release --product "$BIN_NAME" --show-bin-path)/$BIN_NAME"

    VN_SOURCE_COMMIT="unknown"
    VN_SOURCE_DIRTY="unknown"
    if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if VN_SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"; then
            VN_SOURCE_STATUS="$(git -C "$REPO_ROOT" status --porcelain -- App Sources Package.swift Package.resolved 2>/dev/null || true)"
            if [ -n "$VN_SOURCE_STATUS" ]; then
                VN_SOURCE_DIRTY="true"
            else
                VN_SOURCE_DIRTY="false"
            fi
        fi
    fi

    # 專案禁 rm：舊 bundle 移到 build/.trash 留回溯線
    mkdir -p "$BUILD_DIR"
    if [ -d "$APP" ]; then
        mkdir -p "$BUILD_DIR/.trash"
        mv "$APP" "$BUILD_DIR/.trash/VoidNotch.app.$STAMP"
    fi

    echo "==> 組裝 ${APP}"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"

    ICON_ICNS="$REPO_ROOT/resources/AppIcon/AppIcon.icns"
    if [ -f "$ICON_ICNS" ]; then
        cp "$ICON_ICNS" "$APP/Contents/Resources/AppIcon.icns"
        echo "==> App icon: Resources/AppIcon.icns"
    else
        echo "警告：找不到 ${ICON_ICNS}（App 將無自訂圖示）" >&2
    fi

    HOOKS_SRC="$REPO_ROOT/resources/hooks"
    if [ -d "$HOOKS_SRC" ]; then
        mkdir -p "$APP/Contents/Resources/hooks"
        cp "$HOOKS_SRC/peonping-voidnotch-relay.sh" "$APP/Contents/Resources/hooks/"
        cp "$HOOKS_SRC/voidnotch.ts" "$APP/Contents/Resources/hooks/"
        chmod +x "$APP/Contents/Resources/hooks/peonping-voidnotch-relay.sh"
        echo "==> 打包 hook 產物：Resources/hooks/{relay.sh, voidnotch.ts}"
    else
        echo "警告：找不到 ${HOOKS_SRC}（hook 自動串接將無產物可複製）" >&2
    fi

    PROVIDER_ICONS_SRC="$REPO_ROOT/resources/provider-icons"
    PROVIDER_ICONS_DEST="$APP/Contents/Resources/provider-icons"
    if [ -d "$PROVIDER_ICONS_SRC" ]; then
        mkdir -p "$PROVIDER_ICONS_DEST"
        cp -R "$PROVIDER_ICONS_SRC/." "$PROVIDER_ICONS_DEST/"
        echo "==> 打包 provider icon 產物：Resources/provider-icons/"
    else
        echo "警告：找不到 ${PROVIDER_ICONS_SRC}（provider icon 無產物可複製）" >&2
    fi

    for provider_icon in \
        system-health.svg \
        model-usage.svg \
        agent-activity.svg \
        notification.svg \
        display-mode.svg
    do
        if [ ! -f "$PROVIDER_ICONS_DEST/$provider_icon" ]; then
            echo "錯誤：缺少 provider icon 資產：Resources/provider-icons/$provider_icon" >&2
            exit 1
        fi
    done

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
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>  <string>$MARKETING_VERSION</string>
    <key>CFBundleVersion</key>             <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSHumanReadableCopyright</key>    <string>Copyright © 2026 CYHsieh. All rights reserved.</string>
    <key>NSMicrophoneUsageDescription</key> <string>VoidNotch 需要麥克風權限以辨識中文或英文選項。 / VoidNotch needs microphone access to recognize Chinese or English options.</string>
    <key>NSSpeechRecognitionUsageDescription</key> <string>VoidNotch 需要語音辨識權限以將口述選項轉換為既有選項。 / VoidNotch needs speech recognition access to map spoken input to existing options.</string>
    <key>VNSourceCommit</key>           <string>$VN_SOURCE_COMMIT</string>
    <key>VNSourceDirty</key>             <string>$VN_SOURCE_DIRTY</string>
</dict>
</plist>
PLIST
}
