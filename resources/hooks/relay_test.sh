#!/bin/bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELAY="$HERE/peonping-voidnotch-relay.sh"
TMP="$(mktemp -d)"
EVENTS="$TMP/agent-events.jsonl"
fail=0

# 1) grok：GROK_WORKSPACE_ROOT 存在 → provider=grok（即使 --provider claude）
echo '{"hook_event_name":"SessionStart"}' | \
  GROK_WORKSPACE_ROOT="$TMP" VOIDNOTCH_AGENT_EVENTS="$EVENTS" bash "$RELAY" --provider claude
if ! grep -q '"provider":"grok"' "$EVENTS"; then echo "FAIL: grok 判定"; fail=1; fi

# 2) failed：payload status=failed → record status failed
echo '{"hook_event_name":"Stop","status":"failed"}' | \
  VOIDNOTCH_AGENT_EVENTS="$EVENTS" bash "$RELAY" --provider codex
if ! grep -q '"status":"failed"' "$EVENTS"; then echo "FAIL: failed 對映"; fail=1; fi

# 3) 截尾：灌 5100 筆後行數應 <= 5000（加快測試，原始測試為 6000 筆）
for i in $(seq 1 5100); do echo '{"hook_event_name":"UserPromptSubmit"}'; done | \
  while read -r line; do echo "$line" | VOIDNOTCH_AGENT_EVENTS="$EVENTS" bash "$RELAY" --provider claude >/dev/null 2>&1; done
lines=$(wc -l < "$EVENTS")
if [ "$lines" -gt 5000 ]; then echo "FAIL: 截尾（$lines 行）"; fail=1; fi

# 4) input broker 往返：App 端（Swift UUID.uuidString）寫的是大寫 UUID，
#    relay 產生的是小寫。兩端必須大小寫無關地對得上，否則 broker 空等到 timeout。
#    新契約 fail-closed：capabilities 缺失時不接管，故 broker 測試須先宣告 answerable_providers。
#    此 SUPPORT fixture 亦供後續 codex / hermes 測試重用。
BROKER_EVENTS="$TMP/broker-events.jsonl"
RESPONSES="$TMP/responses"
SUPPORT="$TMP/support"
mkdir -p "$RESPONSES" "$SUPPORT"
printf '%s' '{"schema_version":1,"answerable_providers":["claude","codex","pi"]}' \
  > "$SUPPORT/broker-capabilities.json"
BROKER_OUT="$TMP/broker-out.json"
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Q1","header":"H","options":[{"label":"甲","description":""},{"label":"乙","description":""}],"multiSelect":false}]}}'
echo "$PAYLOAD" | VOIDNOTCH_AGENT_EVENTS="$BROKER_EVENTS" VOIDNOTCH_RESPONSE_DIR="$RESPONSES" \
  VOIDNOTCH_SUPPORT_DIR="$SUPPORT" \
  VOIDNOTCH_ASSUME_RUNNING=1 VOIDNOTCH_INPUT_BROKER_TIMEOUT=10 bash "$RELAY" --provider claude > "$BROKER_OUT" &
broker_pid=$!

rid=""
for _ in $(seq 1 50); do
    if [ -s "$BROKER_EVENTS" ]; then
        rid="$(/usr/bin/python3 -c 'import json,sys;print(json.loads(open(sys.argv[1]).read().splitlines()[-1]).get("input_request",{}).get("request_id",""))' "$BROKER_EVENTS")"
        [ -n "$rid" ] && break
    fi
    sleep 0.1
done

if [ -z "$rid" ]; then
    echo "FAIL: broker 未寫出 input_request"
    fail=1
    kill "$broker_pid" 2>/dev/null
else
    # 完全模擬 App 端 AgentInputResponseWriter：檔名與 request_id 皆為大寫 UUID
    upper_rid="$(printf '%s' "$rid" | tr '[:lower:]' '[:upper:]')"
    /usr/bin/python3 -c 'import json,sys;json.dump({"request_id":sys.argv[1],"answers":{"Q1":"甲"}},open(sys.argv[2],"w"))' \
        "$upper_rid" "$RESPONSES/$upper_rid.json"
    wait "$broker_pid"
    if ! grep -q '"permissionDecision":"allow"' "$BROKER_OUT"; then
        echo "FAIL: broker 未接受 App 端（大寫 UUID）回應"
        fail=1
    elif ! grep -q '"answers"' "$BROKER_OUT"; then
        echo "FAIL: broker 輸出缺 answers"
        fail=1
    fi
