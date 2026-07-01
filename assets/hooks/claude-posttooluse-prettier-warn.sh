#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook — 편집 직후 prettier --check 결과를 경고로만 띄운다.
#
# 출처: rim-kanban Phase 1 (scripts/hooks/post-write-prettier.sh) 를 generic 화.
# 근거: docs/design-docs/core-beliefs.md#r-fmt
#
# 차단하지 않는다(exit 2 안 함) — 감각 학습 목적.
# 에이전트가 자기 편집 결과의 포맷팅 위반을 즉시 보고 다음 편집부터 자가 교정한다.
#
# 등록: .claude/settings.json 의 hooks.PostToolUse[matcher=Write|Edit] 항목.

set -euo pipefail

# CWD 가드 — Claude Code 가 주입하는 $CLAUDE_PROJECT_DIR 로 이동 (없으면 스크립트 위치 기반).
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

FILE_PATH=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null || true)

[[ -z "$FILE_PATH" ]] && exit 0

# prettier 가 처리하는 확장자만.
case "$FILE_PATH" in
  *.js|*.jsx|*.ts|*.tsx|*.svelte|*.vue|*.json|*.css|*.scss|*.md|*.yaml|*.yml)
    ;;
  *)
    exit 0
    ;;
esac

# prettier 가 프로젝트에 없으면 조용히 종료.
if ! command -v pnpm >/dev/null 2>&1 && ! command -v npx >/dev/null 2>&1; then
  exit 0
fi

# 차단 안 함 — stdout 경고만 출력.
RUNNER="npx --no-install"
command -v pnpm >/dev/null 2>&1 && RUNNER="pnpm exec"

if ! $RUNNER prettier --check "$FILE_PATH" >/dev/null 2>&1; then
  echo "[R-fmt] $FILE_PATH prettier 위반 — 다음 편집에서 자가 교정."
  echo "  근거: docs/design-docs/core-beliefs.md#r-fmt"
fi

exit 0
