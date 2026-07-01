#!/usr/bin/env bash
# PreToolUse(Task|Agent) hook — 잘못된 subagent_type 으로 dispatch 하는 것을 가로챈다.
#
# 출처: 한 프로젝트 2026-04-14 세션에서 frontend/fullstack 작업을 5회 연속 general-purpose
#       에이전트로 dispatch 한 패턴 발견. 메모리/리마인더가 아닌 hook 으로 강제.
# 근거: docs/design-docs/core-beliefs.md#r-agent
#
# 동작:
#   1. tool_input.subagent_type 이 general-purpose 인지 검사
#   2. tool_input.prompt 에 frontend / fullstack / DB / TS 키워드가 있는지 검사
#   3. 매칭되면 hookSpecificOutput.additionalContext 로 올바른 도메인 에이전트 안내
#
# 강제 모델: 다른 hook 과 동일하게 soft warning. 차단이 아니라 컨텍스트 주입으로
# 에이전트가 자기 검열하도록 유도. 강한 차단을 원하면 stdout 에 decision: block 추가
# 가능하나 (Claude Code 일부 버전에서 지원), 호환성 위해 컨텍스트 주입 방식 채택.
#
# 등록: .claude/settings.json 의 hooks.PreToolUse[matcher="Task|Agent"] 항목.

set -euo pipefail

# CWD 가드 — Claude Code 가 주입하는 $CLAUDE_PROJECT_DIR 로 이동 (없으면 스크립트 위치 기반).
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

PAYLOAD=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {}) or {}
    print(json.dumps({
        'subagent_type': ti.get('subagent_type', ''),
        'prompt': ti.get('prompt', ''),
        'description': ti.get('description', ''),
    }, ensure_ascii=False))
except Exception:
    print('{}')
" 2>/dev/null || echo '{}')

SUBAGENT=$(echo "$PAYLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('subagent_type',''))" 2>/dev/null || echo '')
HAYSTACK=$(echo "$PAYLOAD" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print((d.get('prompt','') + ' ' + d.get('description','')).lower())
" 2>/dev/null || echo '')

# 검사 대상:
#   1) general-purpose dispatch — 도메인 에이전트로 재라우팅 권고
#   2) code-reviewer dispatch + DB 변경 신호 — database-reviewer 병행 권고
#      (code-reviewer 는 Task 도구가 없어 자체 위임 불가, 오케스트레이터가 병렬 dispatch 해야 함)
# 그 외 도메인 에이전트가 명시적으로 선택된 케이스는 그대로 통과.
if [[ "$SUBAGENT" != "general-purpose" && "$SUBAGENT" != "code-reviewer" && -n "$SUBAGENT" ]]; then
  exit 0
fi

# 도메인 키워드 매칭
SUGGEST=""

# code-reviewer 대상은 DB 변경 신호일 때만 database-reviewer 병행 권고로 한정.
# (DB 변경이 없는 코드 리뷰는 단독 dispatch 유지 — 사용자 요구: "DB 개선이 있는 경우에만 동작")
if [[ "$SUBAGENT" == "code-reviewer" ]]; then
  if echo "$HAYSTACK" | grep -Eq 'alembic|migration|schema\.sql|create table|alter table|drop table|add column|create index|jsonb|rls policy|postgres|\.sql( |$)'; then
    python3 - <<'PY'
import json
out = {
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": (
      "[R-agent] code-reviewer dispatch 에 DB 변경 신호 감지 → database-reviewer 를 "
      "병렬로 함께 dispatch 하라. code-reviewer 는 Task 도구가 없어 스스로 위임할 수 없다. "
      "DB 변경이 없으면 이 안내는 무시. 근거: docs/design-docs/core-beliefs.md#r-review"
    )
  }
}
print(json.dumps(out, ensure_ascii=False))
PY
  fi
  exit 0
fi

# Frontend / Fullstack 신호
if echo "$HAYSTACK" | grep -Eq '\.svelte|\+page\.svelte|\+layout\.svelte|src/lib/components|src/routes|frontend|sveltekit|tailwind|dialog|modal|component|impeccable|design'; then
  SUGGEST="fullstack-developer"
fi

# DB 스키마/마이그레이션 신호
if echo "$HAYSTACK" | grep -Eq 'alembic|migration|schema\.sql|column|create table|alter table|index|jsonb|postgres'; then
  if [[ -n "$SUGGEST" ]]; then
    SUGGEST="${SUGGEST} + database-reviewer"
  else
    SUGGEST="database-reviewer"
  fi
fi

# TypeScript 코드 리뷰 신호
if echo "$HAYSTACK" | grep -Eq 'typescript|\.tsx?( |$)|tsconfig|generic type|interface |type alias'; then
  if [[ -n "$SUGGEST" ]]; then
    SUGGEST="${SUGGEST} + typescript-reviewer"
  else
    SUGGEST="typescript-reviewer"
  fi
fi

if [[ -z "$SUGGEST" ]]; then
  exit 0
fi

# 컨텍스트 주입 — 에이전트가 다음 행동을 결정할 수 있게
python3 - "$SUGGEST" <<'PY'
import json, sys
suggest = sys.argv[1]
out = {
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": (
      f"[R-agent] general-purpose dispatch 에 도메인 키워드 감지 → 권장: {suggest}. "
      "범용 조사·문서가 아니면 dispatch 취소 후 권장 에이전트로 재호출. "
      "근거: docs/design-docs/core-beliefs.md#r-agent"
    )
  }
}
print(json.dumps(out, ensure_ascii=False))
PY

exit 0
