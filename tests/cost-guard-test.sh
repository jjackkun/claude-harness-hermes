#!/usr/bin/env bash
# cost-guard — 비싼 실행은 묻고(G1), 서브에이전트는 모델을 정하고(G2), 많이 부르면 다시 묻는다(G3).
#
# 근거: docs/exec-plans/active/2026-10-21-cost-guard-plan.md 목표 G1 · G2 · G3 · G7
#       (평가 대량 실행이 사용자 구독 한도를 다 써 측정이 무효가 된 사고)
#
# 실행: bash tests/cost-guard-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패. 모델 호출 0 — 전부 가짜 페이로드.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-pretooluse-cost-guard.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; H="$TMP/home"
mkdir -p "$P/.claude/agents" "$H/.claude/agents" "$H/plug/agents" "$H/.claude/plugins"
printf -- '---\nname: planner-lite\nmodel: sonnet\n---\n' > "$P/.claude/agents/planner-lite.md"
printf -- '---\nname: no-model\n---\n' > "$P/.claude/agents/no-model.md"
printf -- '---\nname: g-agent\nmodel: haiku\n---\n' > "$H/.claude/agents/g-agent.md"
printf -- '---\nname: p-agent\nmodel: opus\n---\n' > "$H/plug/agents/p-agent.md"
printf '{"version":2,"plugins":{"plug@mk":[{"installPath":"%s"}]}}\n' "$H/plug" > "$H/.claude/plugins/installed_plugins.json"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# run_hook <tool_name> <tool_input JSON> [session_id] — 결정(allow·ask·deny)을 출력한다. 출력 없음 = allow
run_hook() {
  python3 -c "
import json, sys
d = {'tool_name': sys.argv[1], 'tool_input': json.loads(sys.argv[2]), 'hook_event_name': 'PreToolUse'}
if sys.argv[3]: d['session_id'] = sys.argv[3]
print(json.dumps(d))
" "$1" "$2" "${3:-}" | (cd "$P" && CLAUDE_PROJECT_DIR="$P" HOME="$H" bash "$HOOK") > "$TMP/out" 2>/dev/null
  python3 -c "
import json, sys
s = open(sys.argv[1]).read().strip()
print(json.loads(s)['hookSpecificOutput']['permissionDecision'] if s else 'allow')
" "$TMP/out" 2>/dev/null || echo "bad-json"
}
bash_cmd() { run_hook Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1")"; }
agent() { run_hook Agent "$1" "${2:-}"; }

echo "== G1 비싼 실행 =="
assert "python3 -m scripts.run_eval → ask" ask "$(bash_cmd 'python3 -m scripts.run_eval --eval-set e.json')"
assert "python -m scripts.run_loop → ask" ask "$(bash_cmd 'python -m scripts.run_loop --max-iterations 3')"
assert "스크립트 경로 run_eval.py → ask" ask "$(bash_cmd 'python3 /x/skill-creator/scripts/run_eval.py --eval-set e.json')"
assert "harness-eval.py run → ask" ask "$(bash_cmd 'python3 scripts/harness-eval.py run --k 3')"
assert "bash -c 안쪽 → ask" ask "$(bash_cmd 'bash -c "python3 -m scripts.run_eval --eval-set e.json"')"
assert "cd … && 뒤쪽 → ask" ask "$(bash_cmd 'cd skills/skill-creator && python3 -m scripts.run_eval --eval-set e.json')"
for c in 'for i in 1 2; do python scripts/run_eval.py; done' 'if true; then python3 -m scripts.run_eval; fi' \
         '{ python scripts/run_eval.py; }' 'echo $(python -m scripts.run_eval)' 'echo `python -m scripts.run_eval`' \
         "bash -lc 'python3 -m scripts.run_eval'" 'uv run python -m scripts.run_eval' 'sudo -n python3 scripts/run_loop.py' \
         'nice -n 5 python3 -m scripts.run_eval' 'timeout -k 5 60 python3 -m scripts.run_eval' \
         'python -W ignore scripts/run_eval.py' 'python -m skill_creator.scripts.run_eval'; do
  assert "리뷰 지적 놓침 사례 → ask: $c" ask "$(bash_cmd "$c")"
done
assert "따옴표 안 괄호 grep → allow" allow "$(bash_cmd 'grep -E "(run_eval|run_loop)" -r .')"
assert "--dry-run → allow" allow "$(bash_cmd 'python3 scripts/harness-eval.py run --dry-run')"
assert "--help → allow" allow "$(bash_cmd 'python3 -m scripts.run_eval --help')"
assert "grep 이 이름을 다루기만 → allow" allow "$(bash_cmd 'grep -rn "scripts.run_eval" .')"
assert "cat → allow" allow "$(bash_cmd 'cat scripts/run_loop.py')"
assert "git diff → allow" allow "$(bash_cmd 'git diff scripts/harness-eval.py')"
assert "일반 python → allow" allow "$(bash_cmd 'python3 scripts/hermes-sync.py status')"
bash_cmd 'python3 -m scripts.run_eval' >/dev/null
assert "ask 사유에 '호출 수'" 0 "$(grep -q '호출 수' "$TMP/out"; echo $?)"

