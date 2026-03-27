#!/bin/bash
# Uninstall Beatpilot hooks from global settings
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD="${SCRIPT_DIR}/hook.sh"

# Stop the engine if running
"${SCRIPT_DIR}/stop.sh" 2>/dev/null || true
rm -f /tmp/beatpilot-disabled /tmp/beatpilot-state

if [ -f "$SETTINGS" ]; then
    # Remove hooks that point to our hook.sh
    jq --arg cmd "$HOOK_CMD" '
      .hooks |= (if . then
        with_entries(
          .value |= map(select(
            .hooks | all(.command != $cmd)
          )) | select(length > 0)
        ) | if . == {} then empty else . end
      else . end)
    ' "$SETTINGS" > "${SETTINGS}.tmp"
    mv -f "${SETTINGS}.tmp" "$SETTINGS"
    echo "Beatpilot hooks removed from ${SETTINGS}"
else
    echo "No settings file found"
fi

echo "Uninstalled. Restart Claude to take effect."
