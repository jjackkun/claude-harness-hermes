#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook — 코드 작업 발생 시 리뷰 검토용 변경 기록.
#
# 설계:
#   - Write/Edit 발생 → .claude/.review-dirty 파일에 최근 코드 편집을 기록한다.
#   - 첫 코드 편집 때만 soft reminder 출력. 이후 편집은 조용히 누적한다.
#   - commit 단계 bash-guard 는 차단하지 않고 기록 요약만 컨텍스트에 주입한다.

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

# 코드 파일만 dirty 대상. 문서/설정/픽스처는 제외.
case "$FILE_PATH" in
  *.py|*.js|*.jsx|*.ts|*.tsx|*.svelte|*.vue|*.go|*.rs|*.java|*.rb) ;;
  *) exit 0 ;;
esac

DIRTY_FILE=".claude/.review-dirty"
mkdir -p .claude 2>/dev/null || exit 0

# 최초 기록: 첫 편집 파일 + 시각. 이후 편집은 append 로 흔적만.
FIRST_DIRTY=0
if [[ ! -f "$DIRTY_FILE" ]]; then
  echo "first: $(date '+%Y-%m-%d %H:%M:%S')  $FILE_PATH" > "$DIRTY_FILE"
  FIRST_DIRTY=1
fi
echo "edit: $(date '+%H:%M:%S')  $FILE_PATH" >> "$DIRTY_FILE"

if [[ $FIRST_DIRTY -eq 1 ]]; then
  echo "[R-review] 코드 편집 기록 시작 — 큰 변경이면 commit 전 code-reviewer 를 고려하세요."
  echo "  기록 정리: rm .claude/.review-dirty"
fi

exit 0