echo "== G2 서브에이전트 모델 =="
assert "general-purpose + model 없음 → deny" deny "$(agent '{"subagent_type":"general-purpose","prompt":"x"}')"
assert "deny 사유에 'model'" 0 "$(grep -q 'model' "$TMP/out"; echo $?)"
assert "general-purpose + model sonnet → allow" allow "$(agent '{"subagent_type":"general-purpose","model":"sonnet","prompt":"x"}')"
assert "subagent_type 없음 → deny" deny "$(agent '{"prompt":"x"}')"
assert "Explore(내장) → deny" deny "$(agent '{"subagent_type":"Explore","prompt":"x"}')"
assert "프로젝트 정의 planner-lite(sonnet) → allow" allow "$(agent '{"subagent_type":"planner-lite","prompt":"x"}')"
assert "프로젝트 정의에 model 없음 → deny" deny "$(agent '{"subagent_type":"no-model","prompt":"x"}')"
assert "전역 정의 g-agent(haiku) → allow" allow "$(agent '{"subagent_type":"g-agent","prompt":"x"}')"
assert "플러그인 plug:p-agent(opus) → allow" allow "$(agent '{"subagent_type":"plug:p-agent","prompt":"x"}')"
mkdir -p "$P/.claude/agents/review"
printf -- '---\nname: sec-review\nmodel: sonnet\n---\n' > "$P/.claude/agents/review/security.md"
assert "하위 폴더 + name 이 파일 이름과 다름 → allow" allow "$(agent '{"subagent_type":"sec-review","prompt":"x"}')"
mkdir -p "$H/plug/agents/sub"; printf -- '---\nname: deep\nmodel: haiku\n---\n' > "$H/plug/agents/sub/deep.md"
assert "플러그인 하위 폴더 plug:deep → allow" allow "$(agent '{"subagent_type":"plug:deep","prompt":"x"}')"
assert "CLAUDE_CODE_SUBAGENT_MODEL 설정 → allow" allow "$(CLAUDE_CODE_SUBAGENT_MODEL=haiku agent '{"subagent_type":"general-purpose","prompt":"x"}')"
assert "없는 타입 → deny" deny "$(agent '{"subagent_type":"nope","prompt":"x"}')"
assert "fork → allow" allow "$(agent '{"subagent_type":"fork","prompt":"x"}')"

echo "== G3 세션 누적 수 =="
M='{"subagent_type":"general-purpose","model":"haiku","prompt":"x"}'
for i in 1 2 3 4 5 6; do agent "$M" s-a >/dev/null; done
assert "7번째 → allow" allow "$(agent "$M" s-a)"
assert "8번째 → ask" ask "$(agent "$M" s-a)"
assert "9번째 → allow" allow "$(agent "$M" s-a)"
for i in 10 11 12 13 14 15; do agent "$M" s-a >/dev/null; done
assert "16번째 → ask" ask "$(agent "$M" s-a)"
agent '{"subagent_type":"general-purpose","prompt":"x"}' s-b >/dev/null   # G2 deny — 세지 않는다
for i in 1 2 3 4 5 6; do agent "$M" s-b >/dev/null; done
assert "G2 에 막힌 호출은 세지 않음(7번째 → allow)" allow "$(agent "$M" s-b)"
assert "session_id 없음 → allow" allow "$(agent "$M")"
agent "$M" '../../evil' >/dev/null
assert "session_id 의 ../ 로 프로젝트 밖에 쓰지 않음" 0 "$(find "$TMP" -maxdepth 2 -name 'evil*' | wc -l)"
echo 'HARNESS_AGENT_ASK_AT=3' > "$P/.harnessrc"
agent "$M" s-c >/dev/null; agent "$M" s-c >/dev/null
assert ".harnessrc 3 → 3번째 ask" ask "$(agent "$M" s-c)"
echo 'HARNESS_AGENT_ASK_AT=abc' > "$P/.harnessrc"
for i in 1 2 3 4 5 6 7; do agent "$M" s-d >/dev/null; done
assert "값 abc → 기본 8(8번째 ask)" ask "$(agent "$M" s-d)"

echo "== 끔 스위치·관측 =="
echo 'HARNESS_COST_GUARD=off' > "$P/.harnessrc"
assert "HARNESS_COST_GUARD=off → allow" allow "$(agent '{"subagent_type":"general-purpose","prompt":"x"}')"
assert "off 에서 run_eval → allow" allow "$(bash_cmd 'python3 -m scripts.run_eval')"
rm -f "$P/.harnessrc"
assert "R-cost 이벤트 기록" 0 "$(grep -q '"R-cost"' "$P/.harness/gate-events.jsonl" 2>/dev/null; echo $?)"

echo "== G7 에이전트 정의는 모델을 갖는다 =="
assert "assets/agents/*.md 전부 model:" "" "$(grep -L '^model:' "$REPO_ROOT"/assets/agents/*.md)"

echo
echo "결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
