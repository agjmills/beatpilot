#!/bin/bash
# Beatpilot Hook - writes state for the engine to read
# Receives hook JSON on stdin from Claude Code hooks.

SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
PID_FILE="/tmp/beatpilot.pid"
STATE_FILE="/tmp/beatpilot-state"

# --- Check if disabled ---
[ -f /tmp/beatpilot-disabled ] && cat > /dev/null && exit 0

# --- Read JSON from stdin ---
input=$(cat)

# --- Ensure engine is running ---
if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    "${SCRIPT_DIR}/start.sh" >/dev/null 2>&1
    sleep 0.3
fi

# --- Parse event type ---
event=$(echo "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)
[ -z "$event" ] && exit 0

# --- Determine energy level and content to hash ---
energy=1
content=""

case "$event" in
    UserPromptSubmit)
        energy=2
        content=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null)
        ;;
    PreToolUse)
        tool=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null)
        content="${tool}:$(echo "$input" | jq -r '.tool_input | tostring' 2>/dev/null)"
        case "$tool" in
            Agent)  energy=3 ;;
            Bash)   energy=2 ;;
            *)      energy=2 ;;
        esac
        ;;
    PostToolUse)
        energy=2
        content=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null)
        ;;
    PostToolUseFailure)
        energy=0
        content=$(echo "$input" | jq -r '.error // empty' 2>/dev/null)
        ;;
    Stop)
        energy=1
        content="stop"
        ;;
    SubagentStart)
        energy=3
        content=$(echo "$input" | jq -r '.agent_type // empty' 2>/dev/null)
        ;;
    *)
        exit 0
        ;;
esac

[ -z "$content" ] && content="$event"

# --- Hash content for musical variation ---
hash_hex=$(echo -n "$content" | md5 -q 2>/dev/null || echo -n "$content" | md5sum 2>/dev/null | cut -c1-8)
hash_hex=$(echo "$hash_hex" | tr -d ' -' | cut -c1-8)
hash_int=$(printf '%d' "0x${hash_hex}" 2>/dev/null || echo 0)

key=$(( hash_int % 12 ))
scale_type=$(( (hash_int / 12) % 4 ))
seed=$(( (hash_int / 48) % 256 ))
ts=$(date +%s)

# --- Write state atomically ---
tmp="${STATE_FILE}.$$"
printf '%d\n%d\n%d\n%d\n%d\n' "$energy" "$key" "$scale_type" "$seed" "$ts" > "$tmp"
mv -f "$tmp" "$STATE_FILE"

exit 0
