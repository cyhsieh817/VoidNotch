#!/usr/bin/env bash
#
# verify_pbxproj_registration.sh — 檢查 App/ Swift 是否完整登記到 Xcode target
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="$REPO_ROOT/VoidNotch.xcodeproj/project.pbxproj"
ALLOWLIST="$REPO_ROOT/scripts/pbxproj_registration_allowlist.txt"

if [ ! -f "$PBXPROJ" ]; then
    echo "錯誤：找不到 Xcode 專案檔：$PBXPROJ" >&2
    exit 2
fi

is_allowlisted() {
    local relative_path="$1"
    local allowlisted_path

    [ -f "$ALLOWLIST" ] || return 1

    while IFS= read -r allowlisted_path || [ -n "$allowlisted_path" ]; do
        case "$allowlisted_path" in
            ""|\#*)
                continue
                ;;
        esac
        [ "$allowlisted_path" = "$relative_path" ] && return 0
    done < "$ALLOWLIST"

    return 1
}

get_file_reference_id() {
    local filename="$1"

    awk -v filename="$filename" '
        /\/\* Begin PBXFileReference section \*\// { in_section=1; next }
        /\/\* End PBXFileReference section \*\// { in_section=0 }
        in_section && /isa = PBXFileReference;/ &&
            index($0, "/* " filename " */") > 0 &&
            (index($0, "path = " filename ";") > 0 ||
             index($0, "path = \"" filename "\";") > 0) {
            print $1
            found=1
            exit
        }
        END { exit(found ? 0 : 1) }
    ' "$PBXPROJ"
}

has_build_file() {
    local filename="$1"
    local file_reference_id="$2"

    awk -v filename="$filename" -v file_reference_id="$file_reference_id" '
        /\/\* Begin PBXBuildFile section \*\// { in_section=1; next }
        /\/\* End PBXBuildFile section \*\// { in_section=0 }
        in_section && /isa = PBXBuildFile;/ &&
            ((file_reference_id != "" && index($0, "fileRef = " file_reference_id) > 0) ||
             (file_reference_id == "" && index($0, "/* " filename " in Sources */") > 0)) {
            found=1
            exit
        }
        END { exit(found ? 0 : 1) }
    ' "$PBXPROJ"
}

get_build_file_id() {
    local filename="$1"
    local file_reference_id="$2"

    awk -v filename="$filename" -v file_reference_id="$file_reference_id" '
        /\/\* Begin PBXBuildFile section \*\// { in_section=1; next }
        /\/\* End PBXBuildFile section \*\// { in_section=0 }
        in_section && /isa = PBXBuildFile;/ &&
            ((file_reference_id != "" && index($0, "fileRef = " file_reference_id) > 0) ||
             (file_reference_id == "" && index($0, "/* " filename " in Sources */") > 0)) {
            print $1
            found=1
            exit
        }
        END { exit(found ? 0 : 1) }
    ' "$PBXPROJ"
}

has_group_child() {
    local filename="$1"
    local file_reference_id="$2"

    awk -v filename="$filename" -v file_reference_id="$file_reference_id" '
        /\/\* Begin PBXGroup section \*\// { in_section=1; next }
        /\/\* End PBXGroup section \*\// { in_section=0; in_children=0 }
        in_section && /children = \(/ { in_children=1; next }
        in_children && /^[[:space:]]*\);/ { in_children=0; next }
        in_children &&
            ((file_reference_id != "" && index($0, file_reference_id) > 0) ||
             (file_reference_id == "" && index($0, "/* " filename " */") > 0)) {
            found=1
            exit
        }
        END { exit(found ? 0 : 1) }
    ' "$PBXPROJ"
}

has_sources_build_phase_file() {
    local filename="$1"
    local build_file_id="$2"

    awk -v filename="$filename" -v build_file_id="$build_file_id" '
        /\/\* Begin PBXSourcesBuildPhase section \*\// { in_section=1; next }
        /\/\* End PBXSourcesBuildPhase section \*\// { in_section=0; in_files=0 }
        in_section && /files = \(/ { in_files=1; next }
        in_files && /^[[:space:]]*\);/ { in_files=0; next }
        in_files &&
            ((build_file_id != "" && index($0, build_file_id) > 0) ||
             index($0, "/* " filename " in Sources */") > 0) {
            found=1
            exit
        }
        END { exit(found ? 0 : 1) }
    ' "$PBXPROJ"
}

swift_files=()
collect_swift_files() {
    local directory="$1"
    local entry

    for entry in "$directory"/*; do
        [ -e "$entry" ] || continue
        if [ -d "$entry" ]; then
            collect_swift_files "$entry"
        elif [ -f "$entry" ]; then
            case "$entry" in
                *.swift)
                    swift_files+=("$entry")
                    ;;
            esac
        fi
    done
}

collect_swift_files "$REPO_ROOT/App"
missing_count=0
allowlisted_count=0

for swift_file in "${swift_files[@]}"; do
    relative_path="${swift_file#"$REPO_ROOT"/}"
    if is_allowlisted "$relative_path"; then
        allowlisted_count=$((allowlisted_count + 1))
        continue
    fi

    filename="${swift_file##*/}"
    file_reference_id=""
    if file_reference_id="$(get_file_reference_id "$filename")"; then
        :
    else
        file_reference_id=""
    fi

    build_file_id=""
    if has_build_file "$filename" "$file_reference_id"; then
        if build_file_id="$(get_build_file_id "$filename" "$file_reference_id")"; then
            :
        else
            build_file_id=""
        fi
    fi

    missing=()
    if [ -z "$file_reference_id" ]; then
        missing+=("PBXFileReference")
    fi
    if ! has_build_file "$filename" "$file_reference_id"; then
        missing+=("PBXBuildFile")
    fi
    if ! has_group_child "$filename" "$file_reference_id"; then
        missing+=("PBXGroup.children")
    fi
    if ! has_sources_build_phase_file "$filename" "$build_file_id"; then
        missing+=("PBXSourcesBuildPhase.files")
    fi

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "錯誤：$relative_path 缺少 pbxproj 登記：${missing[*]}" >&2
        missing_count=$((missing_count + 1))
    fi
done

if [ "$missing_count" -gt 0 ]; then
    echo "錯誤：新增 App/ 檔需同步登記 pbxproj 四處：PBXBuildFile、PBXFileReference、PBXGroup.children、PBXSourcesBuildPhase.files。" >&2
    # ${} 不可省：變數後緊接全形字元時 bash 會把多位元組字元吃進變數名，set -u 下直接崩
    echo "若檔案刻意不進 Xcode target，請將 repo 相對路徑寫入白名單：${ALLOWLIST}（相對路徑：scripts/pbxproj_registration_allowlist.txt）。" >&2
    exit 1
fi

echo "OK：App/ Swift 全數完成 pbxproj 四處登記（白名單跳過 ${allowlisted_count} 檔）。"
