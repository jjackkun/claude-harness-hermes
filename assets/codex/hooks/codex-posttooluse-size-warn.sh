#!/usr/bin/env bash
# Codex PostToolUse hook — warn when edited files grow too large.

set -euo pipefail

project_dir="${CODEX_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
cd "$project_dir" 2>/dev/null || true

SOFT_WARN_LINES="${SOFT_WARN_LINES:-400}"
HARD_WARN_LINES="${HARD_WARN_LINES:-${MAX_LINES_HARD:-500}}"
[[ -f .harnessrc ]] && source .harnessrc
SOFT_WARN_LINES="${SOFT_WARN_LINES:-400}"
HARD_WARN_LINES="${HARD_WARN_LINES:-${MAX_LINES_HARD:-500}}"

FILE_PATH=$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {}) or d.get('input', {})
    print(ti.get('file_path') or ti.get('path') or '')
except Exception:
    print('')
" 2>/dev/null || true)

[[ -z "$FILE_PATH" ]] && exit 0
[[ -f "$FILE_PATH" ]] || exit 0

case "$FILE_PATH" in
  *.py|*.js|*.jsx|*.ts|*.tsx|*.svelte|*.vue|*.go|*.rs|*.java|*.rb) ;;
  *) exit 0 ;;
esac

LC=$(wc -l < "$FILE_PATH")

if (( LC > HARD_WARN_LINES )); then
  echo "[codex:R-size HARD] $FILE_PATH = $LC lines > $HARD_WARN_LINES. Split responsibilities before committing."
elif (( LC > SOFT_WARN_LINES )); then
  echo "[codex:R-size SOFT] $FILE_PATH = $LC lines. Check whether this file now has more than one responsibility."
fi

exit 0