fi

# 5) dismissal：使用者關掉卡片／卡片逾時 → relay 立即放行（不輸出 updatedInput），
#    agent 才能馬上在終端機提問，而不是空等到 broker timeout。
DISMISS_EVENTS="$TMP/dismiss-events.jsonl"
DISMISS_OUT="$TMP/dismiss-out.json"
echo "$PAYLOAD" | VOIDNOTCH_AGENT_EVENTS="$DISMISS_EVENTS" VOIDNOTCH_RESPONSE_DIR="$RESPONSES" \
  VOIDNOTCH_SUPPORT_DIR="$SUPPORT" \
  VOIDNOTCH_ASSUME_RUNNING=1 VOIDNOTCH_INPUT_BROKER_TIMEOUT=30 bash "$RELAY" --provider claude > "$DISMISS_OUT" &
dismiss_pid=$!

rid=""
for _ in $(seq 1 50); do
    if [ -s "$DISMISS_EVENTS" ]; then
        rid="$(/usr/bin/python3 -c 'import json,sys;print(json.loads(open(sys.argv[1]).read().splitlines()[-1]).get("input_request",{}).get("request_id",""))' "$DISMISS_EVENTS")"
        [ -n "$rid" ] && break
    fi
    sleep 0.1
done

if [ -z "$rid" ]; then
    echo "FAIL: dismissal 情境未寫出 input_request"
    fail=1
    kill "$dismiss_pid" 2>/dev/null
else
    started=$(date +%s)
    /usr/bin/python3 -c 'import json,sys;json.dump({"request_id":sys.argv[1],"dismissed":True},open(sys.argv[2],"w"))' \
        "$rid" "$RESPONSES/$rid.json"
    wait "$dismiss_pid"
    elapsed=$(( $(date +%s) - started ))
    if [ -s "$DISMISS_OUT" ]; then
        echo "FAIL: dismissal 後 relay 仍輸出內容（應完全不接管）"
        fail=1
    fi
    if [ "$elapsed" -ge 10 ]; then
        echo "FAIL: dismissal 未即時放行（等了 ${elapsed}s）"
        fail=1
    fi
fi

# --- codex PermissionRequest broker ---------------------------------------
# codex 的核准提示走 PermissionRequest，回傳契約與 claude 完全不同：
#   {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
# behavior 的 enum 只有 allow/deny；updatedInput 會 fail-closed。
CODEX_PAYLOAD='{"hook_event_name":"PermissionRequest","tool_name":"apply_patch","tool_input":{"path":"a.txt"}}'

# SUPPORT / broker-capabilities.json 已於測試 4 建立（含 claude、codex、pi），此處重用。

# 共用：跑一次 codex broker，把使用者的選擇寫回，回傳 relay 的 stdout
run_codex_broker() {
    local label="$1" answer="$2" outfile="$3"
    local ev="$TMP/codex-$label.jsonl"
    echo "$CODEX_PAYLOAD" | VOIDNOTCH_AGENT_EVENTS="$ev" VOIDNOTCH_RESPONSE_DIR="$RESPONSES" \
      VOIDNOTCH_SUPPORT_DIR="$SUPPORT" VOIDNOTCH_ASSUME_RUNNING=1 \
      VOIDNOTCH_INPUT_BROKER_TIMEOUT=10 bash "$RELAY" --provider codex > "$outfile" &
    local pid=$!
    local rid=""
    for _ in $(seq 1 50); do
        if [ -s "$ev" ]; then
            rid="$(/usr/bin/python3 -c 'import json,sys;print(json.loads(open(sys.argv[1]).read().splitlines()[-1]).get("input_request",{}).get("request_id",""))' "$ev")"
            [ -n "$rid" ] && break
        fi
        sleep 0.1
    done
    if [ -z "$rid" ]; then
        kill "$pid" 2>/dev/null
        return 1
    fi
    local q
    q="$(/usr/bin/python3 -c 'import json,sys;print(json.loads(open(sys.argv[1]).read().splitlines()[-1])["input_request"]["questions"][0]["question"])' "$ev")"
    # App 端一律大寫 UUID
    local upper_rid
    upper_rid="$(printf '%s' "$rid" | tr '[:lower:]' '[:upper:]')"
    /usr/bin/python3 -c 'import json,sys;json.dump({"request_id":sys.argv[1],"answers":{sys.argv[3]:sys.argv[4]}},open(sys.argv[2],"w"))' \
        "$upper_rid" "$RESPONSES/$upper_rid.json" "$q" "$answer"
    wait "$pid"
    return 0
}

