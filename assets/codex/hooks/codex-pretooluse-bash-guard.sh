#!/usr/bin/env bash
# Codex PreToolUse hook — guard Bash commands that bypass verification.

set -euo pipefail

project_dir="${CODEX_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
cd "$project_dir" 2>/dev/null || true

CMD=$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {}) or d.get('input', {})
    print(ti.get('command', ''))
except Exception:
    print('')
" 2>/dev/null || true)

[[ -z "$CMD" ]] && exit 0

if echo "$CMD" | grep -Eq -- '(^|[[:space:]])(-n|--no-verify)([[:space:]]|$)'; then
  echo "[codex:R-verify] --no-verify is not allowed. Fix the failing check or the hook instead of bypassing it."
  exit 2
fi

if echo "$CMD" | grep -q "git commit"; then
  echo "[codex:R-review] git commit detected. If this change is non-trivial, run the Codex review workflow first."
fi

exit 0
