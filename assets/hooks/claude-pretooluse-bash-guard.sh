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

if [[ -f "$(dirname "$0")/gate_emit.sh" ]]; then
  # shellcheck source=/dev/null
  source "$(dirname "$0")/gate_emit.sh"
fi
declare -F gate_emit >/dev/null 2>&1 || gate_emit() { :; }

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
#
# `-n` 은 **`git commit` 문맥에서만** `--no-verify` 의 약어다.
# 문맥을 안 보던 이전 규칙은 `grep -n`·`sort -n`·`head -n`·`git log -n` 을 전부 잡아
# 발화율 100%(관측 20건 전부 오탐, 2026-09-03)를 냈다. 우회를 막는 룰의 경고가
# 상시 배경 소음이 되면 진짜 우회가 섞여도 눈에 띄지 않는다 — 경보가 무의미해진다.
# 근거: docs/audits/2026-09-03-gate-firing-first-observation.md
#
# 알려진 한계: 커밋 메시지 본문에 들어간 `-n`(`git commit -m "fix -n bug"`)은 여전히 오탐이다.
# 명령 문자열만으로 인자와 메시지를 가르려면 셸 파서가 필요하고 그 비용이 이득을 넘는다.
#
# **명령 세그먼트 단위로 본다.** 명령 전체에서 "git commit 이 있는가" 와 "-n 이 있는가" 를
# 따로 물으면 `git log -n 5 && git commit -m x` 가 발화한다 — 두 조건이 서로 다른
# 명령에서 충족되기 때문이다. 이는 이 수정이 없애려던 오탐과 정확히 같은 종류다.
# `;` `&&` `||` `|` 로 잘라, **같은 세그먼트 안에서** 둘이 함께 성립할 때만 발화한다.
R5_TRIP=0
if echo "$CMD" | grep -Eq -- '(^|[[:space:]])--no-verify([[:space:]]|$)'; then
  # 이 문자열은 git 외 쓰임이 사실상 없다. 문맥을 따지지 않는다 —
  # 우회 1건을 놓치는 비용이 오탐 1건보다 크다.
  R5_TRIP=1
else
  while IFS= read -r _seg; do
    echo "$_seg" | grep -Eq '(^|[[:space:]])git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' || continue
    # 묶음 단축 플래그(`git commit -nm x`)도 잡는다 — 유효한 우회인데 이전 규칙은 놓쳤다.
    if echo "$_seg" | grep -Eq -- '(^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
      R5_TRIP=1
      break
    fi
  done < <(printf '%s\n' "$CMD" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g' -e 's/|/\n/g')
fi

if (( R5_TRIP )); then
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
  # R5 는 pass 를 세지 않는다. 분모가 "모든 Bash 호출" 이 되면 도구 호출마다 21ms 가 붙고,
  # 그 비율은 아무것도 말해주지 않는다 — 알고 싶은 것은 **우회 시도 횟수** 자체다.
  gate_emit R5 warn pretooluse "" "--no-verify 시도"
  exit 0
fi

# git commit 감지 — 리뷰 기록(.claude/.review-dirty)이 있으면 soft reminder 만 주입.
if echo "$CMD" | grep -q "git commit"; then
  # 여기는 분모가 성립한다 — 커밋 시도당 빚이 남아 있었는가.
  if [[ -f .claude/.review-dirty ]]; then
    gate_emit R-review warn pretooluse "" "빚이 남은 채 커밋 시도"
  else
    gate_emit R-review pass pretooluse "" "빚 없음"
  fi
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