# 6) 允許 → behavior=allow（codex 會直接放行，終端機那個選單根本不會出現）
CODEX_ALLOW="$TMP/codex-allow.json"
if ! run_codex_broker allow "允許" "$CODEX_ALLOW"; then
    echo "FAIL: codex broker 未寫出 input_request"
    fail=1
else
    if ! /usr/bin/python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
h=d["hookSpecificOutput"]
assert h["hookEventName"]=="PermissionRequest", h
assert h["decision"]=={"behavior":"allow"}, h["decision"]
assert "updatedInput" not in h.get("decision",{}), "updatedInput 會讓 codex fail-closed"
' "$CODEX_ALLOW" 2>/dev/null; then
        echo "FAIL: codex allow 的輸出不符 PermissionRequest 契約"
        fail=1
    fi
fi

# 7) 拒絕 → behavior=deny，且必須帶 message
CODEX_DENY="$TMP/codex-deny.json"
if ! run_codex_broker deny "拒絕" "$CODEX_DENY"; then
    echo "FAIL: codex broker（拒絕）未寫出 input_request"
    fail=1
else
    if ! /usr/bin/python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))["hookSpecificOutput"]["decision"]
assert d["behavior"]=="deny", d
assert d.get("message"), "deny 必須附理由"
' "$CODEX_DENY" 2>/dev/null; then
        echo "FAIL: codex deny 的輸出不符契約"
        fail=1
    fi
fi

# 8) App 沒在跑 → 完全不接管。少了這道判斷，broker 會空等到 timeout，
#    agent 反而比沒裝 VoidNotch 還慢（正是「彈了卡片卻更久」的成因）。
OFFLINE_EVENTS="$TMP/offline-events.jsonl"
OFFLINE_OUT="$TMP/offline-out.json"
started=$(date +%s)
echo "$CODEX_PAYLOAD" | VOIDNOTCH_AGENT_EVENTS="$OFFLINE_EVENTS" VOIDNOTCH_RESPONSE_DIR="$RESPONSES" \
  VOIDNOTCH_SUPPORT_DIR="$SUPPORT" VOIDNOTCH_ASSUME_RUNNING=0 \
  VOIDNOTCH_INPUT_BROKER_TIMEOUT=30 bash "$RELAY" --provider codex > "$OFFLINE_OUT"
elapsed=$(( $(date +%s) - started ))
if [ -s "$OFFLINE_OUT" ]; then
    echo "FAIL: App 沒在跑時 relay 仍輸出 decision（應完全不接管）"
    fail=1
fi
if [ "$elapsed" -ge 10 ]; then
    echo "FAIL: App 沒在跑時 relay 仍空等（${elapsed}s）"
    fail=1
fi
# 但活動事件仍要照常記錄，瀏海才看得到 codex 在動
if ! grep -q '"status":"needsInput"' "$OFFLINE_EVENTS"; then
    echo "FAIL: App 沒在跑時活動事件應照常寫入"
    fail=1
fi
if grep -q '"input_request"' "$OFFLINE_EVENTS"; then
    echo "FAIL: App 沒在跑時不應發出 input_request"
    fail=1
fi

