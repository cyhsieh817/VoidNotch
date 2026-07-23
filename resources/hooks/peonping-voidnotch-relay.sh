#!/bin/bash
#
# peonping-voidnotch-relay.sh
#
# Reads an AI-agent hook payload from stdin, normalizes the event, and appends
# one JSONL record for VoidNotch to display in the Agent Activity widget.
#
# Usage:
#   bash resources/hooks/peonping-voidnotch-relay.sh --provider claude
#   bash resources/hooks/peonping-voidnotch-relay.sh --provider codex
#   bash resources/hooks/peonping-voidnotch-relay.sh --provider agy
#
# Optional:
#   VOIDNOTCH_AGENT_EVENTS=/path/to/agent-events.jsonl

set -uo pipefail

PROVIDER="${VOIDNOTCH_AGENT_PROVIDER:-claude}"
EVENT_FILE="${VOIDNOTCH_AGENT_EVENTS:-$HOME/Library/Application Support/VoidNotch/agent-events.jsonl}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --provider=*)
            PROVIDER="${1#--provider=}"
            shift
            ;;
        --provider)
            if [ "$#" -ge 2 ]; then
                PROVIDER="$2"
                shift 2
            else
                exit 0
            fi
            ;;
        --event-file=*)
            EVENT_FILE="${1#--event-file=}"
            shift
            ;;
        --event-file)
            if [ "$#" -ge 2 ]; then
                EVENT_FILE="$2"
                shift 2
            else
                exit 0
            fi
            ;;
        *)
            shift
            ;;
    esac
done

export VOIDNOTCH_RELAY_PROVIDER="$PROVIDER"
export VOIDNOTCH_RELAY_EVENT_FILE="$EVENT_FILE"
VOIDNOTCH_RELAY_PAYLOAD="$(cat)"
export VOIDNOTCH_RELAY_PAYLOAD

/usr/bin/python3 - "$PWD" <<'PY'
import json
import os
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone

cwd = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
provider_raw = os.environ.get("VOIDNOTCH_RELAY_PROVIDER", "claude")
event_file = os.path.expanduser(os.environ.get("VOIDNOTCH_RELAY_EVENT_FILE", ""))
raw = os.environ.get("VOIDNOTCH_RELAY_PAYLOAD", "")


def canonical_provider(value):
    value = (value or "").lower()
    if "codex" in value:
        return "codex"
    if "grok" in value:
        return "grok"
    if "claude" in value:
        return "claude"
    if "hermes" in value:
        return "hermes"
    if "gemini" in value or "agy" in value or "antigravity" in value:
        return "antigravity"
    return None


def hook_category(hook):
    key = (hook or "").replace("_", "").replace("-", "").replace(".", "").lower()
    return {
        "sessionstart": "session.start",
        "userpromptsubmit": "task.running",
        "subagentstart": "task.running",
        "stop": "task.complete",
        "notification": "input.required",
        "permissionrequest": "input.required",
        "posttoolusefailure": "task.error",
        "precompact": "resource.limit",
        "sessionend": "session.end",
        "pretooluse": "input.required",
        # hermes（NousResearch/hermes-agent）的 shell hooks 事件名自成一套。
        # 沒有這幾條對照，事件會在 status=None 處被靜默丟掉。
        "onsessionstart": "session.start",
        "prellmcall": "task.running",
        "preapprovalrequest": "input.required",
        "apirequesterror": "task.error",
        "onsessionend": "task.complete",
    }.get(key)


def normalize_status(value):
    key = (value or "").replace("_", "").replace("-", "").replace(".", "").replace(" ", "").lower()
    if key in ("sessionstart", "started", "start"):
        return "started"
    if key in ("userpromptsubmit", "subagentstart", "taskrunning", "running"):
        return "running"
    if key in ("stop", "taskcomplete", "completed", "complete"):
        return "completed"
    if key in ("notification", "permissionrequest", "inputrequired", "needsinput"):
        return "needsInput"
    if key in ("posttoolusefailure", "taskerror", "failed", "failure", "error"):
        return "failed"
    if key in ("precompact", "resourcelimit", "contextlimit", "tokenlimit"):
        return "resourceLimit"
    if key in ("sessionend", "stopped", "shutdown"):
        return "stopped"
    return None


def string_value(payload, *keys):
    for key in keys:
        value = payload.get(key)
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return None


# source_surface 必須與 App 端 parser 契約完全一致；禁輸出任意 bundle id / deep link。
ALLOWED_SOURCE_SURFACES = frozenset({
    "ghostty",
    "apple_terminal",
    "iterm",
    "claude_desktop",
    "codex_app",
    "unknown",
})

