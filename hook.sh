#!/bin/bash
# Beatpilot Hook — Claude Code entry point
# Forwards to the Claude Code adapter. Kept for backwards compatibility
# with existing hook registrations in ~/.claude/settings.json.

SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
exec "${SCRIPT_DIR}/adapters/claude-code.sh"