# 9) 舊版 App（沒有 broker-capabilities.json）：只認得 claude 的問答卡。
#    此時對 codex 接管的話，舊版既不顯示選項也不會寫 dismissal，agent 會空等到 timeout。
#    必須保守退回 claude-only，最壞情況等同沒裝 VoidNotch。
LEGACY_SUPPORT="$TMP/legacy-support"   # 刻意不建 broker-capabilities.json
mkdir -p "$LEGACY_SUPPORT"
LEGACY_EVENTS="$TMP/legacy-events.jsonl"
LEGACY_OUT="$TMP/legacy-out.json"
started=$(date +%s)
echo "$CODEX_PAYLOAD" | VOIDNOTCH_AGENT_EVENTS="$LEGACY_EVENTS" VOIDNOTCH_RESPONSE_DIR="$RESPONSES" \
  VOIDNOTCH_SUPPORT_DIR="$LEGACY_SUPPORT" VOIDNOTCH_ASSUME_RUNNING=1 \
  VOIDNOTCH_INPUT_BROKER_TIMEOUT=30 bash "$RELAY" --provider codex > "$LEGACY_OUT"
elapsed=$(( $(date +%s) - started ))
if [ "$elapsed" -ge 10 ]; then
    echo "FAIL: 舊版 App 下 codex 仍被接管並空等（${elapsed}s）"
    fail=1
fi
if grep -q '"input_request"' "$LEGACY_EVENTS"; then
    echo "FAIL: 舊版 App 下不應對 codex 發出 input_request"
    fail=1
fi
# 2026-07-14 契約變更：這裡原本斷言「舊版 App 下 claude 仍要能作答」（fail-open 退回 claude-only）。
# 該斷言已退休，因為它現在是授權漏洞：使用者只要刪掉 broker-capabilities.json，
# 就能讓未授權的 App 白嫖 claude 代答。
# 新契約＝fail-closed：capabilities 讀不到／損壞 → 一律不接管（含 claude）。
# 安全性質不變且更強：不接管 → agent 照常在終端機提問 → 最壞情況等同沒裝 VoidNotch，永不空等。
# 這不會砸掉既有功能，因為 Agent 層從未公開發布過，不存在「舊版 App + 新 relay」的真實使用者。
LEGACY_CLAUDE_EVENTS="$TMP/legacy-claude.jsonl"
LEGACY_CLAUDE_OUT="$TMP/legacy-claude-out.json"
started=$(date +%s)
echo "$PAYLOAD" | VOIDNOTCH_AGENT_EVENTS="$LEGACY_CLAUDE_EVENTS" VOIDNOTCH_RESPONSE_DIR="$RESPONSES" \
  VOIDNOTCH_SUPPORT_DIR="$LEGACY_SUPPORT" VOIDNOTCH_ASSUME_RUNNING=1 \
  VOIDNOTCH_INPUT_BROKER_TIMEOUT=30 bash "$RELAY" --provider claude > "$LEGACY_CLAUDE_OUT"
elapsed=$(( $(date +%s) - started ))
if [ "$elapsed" -ge 10 ]; then
    echo "FAIL: capabilities 缺失時 claude 仍被接管並空等（${elapsed}s）"
    fail=1
fi
if grep -q '"input_request"' "$LEGACY_CLAUDE_EVENTS"; then
    echo "FAIL: capabilities 缺失時不應對 claude 發出 input_request（fail-closed）"
    fail=1
fi
if [ -s "$LEGACY_CLAUDE_OUT" ]; then
    echo "FAIL: capabilities 缺失時 claude 不應有 stdout 輸出（應完全不接管）"
    fail=1
fi

# --- hermes 活動通知 --------------------------------------------------------
# hermes（NousResearch/hermes-agent）的 shell hooks 事件名自成一套；沒有對照表就會
# 在 status=None 處被靜默丟掉——掛了 hook 卻什麼都不顯示。
H_EVENTS="$TMP/hermes-events.jsonl"
hermes_status_for() {
    echo "{\"hook_event_name\":\"$1\",\"session_id\":\"s1\",\"cwd\":\"/tmp/p\"}" | \
      VOIDNOTCH_AGENT_EVENTS="$H_EVENTS" VOIDNOTCH_SUPPORT_DIR="$SUPPORT" \
      VOIDNOTCH_ASSUME_RUNNING=1 bash "$RELAY" --provider hermes >/dev/null 2>&1
    /usr/bin/python3 -c 'import json,sys;d=json.loads(open(sys.argv[1]).read().splitlines()[-1]);print(d["provider"],d["status"])' "$H_EVENTS"
}
for pair in "on_session_start:started" "pre_llm_call:running" \
            "pre_approval_request:needsInput" "api_request_error:failed" \
            "on_session_end:completed"; do
    ev="${pair%%:*}"; want="${pair##*:}"
    got="$(hermes_status_for "$ev")"
    if [ "$got" != "hermes $want" ]; then
        echo "FAIL: hermes $ev 應為「hermes $want」，實得「$got」"
        fail=1
    fi