# 終端機：只信任 TERM_PROGRAM 與已知 __CFBundleIdentifier。
TERM_PROGRAM_SURFACE = {
    "ghostty": "ghostty",
    "Apple_Terminal": "apple_terminal",
    "iTerm.app": "iterm",
}
CF_BUNDLE_TERMINAL_SURFACE = {
    "com.mitchellh.ghostty": "ghostty",
    "com.apple.Terminal": "apple_terminal",
    "com.googlecode.iterm2": "iterm",
}

# Desktop App：只認精確 client/runtime 標記與已知 bundle（非任意 bundle 映射）。
DESKTOP_BUNDLE_SURFACE = {
    "com.anthropic.claudefordesktop": "claude_desktop",
    "com.openai.codex": "codex_app",
}
CLIENT_RUNTIME_SURFACE = {
    "claude_desktop": "claude_desktop",
    "claude-desktop": "claude_desktop",
    "Claude Desktop": "claude_desktop",
    "codex_app": "codex_app",
    "codex-app": "codex_app",
    "Codex App": "codex_app",
}

TMUX_BIN_CANDIDATES = (
    "/opt/homebrew/bin/tmux",
    "/usr/local/bin/tmux",
)


def infer_source_surface(payload):
    """推斷來源表面。VOIDNOTCH_SOURCE_SURFACE 僅在允許 enum 時生效（測試覆寫）。"""
    override = (os.environ.get("VOIDNOTCH_SOURCE_SURFACE") or "").strip()
    if override in ALLOWED_SOURCE_SURFACES:
        return override

    for key in ("client", "runtime", "source_surface", "sourceSurface"):
        marker = string_value(payload, key)
        if marker and marker in CLIENT_RUNTIME_SURFACE:
            return CLIENT_RUNTIME_SURFACE[marker]

    term_program = (os.environ.get("TERM_PROGRAM") or "").strip()
    if term_program in TERM_PROGRAM_SURFACE:
        return TERM_PROGRAM_SURFACE[term_program]

    bundle = (os.environ.get("__CFBundleIdentifier") or "").strip()
    if bundle in DESKTOP_BUNDLE_SURFACE:
        return DESKTOP_BUNDLE_SURFACE[bundle]
    if bundle in CF_BUNDLE_TERMINAL_SURFACE:
        return CF_BUNDLE_TERMINAL_SURFACE[bundle]

    return "unknown"


def find_tmux_executable():
    """只使用固定絕對路徑候選；絕不走 PATH（防注入假 tmux）。"""
    for path in TMUX_BIN_CANDIDATES:
        try:
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        except Exception:
            continue
    return None


