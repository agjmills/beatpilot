#!/bin/bash
DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
exec "$DIR/volume.sh" "$@"
