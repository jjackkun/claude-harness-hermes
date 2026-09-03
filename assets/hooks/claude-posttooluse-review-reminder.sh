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
  # 빚이 *생긴* 사건만 기록한다. 이어지는 편집은 같은 빚의 누적이라 세면 중복이 된다.
  #
  # 키가 `R-review` 가 아니라 `R-review-debt` 인 이유: bash-guard 가 커밋 시점에
  # 같은 `R-review` 로 pass/warn 을 남긴다. 한 키에 **분모가 다른 두 모집단**
  # (편집 횟수 / 커밋 횟수)을 섞으면 발화율이 아무것도 뜻하지 않게 된다.
  if [[ -f "$(dirname "$0")/gate_emit.sh" ]]; then
    # shellcheck source=/dev/null
    source "$(dirname "$0")/gate_emit.sh"
    gate_emit R-review-debt warn posttooluse "$FILE_PATH" "리뷰 빚 발생"
  fi
fi

exit 0
