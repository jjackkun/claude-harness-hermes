#!/usr/bin/env bash
# 구독 CLI 에 프롬프트를 argv 가 아니라 stdin 으로 넘기는지 정적으로 지킨다.
#
# 왜: argv 는 호출이 도는 동안(최대 180초) 같은 컴퓨터의 다른 프로세스가 `ps`·`/proc/<pid>/cmdline` 으로 본다.
# 프롬프트에는 (마스킹된) 사람 발화·세션 요약·작업 지시가 들어 있다. 또 `-p` 인자와 stdin 을 둘 다 주면
# CLI 는 둘을 이어 붙인다(2026-09-22 실측) — stdin 을 명시하지 않으면 부모의 stdin 이 프롬프트에 섞일 수 있다.
# 근거: docs/exec-plans/completed/2026-09-22-cli-prompt-via-stdin-plan.md
#
# 실행: bash tests/cli-prompt-stdin-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# `"-p",`·`'-p',` 바로 뒤가 문자열이 아닌 값(변수·첨자)이면 프롬프트를 argv 에 실은 것이다.
# 제외: harness-eval.py(고정 시나리오 문장 — 계획 §3 비목표) · hermes_sync_ref.py(`-p` 는 git 부모 커밋 옵션).
hits=$(grep -nE "[\"']-p[\"'],[[:space:]]*[A-Za-z_(]" "$REPO_ROOT"/scripts/*.py \
       | grep -v -E '/harness-eval\.py:|/hermes_sync_ref\.py:' || true)
echo "$hits" | sed '/^$/d; s/^/    /'
assert "파이썬 호출이 프롬프트를 argv 에 싣지 않는다" "0" "$(echo "$hits" | sed '/^$/d' | wc -l | tr -d ' ')"

CRON="$REPO_ROOT/scripts/hermes-cron-run.sh"
assert "cron 러너도 프롬프트를 argv 에 싣지 않는다" "0" "$(grep -cE 'claude -p "\$prompt"' "$CRON")"
assert "cron 러너는 프롬프트를 stdin 으로 넘긴다" "1" "$(grep -cE "printf '%s' \"\\\$prompt\" \\| nohup claude -p" "$CRON")"

# 호출을 바꾼 곳은 input= 으로 stdin 을 **명시**한다 — 빠지면 부모 stdin 을 물려받는다.
for f in hermes-crystallize.py hermes-summon.py hermes-loop.py hermes-summarize.py hermes-evolve-skill.py \
         hermes-lifecycle.py hermes_mesh_gate.py hermes-dream.py hermes_search_fallback.py hermes_persona_extract.py; do
  assert "$f 는 input= 으로 프롬프트를 준다" "yes" "$(grep -q 'input=' "$REPO_ROOT/scripts/$f" && echo yes || echo no)"
done

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
