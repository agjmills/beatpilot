#!/bin/bash
# Manual installer for Beatpilot
# Adds hooks to your global Claude settings (~/.claude/settings.json)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"

echo "Beatpilot Installer"
echo "======================"
echo ""

# Check prerequisites
if ! command -v chuck &>/dev/null; then
    echo "ERROR: ChucK is not installed."
    echo "  macOS:  brew install chuck"
    echo "  Linux:  sudo apt install chuck"
    echo "  Or:     https://chuck.cs.princeton.edu/release/"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is not installed."
    echo "  macOS:  brew install jq"
    echo "  Linux:  sudo apt install jq"
    exit 1
fi

echo "Prerequisites OK (chuck, jq found)"
echo ""

# Ensure settings file exists
mkdir -p "$HOME/.claude"
if [ ! -f "$SETTINGS" ]; then
    echo "{}" > "$SETTINGS"
fi

# Build the hooks JSON
HOOK_CMD="${SCRIPT_DIR}/hook.sh"
HOOKS_JSON=$(cat <<EOF
{
  "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "${HOOK_CMD}", "async": true}]}],
  "PreToolUse": [{"hooks": [{"type": "command", "command": "${HOOK_CMD}", "async": true}]}],
  "PostToolUse": [{"hooks": [{"type": "command", "command": "${HOOK_CMD}", "async": true}]}],
  "PostToolUseFailure": [{"hooks": [{"type": "command", "command": "${HOOK_CMD}", "async": true}]}],
  "Stop": [{"hooks": [{"type": "command", "command": "${HOOK_CMD}", "async": true}]}],
  "SubagentStart": [{"hooks": [{"type": "command", "command": "${HOOK_CMD}", "async": true}]}]
}
EOF
)

# Back up, then append our hook to each event without touching anything
# already there. Re-running is a no-op: entries pointing at hook.sh are skipped.
cp "$SETTINGS" "${SETTINGS}.beatpilot.bak"
jq --argjson newhooks "$HOOKS_JSON" --arg cmd "$HOOK_CMD" '
  .hooks = (.hooks // {}) |
  reduce ($newhooks | to_entries[]) as $e (.;
    if ((.hooks[$e.key] // []) | map(.hooks[]?.command) | index($cmd)) then .
    else .hooks[$e.key] = ((.hooks[$e.key] // []) + $e.value) end)
' "$SETTINGS" > "${SETTINGS}.tmp"
mv -f "${SETTINGS}.tmp" "$SETTINGS"

chmod +x "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}"/adapters/*.sh "${SCRIPT_DIR}"/bin/*.sh

echo "Hooks installed to ${SETTINGS} (backup: ${SETTINGS}.beatpilot.bak)"
echo "Note: the Claude Code plugin brings its own hooks. Use one or the other,"
echo "      not both, or every event fires twice."
echo ""
echo "Usage:"
echo "  Start a new Claude session — music plays automatically."
echo "  Run ./toggle.sh to turn music on/off."
echo "  Or use /music inside Claude (after restart)."
echo ""
echo "To uninstall, run: ./uninstall.sh"
