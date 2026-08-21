#!/usr/bin/env bash
# Codex PostToolUse hook — two signals after an edit.
#   (1) line-count warnings (safety net)
#   (2) responsibility-growth signal — fires on a jump in top-level symbols vs the
#       last commit, independent of line count.
# Rationale for (2): docs/superpowers/specs/2026-08-21-responsibility-over-linecount-design.md
# Line count failed as a proxy for responsibility count; only the per-edit delta discriminated.

set -euo pipefail

project_dir="${CODEX_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
cd "$project_dir" 2>/dev/null || true

SOFT_WARN_LINES="${SOFT_WARN_LINES:-400}"
HARD_WARN_LINES="${HARD_WARN_LINES:-${MAX_LINES_HARD:-500}}"
RESP_DELTA_WARN="${RESP_DELTA_WARN:-5}"
[[ -f .harnessrc ]] && source .harnessrc
SOFT_WARN_LINES="${SOFT_WARN_LINES:-400}"
HARD_WARN_LINES="${HARD_WARN_LINES:-${MAX_LINES_HARD:-500}}"
RESP_DELTA_WARN="${RESP_DELTA_WARN:-5}"

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

# `.md` is excluded from line-count warnings (docs would over-fire) but included
# in the responsibility signal — every measured violation was a design document.
case "$FILE_PATH" in
  *.py|*.js|*.jsx|*.ts|*.tsx|*.svelte|*.vue|*.go|*.rs|*.java|*.rb) CHECK_LINES=1 ;;
  *.md) CHECK_LINES=0 ;;
  *) exit 0 ;;
esac

WARNED_LINES=0

if (( CHECK_LINES )); then
LC=$(wc -l < "$FILE_PATH")

if (( LC > HARD_WARN_LINES )); then
  echo "[codex:R-size HARD] $FILE_PATH = $LC lines > $HARD_WARN_LINES. Split responsibilities before committing."
elif (( LC > SOFT_WARN_LINES )); then
  echo "[codex:R-size SOFT] $FILE_PATH = $LC lines. Check whether this file now has more than one responsibility."
fi
(( LC > SOFT_WARN_LINES )) && WARNED_LINES=1
fi

# ── (2) responsibility-growth signal ────────────────────────────────
# Stay silent if a line-count warning already fired — it already says "count the
# responsibilities", and stacking warnings is how people end up disabling the hook.
(( WARNED_LINES )) && exit 0

# Baseline is the last commit: no state file, and it resets itself every commit.
# Files absent from HEAD are skipped — without a baseline there is no "growth",
# and a document written in one sitting would be a guaranteed false positive.
REL=$(git ls-files --full-name --error-unmatch -- "$FILE_PATH" 2>/dev/null) || exit 0
[[ -n "$REL" ]] || exit 0

case "$FILE_PATH" in
  *.md) SYM_PAT='^### '  ; SYM_UNIT='subsections' ;;
  *.py) SYM_PAT='^(def |class |async def )' ; SYM_UNIT='top-level def/class' ;;
  *.go) SYM_PAT='^func ' ; SYM_UNIT='top-level func' ;;
  *.rs) SYM_PAT='^(pub )?(fn|impl|struct|enum) ' ; SYM_UNIT='top-level items' ;;
  *.js|*.jsx|*.ts|*.tsx|*.svelte|*.vue) SYM_PAT='^export ' ; SYM_UNIT='exported symbols' ;;
  # No validated pattern for the rest — the line-count net still covers them.
  *) exit 0 ;;
esac

SYM_NOW=$(grep -cE "$SYM_PAT" "$FILE_PATH" 2>/dev/null || true)
SYM_BASE=$(git show "HEAD:$REL" 2>/dev/null | grep -cE "$SYM_PAT" || true)
SYM_NOW="${SYM_NOW:-0}"; SYM_BASE="${SYM_BASE:-0}"

if (( SYM_NOW - SYM_BASE >= RESP_DELTA_WARN )); then
  echo "[codex:R-size responsibility] $FILE_PATH — $SYM_UNIT since last commit: $SYM_BASE -> $SYM_NOW (+$((SYM_NOW - SYM_BASE)))."
  echo "  Count the responsibilities in this file; if 2+, split per responsibility and re-export."
  echo "  First check: does what you just added fall inside the responsibility the filename promises?"
  echo "  This signal is independent of line count. 400/500 is a safety net, not the split point."
fi

exit 0
