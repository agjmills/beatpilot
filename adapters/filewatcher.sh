#!/bin/bash
# Beatpilot file watcher adapter — works with ANY coding tool
# Monitors a directory for file changes and maps activity to musical state.
# Works with Copilot, Cursor, Codex, Aider, manual editing, or anything else.
#
# Usage:
#   adapters/filewatcher.sh [directory]   Start watching (default: current dir)
#   adapters/filewatcher.sh --stop        Stop the watcher
#
# Uses fswatch if available, falls back to polling with find.

ADAPTER_DIR="$(cd "$(dirname "$0")" && pwd)"
WATCHER_PID="/tmp/beatpilot-watcher.pid"
POLL_INTERVAL=3       # seconds between polls (fallback mode)
MARKER="/tmp/beatpilot-watcher-mark"
EVENT_LOG="/tmp/beatpilot-watcher-events"

# --- Stop mode ---
if [ "$1" = "--stop" ] || [ "$1" = "stop" ]; then
    if [ -f "$WATCHER_PID" ] && kill -0 "$(cat "$WATCHER_PID")" 2>/dev/null; then
        kill "$(cat "$WATCHER_PID")" 2>/dev/null
        rm -f "$WATCHER_PID" "$MARKER" "$EVENT_LOG"
        echo "Beatpilot watcher stopped"
    else
        rm -f "$WATCHER_PID" "$MARKER" "$EVENT_LOG"
        echo "Beatpilot watcher not running"
    fi
    exit 0
fi

# --- Already running? ---
if [ -f "$WATCHER_PID" ] && kill -0 "$(cat "$WATCHER_PID")" 2>/dev/null; then
    echo "Beatpilot watcher already running (PID $(cat "$WATCHER_PID"))"
    exit 0
fi

WATCH_DIR="${1:-.}"
WATCH_DIR="$(cd "$WATCH_DIR" 2>/dev/null && pwd)" || { echo "Invalid directory: $1" >&2; exit 1; }

# --- Energy from recent event count ---
# Counts events in the log that are less than 10 seconds old
calc_energy() {
    local now
    now=$(date +%s)
    local count=0
    if [ -f "$EVENT_LOG" ]; then
        while IFS= read -r ts; do
            if [ $(( now - ts )) -lt 10 ] 2>/dev/null; then
                count=$(( count + 1 ))
            fi
        done < "$EVENT_LOG"
    fi
    if [ "$count" -le 1 ]; then
        echo 1
    elif [ "$count" -le 4 ]; then
        echo 2
    else
        echo 3
    fi
}

# --- Process a file change ---
process_change() {
    local file="$1"
    date +%s >> "$EVENT_LOG"
    # Trim event log to last 20 lines
    if [ -f "$EVENT_LOG" ]; then
        tail -20 "$EVENT_LOG" > "${EVENT_LOG}.tmp" && mv -f "${EVENT_LOG}.tmp" "$EVENT_LOG"
    fi
    local energy
    energy=$(calc_energy)
    "${ADAPTER_DIR}/write-state.sh" "$energy" "$file" 2>/dev/null
}

# --- Cleanup on exit ---
cleanup() {
    rm -f "$WATCHER_PID" "$MARKER" "$EVENT_LOG"
    exit 0
}

# --- Launch watcher in background ---
touch "$MARKER"
: > "$EVENT_LOG"

if command -v fswatch &>/dev/null; then
    # --- fswatch mode (efficient, event-driven) ---
    (
        trap cleanup SIGTERM SIGINT
        fswatch -r -l 1 \
            --exclude '.git' \
            --exclude 'node_modules' \
            --exclude '__pycache__' \
            --exclude '\.pyc$' \
            --exclude '\.swp$' \
            --exclude '\.DS_Store' \
            "$WATCH_DIR" | while IFS= read -r changed_file; do
            process_change "$changed_file"
        done
    ) &
else
    # --- Polling fallback (no extra dependencies) ---
    (
        trap cleanup SIGTERM SIGINT
        while true; do
            changed=$(find "$WATCH_DIR" \
                -newer "$MARKER" \
                -type f \
                -not -path '*/.git/*' \
                -not -path '*/node_modules/*' \
                -not -path '*/__pycache__/*' \
                -not -path '*/.next/*' \
                -not -path '*/.cache/*' \
                -not -name '*.pyc' \
                -not -name '*.swp' \
                -not -name '.DS_Store' \
                2>/dev/null | head -20)

            if [ -n "$changed" ]; then
                while IFS= read -r f; do
                    process_change "$f"
                done <<< "$changed"
                touch "$MARKER"
            fi

            sleep "$POLL_INTERVAL"
        done
    ) &
fi

# Capture PID from parent (works on all bash versions)
echo $! > "$WATCHER_PID"
disown

echo "Beatpilot watcher started on ${WATCH_DIR} (PID $!)"
echo "Stop with: $0 --stop"
