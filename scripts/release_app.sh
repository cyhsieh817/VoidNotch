#!/usr/bin/env bash
#
# release_app.sh — 正式發布路徑：swift build → VoidNotch.app →
#                  Developer ID 簽章 + Hardened Runtime → Notarization → Staple
#
# 需求：機器裝有完整 Xcode 工具鏈（同 make_app.sh），並已安裝
#       Developer ID Application 憑證與（完整模式時）notarytool 的
#       keychain profile（見 VOIDNOTCH_NOTARY_PROFILE）。
#
# 用法：
#   scripts/release_app.sh              # 打包 + 簽章 + 公證 + 裝訂 + 驗收
#   scripts/release_app.sh --sign-only   # 只簽 Developer ID + hardened runtime + spctl，
#                                         # 跳過公證，供 Phase 2 憑證未就緒時本機測試
#
set -euo pipefail

SIGN_ONLY=false
ALLOW_DIRTY=false
for arg in "$@"; do
    case "$arg" in
        --sign-only)
            SIGN_ONLY=true
            ;;
        --allow-dirty)
            ALLOW_DIRTY=true
            ;;
        *)
            echo "未知參數：${arg}（支援 --sign-only / --allow-dirty）" >&2
            exit 2
            ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
APP="$BUILD_DIR/VoidNotch.app"
BIN_NAME="VoidNotch"
BUNDLE_ID="dev.voidnotch.VoidNotch"
ENTITLEMENTS="$REPO_ROOT/App/VoidNotch.entitlements"
STAMP="$(date +%Y%m%d%H%M%S)"

# 簽章識別：不設預設值。此腳本會匯出到公開 repo，硬編憑證通用名稱等同把
# 維護者法定姓名與 Apple Team ID 寫進公開樹（技術上非機密——散佈版跑
# `codesign -dv` 即可讀到——但不該以明文躺在可被 fork 的公開原始碼裡）。
# 用法：export VOIDNOTCH_SIGN_IDENTITY="Developer ID Application: <Name> (<TeamID>)"
# 查可用身分：security find-identity -v -p codesigning
if [ -z "${VOIDNOTCH_SIGN_IDENTITY:-}" ]; then
    echo "錯誤：未設定 VOIDNOTCH_SIGN_IDENTITY。" >&2
    echo "  export VOIDNOTCH_SIGN_IDENTITY=\"Developer ID Application: <Name> (<TeamID>)\"" >&2
    echo "  可用身分：security find-identity -v -p codesigning" >&2
    exit 2
fi
VOIDNOTCH_NOTARY_PROFILE="${VOIDNOTCH_NOTARY_PROFILE:-VoidNotch-Notary}"

cd "$REPO_ROOT"

"$REPO_ROOT/scripts/verify_pbxproj_registration.sh"

