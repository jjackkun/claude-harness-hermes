#!/usr/bin/env bash
# PreToolUse(Write) hook — 새 코드 파일이 계획서 §4 에 선언돼 있는지 본다.
#
# 근거: docs/design-docs/core-beliefs.md#r-declare
#
# 왜 필요한가:
#   템플릿 §4 는 "신규 파일 목록 (파일별 책임 1줄 필수) ← 비워두지 말 것" 을 요구하고
#   "위 목록을 먼저 못 쓰면 아직 설계가 덜 됐다는 뜻. 구현 들어가지 말 것" 이라고까지 적는다.
#   그런데 이를 확인하는 장치가 없어 템플릿의 부탁으로만 남아 있었다(2026-08-25).
#
# 왜 여기인가:
#   커밋 시점에는 이미 파일이 있다. "구조를 먼저 잡는다" 는 파일이 생기기 전에만 성립한다.
#   R-iface 가 같은 자리에서 인터페이스 **폭**을 보고, 이 훅은 **책임 선언 여부**를 본다.
#
# 왜 차단이 아닌가:
#   새 파일 생성은 정당한 경우가 많다 — 스크래치, 픽스처, 긴급 수정. 차단하면
#   우회가 상시화된다. R-iface 는 "폭 8 이상" 이라는 이분 판정이라 차단할 수 있지만,
#   "이 파일이 계획에 있었어야 하는가" 는 기계가 판정할 수 없다. 알리되 막지 않는다.

set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

FILE_PATH=$(python3 -c "
import sys, json
try:
    print((json.load(sys.stdin).get('tool_input', {}) or {}).get('file_path', '') or '')
except Exception:
    print('')
" 2>/dev/null || true)

[[ -n "$FILE_PATH" ]] || exit 0

# 절대 경로로 오므로 프로젝트 기준 상대 경로로 되돌린다.
REL="${FILE_PATH#"$PWD"/}"

# 코드 파일만 본다. 문서·설정·픽스처는 "한 파일 한 책임" 의 대상이 아니다.
case "$REL" in
  *.py|*.js|*.jsx|*.ts|*.tsx|*.svelte|*.vue|*.go|*.rs|*.java|*.rb|*.php) ;;
  *) exit 0 ;;
esac

# 하네스 생성물은 재설치가 덮어쓰는 산출물이지 사람이 설계하는 파일이 아니다.
case "$REL" in
  scripts/hooks/*|scripts/codex-hooks/*) exit 0 ;;
esac

# 이미 있는 파일의 수정은 이 훅의 질문 대상이 아니다.
# 묻는 것은 "이 파일을 **만들기 전에** 책임을 적었는가" 다.
[[ -e "$FILE_PATH" ]] && exit 0

ACTIVE_DIR="docs/exec-plans/active"
[[ -d "$ACTIVE_DIR" ]] || exit 0

PLAN_STATE=""
for cand in scripts/hooks/plan_state.py .git/hooks/plan_state.py; do
  [[ -f "$cand" ]] && PLAN_STATE="$cand" && break
done
[[ -n "$PLAN_STATE" ]] || exit 0

# 계획이 하나도 없으면 침묵한다 — 계획 부재는 R-plan-missing 의 관할이다.
# 여기서 또 말하면 같은 사실로 경고가 둘이 되고, 그러면 둘 다 무시된다.
DECLARED=""
FOUND_PLAN=0
while IFS= read -r plan; do
  [[ -f "$plan" ]] || continue
  FOUND_PLAN=1
  DECLARED+=$'\n'"$(python3 "$PLAN_STATE" declared-files "$plan" 2>/dev/null || true)"
done < <(find "$ACTIVE_DIR" -maxdepth 1 -name '*.md' ! -name 'template.md' -type f 2>/dev/null)

[[ "$FOUND_PLAN" -eq 1 ]] || exit 0

# `grep -q ... && exit 0` 은 set -e 아래에서 **미발견 시 훅을 통째로 종료**시킨다.
# 그러면 경고가 영원히 나오지 않는다 — 조용히 죽는 게이트다.
# 여기가 판정 지점이다 — 위의 조기 반환(확장자·기존 파일·계획 부재)은 분모에 넣지 않는다.
if [[ -f "$(dirname "$0")/gate_emit.sh" ]]; then
  # shellcheck source=/dev/null
  source "$(dirname "$0")/gate_emit.sh"
fi
declare -F gate_emit >/dev/null 2>&1 || gate_emit() { :; }

if printf '%s\n' "$DECLARED" | grep -qxF "$REL"; then
  gate_emit R-declare pass pretooluse "$REL" "§4 에 선언됨"
  exit 0
fi
gate_emit R-declare warn pretooluse "$REL" "§4 에 없음"

REASON="[R-declare] $REL — 계획서 §4 의 신규 파일 목록에 없습니다.
  → 만들기 전에 이 파일의 **유일한 책임**을 한 문장으로 §4 에 적으십시오.
     적을 수 없으면 아직 설계가 덜 된 것입니다 (템플릿 §4 의 문구).
  근거: docs/design-docs/core-beliefs.md#r-declare"

python3 -c "
import json, sys
r = sys.argv[1]
print(json.dumps({'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'additionalContext': r,
}}, ensure_ascii=False))
" "$REASON"

exit 0
