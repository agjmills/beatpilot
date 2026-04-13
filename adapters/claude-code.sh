#!/bin/bash
# Beatpilot adapter for Claude Code
# Receives hook JSON on stdin, maps events to energy + content, calls write-state.sh
# Registered as a Claude Code hook via settings.json.

ADAPTER_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Check if disabled ---
[ -f /tmp/beatpilot-disabled ] && cat > /dev/null && exit 0

# --- Dependency check (jq required for JSON parsing) ---
if ! command -v jq &>/dev/null; then
    cat > /dev/null
    echo '{"systemMessage":"Beatpilot: jq is not installed. Install it with: brew install jq (macOS) or sudo apt install jq (Linux)."}'
    exit 0
fi

# --- Read JSON from stdin ---
input=$(cat)

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

# --- Delegate to shared state writer ---
"${ADAPTER_DIR}/write-state.sh" "$energy" "$content"