done

# hermes 的協定只認 block/context，回不了答案。即使 pre_approval_request 是
# needsInput，也絕不能接管——接管就是把 hermes 卡死到 broker timeout。
if grep -q '"input_request"' "$H_EVENTS"; then
    echo "FAIL: hermes 不可被 broker 接管（協定無法回填答案）"
    fail=1
fi

# --- capabilities fail-closed（生產端授權）---------------------------------
# 讀不到／損壞／空清單 → 完全不接管 codex PermissionRequest；
# 合法且含 codex → 仍接管。stdout 空且無 input_request 即為不接管。
assert_codex_not_taken_over() {
    local label="$1" support_dir="$2"
    local ev="$TMP/cap-$label.jsonl"
    local out="$TMP/cap-$label-out.json"
    : > "$ev"
    : > "$out"
    local started
    started=$(date +%s)
    echo "$CODEX_PAYLOAD" | VOIDNOTCH_AGENT_EVENTS="$ev" VOIDNOTCH_RESPONSE_DIR="$RESPONSES" \
      VOIDNOTCH_SUPPORT_DIR="$support_dir" VOIDNOTCH_ASSUME_RUNNING=1 \
      VOIDNOTCH_INPUT_BROKER_TIMEOUT=30 bash "$RELAY" --provider codex > "$out"
    local elapsed=$(( $(date +%s) - started ))
    if [ -s "$out" ]; then
        echo "FAIL: capabilities($label) 時 codex 仍有 stdout 輸出（應完全不接管）"
        fail=1
    fi
    if grep -q '"input_request"' "$ev"; then
        echo "FAIL: capabilities($label) 時不應發出 input_request"
        fail=1
    fi
    if [ "$elapsed" -ge 10 ]; then
        echo "FAIL: capabilities($label) 時仍空等（${elapsed}s）"
        fail=1
    fi
}

# 10) capabilities 檔不存在 → codex 不被接管
CAP_MISSING="$TMP/cap-missing-support"
mkdir -p "$CAP_MISSING"
assert_codex_not_taken_over missing "$CAP_MISSING"

# 11) capabilities 檔內容損壞（非 JSON）→ 不接管
CAP_BAD="$TMP/cap-bad-support"
mkdir -p "$CAP_BAD"
printf '%s' 'not-json{{{' > "$CAP_BAD/broker-capabilities.json"
assert_codex_not_taken_over corrupt "$CAP_BAD"

# 12) answerable_providers 為空清單 → 不接管
CAP_EMPTY="$TMP/cap-empty-support"
mkdir -p "$CAP_EMPTY"
printf '%s' '{"answerable_providers":[]}' > "$CAP_EMPTY/broker-capabilities.json"
assert_codex_not_taken_over empty "$CAP_EMPTY"

# 13) answerable_providers 含 codex → 接管（維持既有能力）
CAP_CODEX="$TMP/cap-codex-support"
mkdir -p "$CAP_CODEX"
printf '%s' '{"answerable_providers":["codex"]}' > "$CAP_CODEX/broker-capabilities.json"
CAP_CODEX_EV="$TMP/cap-codex-only.jsonl"
CAP_CODEX_OUT="$TMP/cap-codex-only-out.json"
echo "$CODEX_PAYLOAD" | VOIDNOTCH_AGENT_EVENTS="$CAP_CODEX_EV" VOIDNOTCH_RESPONSE_DIR="$RESPONSES" \
  VOIDNOTCH_SUPPORT_DIR="$CAP_CODEX" VOIDNOTCH_ASSUME_RUNNING=1 \
  VOIDNOTCH_INPUT_BROKER_TIMEOUT=10 bash "$RELAY" --provider codex > "$CAP_CODEX_OUT" &
