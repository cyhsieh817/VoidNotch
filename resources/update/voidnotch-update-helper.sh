#!/bin/sh
set -eu

parent_pid="$1"
current_app="$2"
new_app="$3"
backup_dir="$4"
log_file="$5"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$log_file"
}

log "update helper started parent_pid=$parent_pid current_app=$current_app new_app=$new_app"

attempt=0
while kill -0 "$parent_pid" 2>/dev/null; do
    if [ "$attempt" -ge 60 ]; then
        log "timed out waiting for parent process"
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 1
done

log "parent process exited"
parent_dir=$(dirname "$current_app")
staged_new="$parent_dir/.VoidNotch-update-$$.app"
if ! /usr/bin/ditto "$new_app" "$staged_new" >> "$log_file" 2>&1; then
    log "same-volume candidate pre-staging failed; current app untouched"
    mv "$staged_new" "$backup_dir/" 2>/dev/null || true
    exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict "$staged_new" >> "$log_file" 2>&1; then
    log "final candidate codesign verification failed"
    mv "$staged_new" "$backup_dir/" 2>/dev/null || true
    exit 1
fi

local_backup="$parent_dir/.VoidNotch-backup-$$.app"
if ! mv "$current_app" "$local_backup"; then
    log "could not move current app to backup"
    exit 1
fi

if ! mv "$staged_new" "$current_app"; then
    log "could not move candidate app into place; rolling back"
    if mv "$local_backup" "$current_app"; then
        log "rollback completed"
    else
        log "rollback failed"
    fi
    exit 1
fi

xattr -dr com.apple.quarantine "$current_app" >> "$log_file" 2>&1 || true
log "candidate app installed"

open "$current_app" >> "$log_file" 2>&1
sleep 5
if pgrep -f "$current_app/Contents/MacOS/VoidNotch" >/dev/null 2>&1; then
    log "new app process detected; update succeeded"
    if mv "$local_backup" "$backup_dir/VoidNotch-backup.app"; then
        log "old app backup archived as VoidNotch-backup.app"
    else
        log "could not archive old app backup; leaving local backup"
    fi
    if [ -d "$new_app" ]; then
        mv "$new_app" "$backup_dir/" 2>/dev/null || true
    fi
    exit 0
fi

log "new app process not detected; rolling back"
failed_app="$backup_dir/failed-$(date +%s).app"
if mv "$current_app" "$failed_app" && mv "$local_backup" "$current_app"; then
    xattr -dr com.apple.quarantine "$current_app" >> "$log_file" 2>&1 || true
    open "$current_app" >> "$log_file" 2>&1
    log "rollback completed and old app reopened"
else
    log "rollback failed"
fi
exit 1
