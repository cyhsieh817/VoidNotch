#!/usr/bin/env bash
#
# verify_build_provenance.sh：檢查 .app 或 .zip 的建置來源與陳舊狀態
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TVW_TMP_ROOT="/tmp/tvw"
STAMP="$(date +%Y%m%d%H%M%S)-$$"
INPUT_PATH="${1:-}"
ARTIFACT_PATH=""
APP_PATH=""
TMP_DIR=""

vn_cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        mv "$TMP_DIR" "$TVW_TMP_ROOT/_DELETE_verify-build-provenance.$STAMP" || true
    fi
}
trap vn_cleanup EXIT

if [ "$#" -ne 1 ]; then
    echo "用法：scripts/verify_build_provenance.sh <app 或 zip 路徑>" >&2
    exit 2
fi

case "$INPUT_PATH" in
    /*)
        ARTIFACT_PATH="$INPUT_PATH"
        ;;
    *)
        ARTIFACT_PATH="$REPO_ROOT/$INPUT_PATH"
        ;;
esac

if [ ! -e "$ARTIFACT_PATH" ]; then
    echo "UNKNOWN：找不到產物：$ARTIFACT_PATH" >&2
    exit 2
fi

case "$ARTIFACT_PATH" in
    *.app|*.APP)
        APP_PATH="$ARTIFACT_PATH"
        ;;
    *.zip|*.ZIP)
        mkdir -p "$TVW_TMP_ROOT"
        TMP_DIR="$(mktemp -d "$TVW_TMP_ROOT/verify-build-provenance.XXXXXX")"
        if ! ditto -x -k "$ARTIFACT_PATH" "$TMP_DIR" >/dev/null 2>&1; then
            echo "UNKNOWN：無法解開 zip 產物：$ARTIFACT_PATH" >&2
            exit 2
        fi
        APP_PATH="$(find "$TMP_DIR" -type d -name '*.app' -prune -print -quit)"
        if [ -z "$APP_PATH" ]; then
            echo "UNKNOWN：zip 內找不到 .app 產物：$ARTIFACT_PATH" >&2
            exit 2
        fi
        ;;
    *)
        echo "UNKNOWN：只接受 .app 或 .zip 產物：$ARTIFACT_PATH" >&2
        exit 2
        ;;
esac

PLIST_PATH="$APP_PATH/Contents/Info.plist"
if [ ! -f "$PLIST_PATH" ]; then
    echo "UNKNOWN：產物缺少 Info.plist：$PLIST_PATH" >&2
    exit 2
fi

if ! VN_SOURCE_COMMIT="$(plutil -extract VNSourceCommit raw -o - "$PLIST_PATH" 2>/dev/null)"; then
    echo "UNKNOWN：產物沒有 VNSourceCommit，這是未加來源章的舊產物。" >&2
    exit 2
fi
if ! VN_SOURCE_DIRTY="$(plutil -extract VNSourceDirty raw -o - "$PLIST_PATH" 2>/dev/null)"; then
    echo "UNKNOWN：產物沒有 VNSourceDirty，這是未加來源章的舊產物。" >&2
    exit 2
fi

if [ "$VN_SOURCE_COMMIT" = "unknown" ] || [ "$VN_SOURCE_DIRTY" = "unknown" ]; then
    echo "UNKNOWN：產物的來源章是 unknown，無法對應到 git commit。"
    exit 2
fi

if ! HEAD_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"; then
    echo "UNKNOWN：目前不是 git 工作區，無法比對產物來源。"
    exit 2
fi

if [ "$VN_SOURCE_DIRTY" != "true" ] && [ "$VN_SOURCE_DIRTY" != "false" ]; then
    echo "UNKNOWN：VNSourceDirty 值不合法：$VN_SOURCE_DIRTY"
    exit 2
fi

if [ "$VN_SOURCE_DIRTY" = "true" ]; then
    echo "DIRTY：產物是在有未提交變更的來源上建置，無法可靠溯源。"
    echo "來源 commit：$VN_SOURCE_COMMIT"
    echo "目前 HEAD：$HEAD_COMMIT"
    exit 1
fi

if [ "$VN_SOURCE_COMMIT" = "$HEAD_COMMIT" ]; then
    echo "FRESH：來源 commit 等於目前 HEAD，且 VNSourceDirty=false。"
    echo "來源 commit：$VN_SOURCE_COMMIT"
    exit 0
fi

if git -C "$REPO_ROOT" merge-base --is-ancestor "$VN_SOURCE_COMMIT" "$HEAD_COMMIT" >/dev/null 2>&1; then
    echo "STALE：來源 commit 是目前 HEAD 的祖先，產物缺少以下會影響二進位檔的後續變更："
    STALE_COMMITS="$(git -C "$REPO_ROOT" log --format='%h %s' "$VN_SOURCE_COMMIT..$HEAD_COMMIT" -- App Sources Package.swift)"
    if [ -n "$STALE_COMMITS" ]; then
        printf '%s\n' "$STALE_COMMITS"
    else
        echo "其後沒有變更 App、Sources 或 Package.swift 的 commit。"
    fi
    echo "來源 commit：$VN_SOURCE_COMMIT"
    echo "目前 HEAD：$HEAD_COMMIT"
    exit 1
fi

echo "DIVERGED：來源 commit 不是目前 HEAD 的祖先，也不等於目前 HEAD。"
echo "來源 commit：$VN_SOURCE_COMMIT"
echo "目前 HEAD：$HEAD_COMMIT"
exit 1