cap_codex_pid=$!
rid=""
for _ in $(seq 1 50); do
    if [ -s "$CAP_CODEX_EV" ]; then
        rid="$(/usr/bin/python3 -c 'import json,sys;print(json.loads(open(sys.argv[1]).read().splitlines()[-1]).get("input_request",{}).get("request_id",""))' "$CAP_CODEX_EV")"
        [ -n "$rid" ] && break
    fi
    sleep 0.1
done
if [ -z "$rid" ]; then
    echo "FAIL: capabilities 含 codex 時應接管並寫出 input_request"
    fail=1
    kill "$cap_codex_pid" 2>/dev/null
else
    q="$(/usr/bin/python3 -c 'import json,sys;print(json.loads(open(sys.argv[1]).read().splitlines()[-1])["input_request"]["questions"][0]["question"])' "$CAP_CODEX_EV")"
    upper_rid="$(printf '%s' "$rid" | tr '[:lower:]' '[:upper:]')"
    /usr/bin/python3 -c 'import json,sys;json.dump({"request_id":sys.argv[1],"answers":{sys.argv[3]:sys.argv[4]}},open(sys.argv[2],"w"))' \
        "$upper_rid" "$RESPONSES/$upper_rid.json" "$q" "允許"
    wait "$cap_codex_pid"
    if ! /usr/bin/python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
h=d["hookSpecificOutput"]
assert h["hookEventName"]=="PermissionRequest", h
assert h["decision"]=={"behavior":"allow"}, h["decision"]
' "$CAP_CODEX_OUT" 2>/dev/null; then
        echo "FAIL: capabilities 含 codex 時接管後輸出不符契約"
        fail=1
    fi
fi

# --- navigation metadata ----------------------------------------------------
# 契約：每筆記錄可帶 navigation（source_surface / session_id / tmux_*）。
# source_surface enum 必須與 parser 完全一致。tmux 只查固定絕對路徑，PATH 注入無效。

assert_nav_json() {
    local file="$1"
    shift
    /usr/bin/python3 -c '
import json,sys
path=sys.argv[1]
checks=sys.argv[2:]
d=json.loads(open(path).read().splitlines()[-1])
nav=d.get("navigation")
assert isinstance(nav, dict), "missing navigation: %r" % (nav,)
i=0
while i < len(checks):
    key=checks[i]; op=checks[i+1]; i+=2
    got=nav.get(key)
    if op == "eq":
        want=checks[i]; i+=1
        assert got == want, "%s: want %r got %r (nav=%r)" % (key, want, got, nav)
    elif op == "absent":
        assert key not in nav, "%s should be absent, got %r" % (key, got)
    elif op == "present":
        assert got, "%s should be present, got %r" % (key, got)
    else:
        raise SystemExit("unknown op %r" % op)
' "$file" "$@"
}

# 隔離 terminal/tmux 推斷用的環境（可重現）
run_relay_nav() {
    local events_file="$1" provider="$2" payload="$3"
    shift 3
    # 其餘參數為 VAR=value 形式的額外環境
    env -u TMUX -u TMUX_PANE -u TERM_PROGRAM -u __CFBundleIdentifier -u VOIDNOTCH_SOURCE_SURFACE \
      "$@" \
      /usr/bin/env bash -c '
        printf "%s\n" "$2" | VOIDNOTCH_AGENT_EVENTS="$0" bash "$1" --provider "$3" >/dev/null
      ' "$events_file" "$RELAY" "$payload" "$provider"
}

# 14) 非 tmux 傳統事件：仍寫出事件；navigation 有 source_surface，無 tmux 欄位
NAV_LEGACY="$TMP/nav-legacy.jsonl"
run_relay_nav "$NAV_LEGACY" claude \
  '{"hook_event_name":"SessionStart","workspace":"VoidNotch"}'
if ! assert_nav_json "$NAV_LEGACY" \
    source_surface eq unknown \
    session_id absent \
    tmux_socket absent \
    tmux_pane absent \
    tmux_window absent \
    tmux_session absent \
    tmux_client_tty absent 2>/dev/null; then
    echo "FAIL: 非 tmux legacy 事件的 navigation 不符契約"
    fail=1
