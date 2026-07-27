#!/bin/bash
# 從 VERSION 產生站台使用的下載版本資訊，僅更新本機檔案。

set -euo pipefail

DEFAULT_WEB_REPO="/Volumes/YuData/APPDEV/102_Github/voidnotch-web"
WEB_REPO="$DEFAULT_WEB_REPO"
NOTES=""
NOTES_SET=0
ZIP_PATH=""
ZIP_SET=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --web-repo)
            if [ "$#" -lt 2 ]; then
                echo "錯誤：--web-repo 需要提供路徑。" >&2
                exit 2
            fi
            WEB_REPO="$2"
            shift 2
            ;;
        --notes)
            if [ "$#" -lt 2 ]; then
                echo "錯誤：--notes 需要提供更新說明。" >&2
                exit 2
            fi
            NOTES="$2"
            NOTES_SET=1
            shift 2
            ;;
        --zip)
            if [ "$#" -lt 2 ]; then
                echo "錯誤：--zip 需要提供路徑。" >&2
                exit 2
            fi
            ZIP_PATH="$2"
            ZIP_SET=1
            shift 2
            ;;
        *)
            echo "未知參數：${1}（支援 --web-repo <路徑> / --notes \"<更新說明>\" / --zip <路徑>）" >&2
            exit 2
            ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"

if [ ! -f "$VERSION_FILE" ]; then
    echo "錯誤：找不到 VERSION：${VERSION_FILE}" >&2
    exit 1
fi

VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
MARKETING_VERSION="${VERSION%-dev}"

if [ -z "$MARKETING_VERSION" ]; then
    echo "錯誤：VERSION 無法推導有效的行銷版號。" >&2
    exit 1
fi

URL="https://dl.voidnotch.labgrimoire.com/VoidNotch-${MARKETING_VERSION}-macOS-arm64.zip"

ZIP_SHA256=""
if [ "$ZIP_SET" -eq 1 ]; then
    if [ ! -f "$ZIP_PATH" ]; then
        echo "錯誤：--zip 路徑不存在：${ZIP_PATH}" >&2
        exit 2
    fi
    ZIP_SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
fi

mkdir -p "$WEB_REPO/public/downloads"
WEB_REPO="$(cd "$WEB_REPO" && pwd)"
TARGET="$WEB_REPO/public/downloads/version.json"

if [ -e "$TARGET" ]; then
    mkdir -p "/tmp/tvw"
    BACKUP="/tmp/tvw/version.json.bak.$(date +%s)"
    cp "$TARGET" "$BACKUP"
    echo "已備份既有 version.json：${BACKUP}"
fi

python3 -c '
import json
import pathlib
import sys

target = pathlib.Path(sys.argv[1])
# 欄位順序：version → url → [sha256] → notes（sha256 僅 --zip 時插入）
expected = {
    "version": sys.argv[2],
    "url": sys.argv[3],
}
if sys.argv[6] == "1":
    expected["sha256"] = sys.argv[7]
expected["notes"] = sys.argv[5] if sys.argv[4] == "1" else None

with target.open("w", encoding="utf-8") as handle:
    json.dump(expected, handle, ensure_ascii=False, indent=2)
    handle.write("\n")

with target.open("r", encoding="utf-8") as handle:
    actual = json.load(handle)

if actual != expected:
    raise SystemExit("生成的 version.json 驗證失敗")
' "$TARGET" "$MARKETING_VERSION" "$URL" "$NOTES_SET" "$NOTES" "$ZIP_SET" "$ZIP_SHA256"

echo "已生成並驗證：${TARGET}"
echo "後續部署步驟："
echo "① 確認 R2 已有 ${URL}（wrangler r2 object put voidnotch-downloads/<檔名> --file <zip> --remote）"
echo "② 確認 ${WEB_REPO}/src/config.ts 的 PUBLIC_BINARY_DOWNLOAD_URL 同步"
echo "③ cd ${WEB_REPO} && bun run build && bun run deploy"
echo "④ curl -s https://voidnotch.labgrimoire.com/downloads/version.json 驗證"
echo "⑤ 站台 repo commit＋PR"
