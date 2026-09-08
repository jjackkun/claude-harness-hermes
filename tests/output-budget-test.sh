#!/usr/bin/env bash
# R-out 게이트 시험 — 실측 바이트로 판정하는지, 그리고 조용해야 할 때 조용한지 본다.
#
# 근거: docs/exec-plans/active/2026-09-08-tool-output-budget.md
#
# 통과만 확인하는 시험은 게이트가 조용히 꺼진 것을 못 잡는다(harness-hooks-smoke.sh 선례).
# 그래서 임계 초과 페이로드로 **실제 발화**를 확인하고, 판정 불가가 pass 로 새지 않는지도
# 단언한다 — 2026-09-08 검토에서 R-plan-stale 이 정확히 그 실수를 했다.
#
# 게이트 기록은 CLAUDE_PROJECT_DIR 를 임시 디렉터리로 돌려 받는다.
# 저장소의 실제 .harness/gate-events.jsonl 을 시험 이벤트로 오염시키면 안 된다.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-posttooluse-output-budget.sh"
PASS=0
FAIL=0

ok()  { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 없음"; exit 0; }
[[ -x "$HOOK" ]] || { echo "FAIL: 훅이 없거나 실행 불가: $HOOK"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
EVENTS="$TMP/.harness/gate-events.jsonl"

# payload <바이트수> [interrupted] — stdout 이 정확히 N 바이트인 가짜 페이로드
payload() {
  python3 -c "
import json,sys
n=int(sys.argv[1]); intr = len(sys.argv)>2 and sys.argv[2]=='1'
print(json.dumps({'hook_event_name':'PostToolUse','tool_name':'Bash',
  'tool_input':{'command':'probe'},'duration_ms':42,
  'tool_response':{'stdout':'x'*n,'stderr':'','interrupted':intr,
                   'isImage':False,'noOutputExpected':False}}))
" "$@"
}

run() { CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK"; }

verdict_of() { grep -o "\"verdict\": \"[a-z]*\"" "$EVENTS" 2>/dev/null | tail -1 | cut -d'"' -f4; }

# ── 1. 임계 미만 → 조용하고 pass ──────────────────────────────────────────
OUT=$(payload 100 | run)
[[ -z "$OUT" ]] && ok "임계 미만이면 아무것도 주입하지 않는다" \
                || bad "임계 미만인데 주입했다: $OUT"
[[ "$(verdict_of)" == "pass" ]] && ok "임계 미만은 pass 로 기록된다" \
                                || bad "임계 미만 판정이 '$(verdict_of)'"

# ── 2. 임계 초과 → 발화 (핵심 — 여기가 죽으면 게이트가 꺼진 것) ──────────
OUT=$(payload 20000 | run)
if echo "$OUT" | grep -q "R-out"; then
  ok "임계 초과 시 실제로 발화한다"
  echo "$OUT" | grep -q "20,000B" && ok "실측 바이트를 알려준다" \
                                  || bad "무엇이 문제인지 수치를 안 준다"
  echo "$OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null \
    && ok "주입 출력이 유효한 JSON 이다" || bad "JSON 이 깨졌다"
else
  bad "임계를 넘겼는데 침묵했다 — 게이트가 꺼져 있다"
fi
[[ "$(verdict_of)" == "warn" ]] && ok "임계 초과는 warn 으로 기록된다" \
                                || bad "임계 초과 판정이 '$(verdict_of)'"

# ── 3. 판정 불가는 pass 가 아니다 (분모 오염 방지) ───────────────────────
payload 20000 1 | run >/dev/null
[[ "$(verdict_of)" == "skipped" ]] && ok "중단된 명령은 skipped (pass 아님)" \
                                   || bad "중단 판정이 '$(verdict_of)' — 분모가 오염된다"

echo '{"hook_event_name":"PostToolUse","tool_name":"Bash"}' | run >/dev/null
[[ "$(verdict_of)" == "skipped" ]] && ok "tool_response 부재는 skipped" \
                                   || bad "tool_response 부재 판정이 '$(verdict_of)'"

echo 'not json at all' | run >/dev/null
[[ "$(verdict_of)" == "skipped" ]] && ok "깨진 페이로드는 skipped" \
                                   || bad "깨진 페이로드 판정이 '$(verdict_of)'"

# 파싱은 되지만 최상위가 dict 가 아닌 경우 — 2026-09-08 검토가 잡은 결함.
# 이때 판정이 통째로 사라져 skipped 조차 남지 않았다. "깨진 JSON" 케이스만으로는
# 이 분기를 못 만든다 — 통과만 보는 시험의 변종이었다.
for LIT in '[]' '123' '"str"'; do
  rm -f "$EVENTS"
  echo "$LIT" | run >/dev/null
  if [[ ! -f "$EVENTS" ]]; then
    bad "최상위가 dict 가 아닌 JSON($LIT) 에서 아무 기록도 남지 않았다"
  elif [[ "$(verdict_of)" == "skipped" ]]; then
    ok "최상위가 dict 아닌 JSON($LIT) 은 skipped"
  else
    bad "$LIT 판정이 '$(verdict_of)' — 판정 불가가 통과로 샌다"
  fi
done

# ── 4. stderr 도 센다 (절반만 세면 시끄러운 명령을 놓친다) ───────────────
OUT=$(python3 -c "
import json
print(json.dumps({'hook_event_name':'PostToolUse','tool_name':'Bash',
  'tool_input':{'command':'probe'},'duration_ms':1,
  'tool_response':{'stdout':'x'*5000,'stderr':'y'*5000,'interrupted':False}}))
" | run)
echo "$OUT" | grep -q "R-out" && ok "stdout+stderr 를 합산한다 (각 5000B → 발화)" \
                              || bad "stderr 를 안 세서 10,000B 를 놓쳤다"

# ── 5. 명령 패턴으로 추측하지 않는다 (오탐 구조적 차단) ──────────────────
if grep -qE "pytest|npm (run )?test|yarn |webpack|docker build" "$HOOK"; then
  bad "훅이 명령 패턴을 매칭한다 — R5 '-n' 오탐과 같은 위험"
else
  ok "명령 패턴 매칭이 없다 (실측만 사용)"
fi

# ── 6. 배선이 살아 있는가 ────────────────────────────────────────────────
CONF="$REPO_ROOT/presets/workflow/harness.conf"
grep -q "claude-posttooluse-output-budget.sh" "$CONF" \
  && ok "harness.conf 에 배선돼 있다" || bad "배선이 없어 12곳에 안 깔린다"
grep -q "POST_TOOL_USE_HOOKS.*Bash::.*output-budget" "$CONF" \
  && ok "Bash 매처로 등록된다" || bad "매처 등록이 없다"

# ── 7. 저장소 실제 기록을 오염시키지 않았는가 ────────────────────────────
[[ -f "$EVENTS" ]] && ok "시험 이벤트는 임시 디렉터리에만 남았다" \
                   || bad "임시 이벤트 파일이 없다 — 실제 .harness 에 썼을 수 있다"

echo ""
echo "  결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
