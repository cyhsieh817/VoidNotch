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
import sys
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
    if "claude" in value:
        return "claude"
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


payload = {}
if raw.strip():
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            payload = parsed
    except Exception:
        payload = {"message": raw.strip()}

provider = canonical_provider(
    string_value(payload, "provider", "agent", "client", "runtime", "tool", "source")
    or provider_raw
)
if provider is None or not event_file:
    sys.exit(0)

hook = string_value(payload, "hook_event_name", "hookEventName", "event", "event_name", "eventName")
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
    display = {"codex": "Codex", "claude": "Claude", "antigravity": "Gemini (Agy)"}[provider]
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
}

directory = os.path.dirname(event_file) or "."
os.makedirs(directory, exist_ok=True)
with open(event_file, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
PY