def collect_tmux_navigation():
    """從 TMUX / TMUX_PANE 與固定路徑 tmux 查詢收集 metadata；失敗只降級，不丟事件。"""
    nav = {}
    tmux_env = (os.environ.get("TMUX") or "").strip()
    pane_env = (os.environ.get("TMUX_PANE") or "").strip() or None

    socket = None
    if tmux_env:
        socket = tmux_env.split(",", 1)[0].strip() or None
    if socket:
        nav["tmux_socket"] = socket
    if pane_env:
        nav["tmux_pane"] = pane_env

    tmux_bin = find_tmux_executable()
    if not tmux_bin or not socket:
        return nav

    try:
        cmd = [tmux_bin, "-S", socket, "display-message", "-p"]
        if pane_env:
            cmd.extend(["-t", pane_env])
        cmd.append("#{session_name}\t#{window_id}\t#{pane_id}")
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2,
        )
        if proc.returncode == 0 and proc.stdout:
            parts = proc.stdout.strip().split("\t")
            if len(parts) >= 3:
                session_name, window_id, pane_id = parts[0].strip(), parts[1].strip(), parts[2].strip()
                if session_name:
                    nav["tmux_session"] = session_name
                if window_id:
                    nav["tmux_window"] = window_id
                if pane_id:
                    nav["tmux_pane"] = pane_id
    except Exception:
        pass

    session_name = nav.get("tmux_session")
    if not session_name:
        return nav

    try:
        proc = subprocess.run(
            [tmux_bin, "-S", socket, "list-clients", "-t", session_name, "-F", "#{client_tty}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2,
        )
        if proc.returncode == 0 and proc.stdout is not None:
            clients = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
            if len(clients) == 1:
                nav["tmux_client_tty"] = clients[0]
    except Exception:
        pass

    return nav


def build_navigation(payload):
    """組裝 navigation object；只含有值的欄位，永不輸出 deep link / 任意 bundle id。"""
    nav = {"source_surface": infer_source_surface(payload)}
    session_id = string_value(
        payload,
        "session_id",
        "sessionId",
        "thread_id",
        "threadId",
        "conversation_id",
    )
    if session_id:
        nav["session_id"] = session_id
    nav.update(collect_tmux_navigation())
    return nav


def answerable_providers():
    """App 啟動時宣告自己答得出哪些 provider（broker-capabilities.json）。

    fail-closed：檔案不存在、JSON 損壞、或 answerable_providers 不是 list 時，
    回空集合，完全不接管。agent 回終端機提問，最壞情況等同沒裝 VoidNotch。

    早期曾 fail-open 退回 {"claude"}，那是「新 relay + 舊 App」過渡期的兼容：
    舊 App 只答得出 claude。現在改成 fail-closed，是因為缺檔／損壞時若仍
    授權 claude，刪掉 capabilities 就能白嫖代答，變成授權漏洞。"""
    support = os.path.expanduser(
        os.environ.get("VOIDNOTCH_SUPPORT_DIR", "~/Library/Application Support/VoidNotch")
    )
    try:
        with open(os.path.join(support, "broker-capabilities.json"), "r", encoding="utf-8") as handle:
            declared = json.load(handle).get("answerable_providers")
        if isinstance(declared, list):
            return {str(item) for item in declared}
    except Exception:
        pass
    return set()


def notch_is_running():
    """VoidNotch 沒在跑就沒人會寫回應檔。少了這道判斷，broker 會空等到 timeout，
    agent 反而比沒裝 VoidNotch 還慢——這正是「彈了卡片卻更久」的成因之一。"""
    override = os.environ.get("VOIDNOTCH_ASSUME_RUNNING")
    if override in ("0", "1"):
        return override == "1"
    try:
        return subprocess.run(
            ["/usr/bin/pgrep", "-x", "VoidNotch"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
        ).returncode == 0
    except Exception:
        return False


payload = {}
if raw.strip():
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            payload = parsed
    except Exception:
        payload = {"message": raw.strip()}

if os.environ.get("GROK_WORKSPACE_ROOT"):
    provider = "grok"
else:
    provider = canonical_provider(
        string_value(payload, "provider", "agent", "client", "runtime", "tool", "source")
        or provider_raw
    )
if provider is None or not event_file:
    sys.exit(0)

hook = string_value(payload, "hook_event_name", "hookEventName", "event", "event_name", "eventName")
tool_name = string_value(payload, "tool_name", "toolName")
is_input_broker = provider == "claude" and hook == "PreToolUse" and tool_name == "AskUserQuestion"
# codex 的核准提示走 PermissionRequest。該 hook 跑在核准 UI「之前」，回 decision.behavior
# =allow/deny 就能取代終端機那個選單；不回 decision 則照常顯示原提示。
# 真相源：codex-rs/hooks/src/events/permission_request.rs（allow/deny 皆支援，
# 只有 updatedInput/updatedPermissions/interrupt 是 fail-closed）。
is_permission_broker = provider == "codex" and hook == "PermissionRequest"
# 只在「App 有在跑」且「這一版 App 答得出這個 provider」時才接管。
# 任一不成立就完全不接管，讓 agent 照常在終端機提問——最壞情況等同沒裝 VoidNotch，
# 而不是把使用者晾在一張答不了的卡片後面。
if is_input_broker or is_permission_broker:
    if not notch_is_running() or provider not in answerable_providers():
        is_input_broker = False
        is_permission_broker = False
category = string_value(payload, "category", "cesp") or hook_category(hook)
status = normalize_status(string_value(payload, "status") or category or hook)
if status is None:
    sys.exit(0)

workspace = (
    string_value(payload, "workspace", "workspace_name", "project", "repo")
    or os.path.basename(cwd.rstrip(os.sep))
)
title = string_value(payload, "title")
if not title:
    display = {"codex": "Codex", "claude": "Claude", "antigravity": "Gemini (Agy)",
               "grok": "Grok", "hermes": "Hermes", "pi": "pi"}[provider]
    title = {
        "started": f"{display} started",
        "running": f"{display} working",
        "needsInput": f"{display} needs input",
        "completed": f"{display} completed",
        "failed": f"{display} error",
        "resourceLimit": f"{display} resource limit",
        "stopped": f"{display} stopped",
    }[status]

detail = string_value(payload, "detail", "message", "body", "summary", "error", "tool_name")
if not detail:
    parts = [part for part in (hook, category) if part]
    detail = " · ".join(parts) if parts else None

record = {
    "id": str(uuid.uuid4()),
    "provider": provider,
    "status": status,
    "hook_event_name": hook,
    "category": category,
    "title": title,
    "detail": detail,
    "workspace": workspace,
    "cwd": cwd,
    "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "navigation": build_navigation(payload),
}

request_id = None
questions = None
if is_input_broker:
    tool_input = payload.get("tool_input")
    candidate = tool_input.get("questions") if isinstance(tool_input, dict) else None
    normalized = []
    if isinstance(candidate, list) and candidate:
        for question in candidate:
            if not isinstance(question, dict):
                normalized = []
                break
            text = question.get("question")
            header = question.get("header", "")
            options = question.get("options")
            if not isinstance(text, str) or not text or not isinstance(header, str) or not isinstance(options, list) or not options:
                normalized = []
                break
            clean_options = []
            for option in options:
                if not isinstance(option, dict) or not isinstance(option.get("label"), str) or not option.get("label") or not isinstance(option.get("description", ""), str):
                    clean_options = []
                    break
                clean_options.append({"label": option["label"], "description": option.get("description", "")})
            if len(clean_options) != len(options):
                normalized = []
                break
            normalized.append({"question": text, "header": header, "options": clean_options,
                               "multiSelect": bool(question.get("multiSelect", False))})
    if normalized:
        request_id = str(uuid.uuid4())
        questions = normalized
        record["id"] = request_id
        record["input_request"] = {"request_id": request_id, "questions": questions}
elif is_permission_broker:
    # codex 只給 allow/deny 兩個出口（「不再詢問」要 updatedPermissions，是 fail-closed 的，
    # 給不了），所以卡片就是兩個選項。
    target = tool_name or "動作"
    summary = string_value(payload, "detail", "message") or target
    questions = [{
        "question": f"允許 Codex 執行 {target}？",
        "header": "Codex 核准",
        "options": [
            {"label": "允許", "description": summary},
            {"label": "拒絕", "description": "退回 Codex，讓它改用別的做法"},
        ],
        "multiSelect": False,
    }]
    request_id = str(uuid.uuid4())
    record["id"] = request_id
    record["input_request"] = {"request_id": request_id, "questions": questions}

directory = os.path.dirname(event_file) or "."
os.makedirs(directory, exist_ok=True)
with open(event_file, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")

# 截尾：超過 5000 行保留最後 1000 行
try:
    with open(event_file, "r", encoding="utf-8") as handle:
        lines = handle.readlines()
    if len(lines) > 5000:
        with open(event_file, "w", encoding="utf-8") as handle:
            handle.writelines(lines[-1000:])
except Exception:
    pass

if request_id and questions:
    response_dir = os.path.expanduser(
        os.environ.get("VOIDNOTCH_RESPONSE_DIR", "~/Library/Application Support/VoidNotch/responses")
    )
    # App 端 Swift 的 UUID.uuidString 一律大寫，relay 的 uuid4() 一律小寫。
    # 兩端皆須大小寫無關地對得上，否則 broker 會空等到 timeout（回應等於沒送出）。
    response_files = [
        os.path.join(response_dir, request_id + ".json"),
        os.path.join(response_dir, request_id.upper() + ".json"),
    ]
    timeout = max(0.0, float(os.environ.get("VOIDNOTCH_INPUT_BROKER_TIMEOUT", "590")))
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            response = None
            for candidate in response_files:
                try:
                    with open(candidate, "r", encoding="utf-8") as handle:
                        response = json.load(handle)
                    break
                except FileNotFoundError:
                    continue
            matched = (
                isinstance(response, dict)
                and str(response.get("request_id", "")).lower() == request_id.lower()
            )
            # 使用者關掉卡片／卡片逾時：放棄接管，不輸出 updatedInput，
            # 讓 agent 立刻照原本的方式在終端機提問，而不是讓它空等到 timeout。
            if matched and response.get("dismissed") is True:
                break
            answers = response.get("answers") if matched else None
            allowed = {q["question"]: {o["label"] for o in q["options"]} for q in questions}
            question_rules = {q["question"]: bool(q.get("multiSelect", False)) for q in questions}
            if isinstance(answers, dict) and set(answers) == set(allowed):
                valid = True
                for question, answer in answers.items():
                    labels = [part.strip() for part in answer.split(",")] if isinstance(answer, str) else []
                    if (not labels or
                            any(label not in allowed[question] for label in labels) or
                            len(labels) != len(set(labels)) or
                            (not question_rules[question] and len(labels) != 1)):
                        valid = False
                        break
                if valid and is_permission_broker:
                    picked = list(answers.values())[0].strip()
                    decision = ({"behavior": "allow"} if picked == "允許"
                                else {"behavior": "deny", "message": "契約者於 VoidNotch 瀏海拒絕了這個動作。"})
                    output = {"hookSpecificOutput": {"hookEventName": "PermissionRequest",
                              "decision": decision}}
                    print(json.dumps(output, ensure_ascii=False, separators=(",", ":")))
                    break
                if valid:
                    updated_input = dict(payload.get("tool_input") or {})
                    updated_input["questions"] = questions
                    updated_input["answers"] = answers
                    output = {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                              "permissionDecision": "allow", "updatedInput": updated_input}}
                    print(json.dumps(output, ensure_ascii=False, separators=(",", ":")))
                    break
        except Exception:
            pass
        time.sleep(0.1)
PY
