#!/bin/bash
DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
exec "$DIR/install-samples.sh" "$@"
