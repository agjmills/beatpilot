#!/bin/bash
# Beatpilot adapter for GitHub Copilot CLI
# Receives hook JSON on stdin, maps events to energy + content, calls write-state.sh
#
# Setup: Add to ~/.copilot/config.json (or .github/hooks/ in your repo):
#
#   {
#     "hooks": {
#       "userPromptSubmitted": [{
#         "type": "command",
#         "bash": "/path/to/beatpilot/adapters/copilot-cli.sh"
#       }],
#       "preToolUse": [{
#         "type": "command",
#         "bash": "/path/to/beatpilot/adapters/copilot-cli.sh"
#       }],
#       "postToolUse": [{
#         "type": "command",
#         "bash": "/path/to/beatpilot/adapters/copilot-cli.sh"
#       }],
#       "errorOccurred": [{
#         "type": "command",
#         "bash": "/path/to/beatpilot/adapters/copilot-cli.sh"
#       }],
#       "sessionStart": [{
#         "type": "command",
#         "bash": "/path/to/beatpilot/adapters/copilot-cli.sh"
#       }],
#       "sessionEnd": [{
#         "type": "command",
#         "bash": "/path/to/beatpilot/adapters/copilot-cli.sh"
#       }]
#     }
#   }

ADAPTER_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/paths.sh
. "$ADAPTER_DIR/../lib/paths.sh" || { cat >/dev/null; exit 0; }

[ -f "$BP_DISABLED" ] && cat > /dev/null && exit 0

# --- Dependency check (jq required for JSON parsing) ---
if ! command -v jq &>/dev/null; then
    cat > /dev/null
    exit 0
fi

# --- Read JSON from stdin ---
input=$(cat)

# --- Detect event type ---
# Copilot CLI hooks receive JSON with toolName, toolArgs, timestamp, cwd, etc.
# The event type is inferred from which hook fired (not in the JSON itself),
# so we detect based on which fields are present.
tool_name=$(echo "$input" | jq -r '.toolName // empty' 2>/dev/null)
error=$(echo "$input" | jq -r '.error // empty' 2>/dev/null)
prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null)
session_event=$(echo "$input" | jq -r '.sessionEvent // empty' 2>/dev/null)

current_energy() {
    local e=2
    [ -f "$BP_STATE" ] && read -r e < "$BP_STATE"
    case "$e" in ''|*[!0-9]*) e=2 ;; esac
    echo "$e"
}

if [ -n "$error" ]; then
    # errorOccurred: tension (one level down), not silence
    e=$(current_energy)
    [ "$e" -gt 1 ] && e=$(( e - 1 ))
    "${ADAPTER_DIR}/write-state.sh" "$e" --keep
elif [ -n "$prompt" ]; then
    # userPromptSubmitted: a new task gets a new tune (content over stdin)
    printf '%s' "$prompt" | "${ADAPTER_DIR}/write-state.sh" 2 -
elif [ -n "$tool_name" ]; then
    # preToolUse / postToolUse: energy only, keep the tune developing
    case "$tool_name" in
        *agent*|*Agent*|*spawn*) "${ADAPTER_DIR}/write-state.sh" 3 --keep ;;
        *)                                  "${ADAPTER_DIR}/write-state.sh" 2 --keep ;;
    esac
elif [ -n "$session_event" ]; then
    "${ADAPTER_DIR}/write-state.sh" 1 --keep
else
    "${ADAPTER_DIR}/write-state.sh" 1 --keep
fi
exit 0
