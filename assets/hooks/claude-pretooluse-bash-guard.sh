#!/usr/bin/env bash
# PreToolUse(Bash) hook — Claude 가 Bash 도구로 위험 명령을 실행하려 할 때 가로챈다.
#
# 출처: rim-kanban Phase 1 (scripts/hooks/pre-commit-reviewer-check.sh) 를 generic 화.
# 근거: docs/design-docs/core-beliefs.md#r5, #r-review
#
# 두 가지를 검사한다:
#   1. `git commit` — 위험 신호가 있으면 리뷰 검토를 상기시킨다.
#   2. `--no-verify` / `-n` (단축) — 우회 시도 탐지. R5 강제.
#
# 메커니즘: stdin 으로 도구 호출 페이로드(JSON)가 들어오고,
# stdout 으로 hookSpecificOutput 을 출력하면 additionalContext 가
# 모델 컨텍스트에 주입된다.
#
# 등록: .claude/settings.json 의 hooks.PreToolUse[matcher=Bash] 항목.

set -euo pipefail

# CWD 가드 — Claude Code 가 주입하는 $CLAUDE_PROJECT_DIR 로 이동 (없으면 스크립트 위치 기반).
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

CMD=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || true)

# --no-verify 우회 시도 탐지 — 단순 grep 으로 100% 차단은 불가능하나
# 강한 경고로 에이전트가 자기 검열하도록 유도.
if echo "$CMD" | grep -Eq -- '(^|[[:space:]])(-n|--no-verify)([[:space:]]|$)'; then
  python3 <<'PY'
import json
out = {
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": (
      "[R5] --no-verify 금지. hook 이 막으면 코드/hook 을 고친다. "
      "근거: docs/design-docs/core-beliefs.md#r5"
    )
  }
}
print(json.dumps(out, ensure_ascii=False))
PY
  exit 0
fi

# git commit 감지 — 리뷰 기록(.claude/.review-dirty)이 있으면 soft reminder 만 주입.
if echo "$CMD" | grep -q "git commit"; then
  if [[ -f .claude/.review-dirty ]]; then
    DIRTY_SUMMARY=$(head -5 .claude/.review-dirty 2>/dev/null || echo "(read error)")
    python3 - "$DIRTY_SUMMARY" <<'PY'
import json, sys
summary = sys.argv[1]
out = {
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": (
      "[R-review] 최근 코드 편집 기록이 있습니다. 변경이 크거나 공유 경계/보안/DB/동시성에 "
      "영향이 있으면 commit 전 code-reviewer 를 사용하세요.\n\n"
      f"{summary}\n\n"
      "단순 변경이면 계속 진행해도 됩니다. 기록 정리: rm .claude/.review-dirty"
    )
  }
}
print(json.dumps(out, ensure_ascii=False))
PY
    exit 0
  fi
  python3 <<'PY'
import json
out = {
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": (
      "[HARNESS] git commit 감지. 큰 변경이나 공유 경계 변경이면 "
      "code-reviewer 사용을 고려하세요."
    )
  }
}
print(json.dumps(out, ensure_ascii=False))
PY
fi

exit 0
