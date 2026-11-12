#!/bin/bash
# Beatpilot adapter for Claude Code (shell hooks; used by ./install.sh).
# The plugin install uses the in-process mod in hooks/ instead.
# Receives hook JSON on stdin, maps events to energy, calls write-state.sh.

ADAPTER_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/paths.sh
. "$ADAPTER_DIR/../lib/paths.sh" || { cat >/dev/null; exit 0; }

[ -f "$BP_DISABLED" ] && cat > /dev/null && exit 0

if ! command -v jq &>/dev/null; then
    cat > /dev/null
    echo '{"systemMessage":"Beatpilot: jq is not installed. Install it with: brew install jq (macOS) or sudo apt install jq (Linux)."}'
    exit 0
fi

input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)
[ -z "$event" ] && exit 0

current_energy() {
    local e=2
    [ -f "$BP_STATE" ] && read -r e < "$BP_STATE"
    case "$e" in ''|*[!0-9]*) e=2 ;; esac
    echo "$e"
}

case "$event" in
    UserPromptSubmit)
        # A new task: new tune. Content goes over stdin, not argv.
        printf '%s' "$input" | jq -r '.prompt // "prompt"' | "${ADAPTER_DIR}/write-state.sh" 2 -
        ;;
    PreToolUse)
        tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
        case "$tool" in
            Agent|Task) "${ADAPTER_DIR}/write-state.sh" 3 --keep ;;
            *)          "${ADAPTER_DIR}/write-state.sh" 2 --keep ;;
        esac
        ;;
    PostToolUse)
        "${ADAPTER_DIR}/write-state.sh" "$(current_energy)" --keep
        ;;
    PostToolUseFailure)
        # Failures are routine for an agent: tension (one level down), not silence.
        e=$(current_energy)
        [ "$e" -gt 1 ] && e=$(( e - 1 ))
        "${ADAPTER_DIR}/write-state.sh" "$e" --keep
        ;;
    Stop)
        "${ADAPTER_DIR}/write-state.sh" 1 --keep
        ;;
    SubagentStart)
        "${ADAPTER_DIR}/write-state.sh" 3 --keep
        ;;
esac
exit 0
