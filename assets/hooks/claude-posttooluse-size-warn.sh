#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook — 편집 직후 파일 줄 수를 두 단계로 경고.
#
# 목적: pre-commit 의 R-size 한도(MAX_LINES_HARD=500) 에 *도달한 뒤* 알게 되는 문제.
# 2026-04-15 한 프로젝트 세션 자성: watch.py 가 833 줄까지 부풀어 split 타이밍을 놓쳤다.
# 본 hook 은 400 줄 (soft) 에서 미리 경고하여 split 판단을 조기 유도한다.
#
# 차단하지 않는다(exit 0) — 감각 학습 목적. 강제 차단은 pre-commit 의 몫.
#
# 임계값:
#   SOFT_WARN_LINES (기본 400) — "곧 한도" 경고
#   HARD_WARN_LINES (기본 MAX_LINES_HARD=500) — "한도 초과, 즉시 split" 경고
#
# 등록: .claude/settings.json 의 hooks.PostToolUse[matcher=Write|Edit].

set -euo pipefail

# CWD 가드 — Claude Code 가 주입하는 $CLAUDE_PROJECT_DIR 로 이동 (없으면 스크립트 위치 기반).
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

SOFT_WARN_LINES="${SOFT_WARN_LINES:-400}"
HARD_WARN_LINES="${HARD_WARN_LINES:-${MAX_LINES_HARD:-500}}"
[[ -f .harnessrc ]] && source .harnessrc
SOFT_WARN_LINES="${SOFT_WARN_LINES:-400}"
HARD_WARN_LINES="${HARD_WARN_LINES:-${MAX_LINES_HARD:-500}}"

FILE_PATH=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null || true)

[[ -z "$FILE_PATH" ]] && exit 0
[[ -f "$FILE_PATH" ]] || exit 0

case "$FILE_PATH" in
  *.py|*.js|*.jsx|*.ts|*.tsx|*.svelte) ;;
  *) exit 0 ;;
esac

LC=$(wc -l < "$FILE_PATH")

if (( LC > HARD_WARN_LINES )); then
  echo "[R-size HARD] $FILE_PATH = $LC 줄 > $HARD_WARN_LINES. commit 시 차단됨."
  echo "  이 파일에 책임이 몇 개인지 세고, 2개 이상이면 파일별 책임 분리 → 배럴 재export."
  echo "  정말 한 책임이면 파일 상단에 waiver 주석 + docs/audits/ 근거 기록 후 .harnessrc MAX_LINES_HARD 상향."
  echo "  근거: docs/design-docs/core-beliefs.md#r-size"
elif (( LC > SOFT_WARN_LINES )); then
  echo "[R-size SOFT] $FILE_PATH = $LC 줄 (한도 $HARD_WARN_LINES, 잔여 $((HARD_WARN_LINES - LC))). 이미 늦었을 가능성."
  echo "  이 파일에 책임이 몇 개인지 먼저 세기. 2개 이상이면 지금 split, 1개면 계속."
  echo "  근거: docs/design-docs/core-beliefs.md#r-size"
fi

exit 0