if [ "$ALLOW_DIRTY" = true ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "警告：已使用 --allow-dirty，這是本機實驗建置，產物可能無法溯源到乾淨的 commit。"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
else
    if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "錯誤：目前不是 git 工作區，產物將無法溯源到任何 commit。請先提交或 stash，或使用 --allow-dirty 進行本機實驗。" >&2
        exit 1
    fi

    SOURCE_STATUS="$(git -C "$REPO_ROOT" status --porcelain -- App Sources Package.swift Package.resolved)"
    if [ -n "$SOURCE_STATUS" ]; then
        echo "錯誤：App、Sources、Package.swift 或 Package.resolved 有未提交變更。" >&2
        echo "產物將無法溯源到任何 commit，請先提交或 stash。" >&2
        echo "$SOURCE_STATUS" >&2
        exit 1
    fi
fi

# shellcheck source=lib/app_bundle.sh
source "$REPO_ROOT/scripts/lib/app_bundle.sh"

vn_derive_version
vn_assemble_bundle

VN_SOURCE_COMMIT="$(plutil -extract VNSourceCommit raw -o - "$APP/Contents/Info.plist")"
VN_SOURCE_DIRTY="$(plutil -extract VNSourceDirty raw -o - "$APP/Contents/Info.plist")"
VN_SOURCE_COMMIT_SHORT="${VN_SOURCE_COMMIT:0:12}"

echo "==> Developer ID 簽章 + Hardened Runtime：${VOIDNOTCH_SIGN_IDENTITY}"
codesign --force --options runtime --timestamp --sign "$VOIDNOTCH_SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"

if [ "$SIGN_ONLY" = true ]; then
    echo "==> 驗證簽章（--sign-only，跳過公證）"
    codesign --verify --deep --strict --verbose=2 "$APP"

    echo "==> spctl 評估（未公證前預期 rejected，屬正常）"
    spctl -a -vvv --type exec "$APP" || echo "==> 提示：spctl 未通過屬預期（尚未公證），--sign-only 到此結束"

    echo "==> 完成（--sign-only）：${APP} (v${MARKETING_VERSION} / VERSION=${VERSION} build ${BUILD_NUMBER})，來源 commit ${VN_SOURCE_COMMIT_SHORT}，VNSourceDirty=${VN_SOURCE_DIRTY}"
    exit 0
fi

echo "==> 打包送審用 zip"
ZIP="$BUILD_DIR/VoidNotch-notarize.zip"
if [ -f "$ZIP" ]; then
    mkdir -p "$BUILD_DIR/.trash"
    mv "$ZIP" "$BUILD_DIR/.trash/VoidNotch-notarize.zip.$STAMP"
fi
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 送交 Apple Notary Service（keychain profile：${VOIDNOTCH_NOTARY_PROFILE}）"
xcrun notarytool submit "$ZIP" --keychain-profile "$VOIDNOTCH_NOTARY_PROFILE" --wait

echo "==> 裝訂公證票證"
xcrun stapler staple "$APP"

echo "==> 驗收：codesign"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> 驗收：spctl（應為 accepted / source=Notarized Developer ID）"
SPCTL_OUT="$(spctl -a -vvv --type exec "$APP" 2>&1)"
echo "$SPCTL_OUT"
if ! echo "$SPCTL_OUT" | grep -q "accepted"; then
    echo "錯誤：spctl 未回報 accepted，公證驗收失敗" >&2
    exit 1
fi

# staple + spctl accepted 之後才產正式散佈 zip（勿把送審用 VoidNotch-notarize.zip 上傳 R2）
DIST_ZIP="$BUILD_DIR/VoidNotch-${MARKETING_VERSION}-macOS-arm64.zip"
if [ -f "$DIST_ZIP" ]; then
    mkdir -p "$BUILD_DIR/.trash"
    mv "$DIST_ZIP" "$BUILD_DIR/.trash/VoidNotch-${MARKETING_VERSION}-macOS-arm64.zip.$STAMP"
fi
echo "==> 打包正式散佈 zip：${DIST_ZIP}"
ditto -c -k --keepParent "$APP" "$DIST_ZIP"

DIST_SHA256="$(shasum -a 256 "$DIST_ZIP" | awk '{print $1}')"
DIST_ZIP_BASENAME="$(basename "$DIST_ZIP")"
echo "${DIST_SHA256}  ${DIST_ZIP_BASENAME}" | tee "$DIST_ZIP.sha256"
echo "==> 正式散佈 zip sha256：${DIST_SHA256}"
echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "警語：R2 上傳一律使用正式散佈 zip："
echo "  ${DIST_ZIP}"
echo "VoidNotch-notarize.zip 僅為 notarytool 送審暫存，禁止上傳。"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo ""

echo "==> 完成：${APP} (v${MARKETING_VERSION} / VERSION=${VERSION} build ${BUILD_NUMBER})，已公證＋裝訂；來源 commit ${VN_SOURCE_COMMIT_SHORT}，VNSourceDirty=${VN_SOURCE_DIRTY}"
echo "==> 正式散佈：${DIST_ZIP}（sha256 ${DIST_SHA256}）"
