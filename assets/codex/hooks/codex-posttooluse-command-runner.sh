#!/usr/bin/env bash
# Run a resolved preset PostToolUse command under Codex.

set -euo pipefail

COMMAND="${1:-}"
[[ -z "$COMMAND" ]] && exit 0

project_dir="${CODEX_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
cd "$project_dir" 2>/dev/null || true

payload="$(cat 2>/dev/null || true)"
file_path=$(printf '%s' "$payload" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {}) or d.get('input', {})
    print(ti.get('file_path') or ti.get('path') or '')
except Exception:
    print('')
" 2>/dev/null || true)

export CODEX_TOOL_FILE_PATH="$file_path"
# Compatibility for shared presets that still express generic edit hooks with
# the older variable name. Codex-specific hook files do not rely on it.
export CLAUDE_TOOL_FILE_PATH="$file_path"

bash -lc "$COMMAND"