fi
if ! grep -q '"provider":"claude"' "$NAV_LEGACY" || ! grep -q '"status":"started"' "$NAV_LEGACY"; then
    echo "FAIL: 非 tmux legacy 事件本體未正確寫入"
    fail=1
fi

# 15) 明確 ghostty surface + session_id（payload 既有欄位）
NAV_GHOSTTY="$TMP/nav-ghostty.jsonl"
run_relay_nav "$NAV_GHOSTTY" claude \
  '{"hook_event_name":"UserPromptSubmit","session_id":"sess-ghostty-1"}' \
  VOIDNOTCH_SOURCE_SURFACE=ghostty
if ! assert_nav_json "$NAV_GHOSTTY" \
    source_surface eq ghostty \
    session_id eq sess-ghostty-1 2>/dev/null; then
    echo "FAIL: ghostty surface / session_id 未正確寫入 navigation"
    fail=1
fi

# 16) 非法 VOIDNOTCH_SOURCE_SURFACE → 忽略覆寫，推斷為 unknown（無其他標記時）
NAV_BAD_SURFACE="$TMP/nav-bad-surface.jsonl"
run_relay_nav "$NAV_BAD_SURFACE" codex \
  '{"hook_event_name":"Stop"}' \
  VOIDNOTCH_SOURCE_SURFACE=not-a-real-surface
if ! assert_nav_json "$NAV_BAD_SURFACE" source_surface eq unknown 2>/dev/null; then
    echo "FAIL: 非法 source_surface 覆寫應回落 unknown"
    fail=1
fi

# 17) PATH 上的假 tmux 不可被注入；只認固定絕對路徑候選
NAV_FAKE_TMUX="$TMP/nav-fake-tmux.jsonl"
FAKE_BIN="$TMP/fakebin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/tmux" <<'FAKE_TMUX'
#!/bin/bash
# 若 relay 誤走 PATH，會寫出可偵測的毒 payload
echo "evil_session	@999	%999"
exit 0
FAKE_TMUX
chmod +x "$FAKE_BIN/tmux"
# 給一個不存在的 socket，讓真實固定路徑 tmux（若存在）查詢失敗並降級
env -u TERM_PROGRAM -u __CFBundleIdentifier -u VOIDNOTCH_SOURCE_SURFACE \
  PATH="$FAKE_BIN:/usr/bin:/bin" \
  TMUX="/private/tmp/voidnotch-relay-test-no-such-socket,0,0" \
  TMUX_PANE="%0" \
  /usr/bin/env bash -c '
    printf "%s\n" "$2" | VOIDNOTCH_AGENT_EVENTS="$0" bash "$1" --provider claude >/dev/null
  ' "$NAV_FAKE_TMUX" "$RELAY" '{"hook_event_name":"SessionStart","session_id":"s-tmux"}'
if ! /usr/bin/python3 -c '
import json,sys
d=json.loads(open(sys.argv[1]).read().splitlines()[-1])
nav=d.get("navigation") or {}
assert nav.get("source_surface") == "unknown", nav
assert nav.get("session_id") == "s-tmux", nav
assert nav.get("tmux_socket") == "/private/tmp/voidnotch-relay-test-no-such-socket", nav
assert nav.get("tmux_pane") == "%0", nav
# 假 tmux 的毒輸出不得進 navigation
assert nav.get("tmux_session") != "evil_session", nav
assert nav.get("tmux_window") != "@999", nav
assert nav.get("tmux_pane") != "%999", nav
# 不可因 tmux 查詢失敗而丟掉事件
assert d.get("status") == "started", d
' "$NAV_FAKE_TMUX" 2>/dev/null; then
    echo "FAIL: 假 tmux PATH 注入未被正確忽略／降級"
    fail=1
fi

[ "$fail" -eq 0 ] && echo "relay_test: ALL PASS"
# 禁 rm：暫存搬到 /private/tmp/tvw 留時間線
mkdir -p /private/tmp/tvw
mv "$TMP" "/private/tmp/tvw/_DELETE_voidnotch_relay_test_$$"
exit $fail
