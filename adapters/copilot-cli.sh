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

# --- Check if disabled ---
[ -f /tmp/beatpilot-disabled ] && cat > /dev/null && exit 0

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
tool_args=$(echo "$input" | jq -r '.toolArgs // empty' 2>/dev/null)
error=$(echo "$input" | jq -r '.error // empty' 2>/dev/null)
prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null)
session_event=$(echo "$input" | jq -r '.sessionEvent // empty' 2>/dev/null)

energy=1
content=""

if [ -n "$error" ]; then
    # errorOccurred
    energy=0
    content="$error"
elif [ -n "$prompt" ]; then
    # userPromptSubmitted
    energy=2
    content="$prompt"
elif [ -n "$tool_name" ]; then
    # preToolUse or postToolUse
    content="${tool_name}:${tool_args}"
    case "$tool_name" in
        # High-energy tools
        *agent*|*Agent*|*spawn*|*subagent*)
            energy=3 ;;
        *bash*|*Bash*|*terminal*|*shell*|*exec*)
            energy=2 ;;
        *edit*|*Edit*|*write*|*Write*)
            energy=2 ;;
        *)
            energy=2 ;;
    esac
elif [ -n "$session_event" ]; then
    energy=1
    content="session"
else
    # Fallback: hash whatever we got
    content=$(echo "$input" | jq -r 'tostring' 2>/dev/null)
    energy=1
fi

[ -z "$content" ] && content="copilot-event"

# --- Delegate to shared state writer ---
"${ADAPTER_DIR}/write-state.sh" "$energy" "$content"
