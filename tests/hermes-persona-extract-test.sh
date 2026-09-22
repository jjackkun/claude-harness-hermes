#!/usr/bin/env bash
# 사용자 성향 추출 Step 2 — 발화 묶음 → 마스킹 → claude -p → 관찰 검증.
#
# 핵심: 모델이 준 인용(quote)이 **그 발화 안에 글자 그대로** 있어야 관찰로 받는다.
# 지어낸 성향이 사실처럼 쌓이는 것을 막는 장치다. 실제 LLM 은 부르지 않는다 — 실행기를 바꿔 끼운다.
# 근거: docs/exec-plans/completed/2026-09-22-user-persona-distill-plan.md 목표 2·5
#
# 실행: bash tests/hermes-persona-extract-test.sh
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

out=$(python3 - "$REPO_ROOT" <<'EOF'
import importlib.util, json, sys
sys.path.insert(0, sys.argv[1] + "/scripts")
spec = importlib.util.spec_from_file_location("ex", sys.argv[1] + "/scripts/hermes_persona_extract.py")
ex = importlib.util.module_from_spec(spec); spec.loader.exec_module(ex)

utts = [{"text": "폼 질문을 연달아 띄우지 마", "line": 1},
        {"text": "연락처는 010-1234-5678 로 줘", "line": 2},
        {"text": "x" * 5000, "line": 3}]

# 1. 묶기: 발화 하나는 상한까지 자르고, 묶음은 입력 상한을 넘지 않는다
batches = ex.build_batches(utts)
print("batches:", len(batches), "max_utt:", max(len(u["text"]) for b in batches for u in b) <= ex.UTTERANCE_MAX_CHARS)
print("batch_cap:", all(sum(len(u["text"]) for u in b) <= ex.BATCH_MAX_CHARS for b in batches))

# 2. 마스킹: 모델에 가는 프롬프트에 전화번호가 없다
prompt = ex.build_prompt(batches[0], known_keys=[("workflow", "no-form-spam", "폼 질문을 연달아 띄우지 않는다")])
print("phone_masked:", "010-1234-5678" not in prompt and "[REDACTED:PHONE]" in prompt)
print("keys_in_prompt:", "no-form-spam" in prompt)

# 3. 검증: 인용이 발화에 없으면 버리고, 면·등급이 틀려도 버린다
reply = json.dumps([
  {"n": 1, "facet": "workflow", "key": "no-form-spam", "statement": "폼 질문을 연달아 띄우지 않는다", "quote": "연달아 띄우지 마", "tier": "t1"},
  {"n": 1, "facet": "workflow", "key": "made-up", "statement": "지어낸 성향", "quote": "이런 말은 한 적 없다", "tier": "t1"},
  {"n": 1, "facet": "hobby", "key": "x", "statement": "없는 면", "quote": "폼 질문", "tier": "t1"},
  {"n": 1, "facet": "workflow", "key": "y", "statement": "없는 등급", "quote": "폼 질문", "tier": "t9"},
  {"n": 9, "facet": "workflow", "key": "z", "statement": "없는 발화 번호", "quote": "폼", "tier": "t2"},
], ensure_ascii=False)
obs = ex.parse_observations("```json\n" + reply + "\n```", batches[0])
print("kept:", len(obs), obs[0]["key"] if obs else "-", obs[0]["line"] if obs else "-")
wrapped = "다음은 추출한 성향입니다:\n\n```json\n" + reply + "\n```\n\n참고: 5번은 애매합니다."
print("wrapped:", len(ex.parse_observations(wrapped, batches[0]) or []))

# 4. 실행: 가짜 실행기 — 실패는 None, 성향 없음은 빈 목록, 성공은 검증된 관찰
class R:
    def __init__(self, rc, out): self.returncode, self.stdout = rc, out
calls = []
def ok(cmd, **kw): calls.append(cmd); return R(0, reply)
def bad(cmd, **kw): return R(1, "")
print("run_ok:", len(ex.extract_observations(batches[0], [], run=ok)))
print("model:", "claude-haiku-4-5-20251001" in calls[0], "argv0:", calls[0][0])
print("run_fail:", ex.extract_observations(batches[0], [], run=bad))
print("run_garbage:", ex.extract_observations(batches[0], [], run=lambda c, **k: R(0, "모르겠다")))
print("run_empty:", ex.extract_observations(batches[0], [], run=lambda c, **k: R(0, "[]")))
import io, contextlib, subprocess
def slow(cmd, **kw): raise subprocess.TimeoutExpired(cmd, kw.get("timeout"))
err = io.StringIO()
with contextlib.redirect_stderr(err):
    ex.extract_observations(batches[0], [], run=slow)
print("log_no_prompt:", "폼 질문" not in err.getvalue() and "timeout" in err.getvalue().lower())
EOF
)
echo "$out" | sed 's/^/    /'

echo "== 1. 묶기 =="
assert "긴 발화도 상한 안에서 잘린다" "batches: 1 max_utt: True" "$(echo "$out" | sed -n 1p)"
assert "묶음이 입력 상한을 넘지 않는다" "batch_cap: True" "$(echo "$out" | sed -n 2p)"
echo "== 2. 마스킹 (목표 5) =="
assert "프롬프트에 전화번호 원문이 없다" "phone_masked: True" "$(echo "$out" | sed -n 3p)"
assert "이미 있는 성향 키를 함께 준다" "keys_in_prompt: True" "$(echo "$out" | sed -n 4p)"
echo "== 3. 검증 — 지어낸 인용·없는 면·없는 등급·없는 번호는 버린다 =="
assert "5개 중 1개만 남는다" "kept: 1 no-form-spam 1" "$(echo "$out" | sed -n 5p)"
assert "앞뒤에 설명 글이 붙어도 배열을 찾아 읽는다 (실측 2026-09-22)" "wrapped: 1" "$(echo "$out" | sed -n 6p)"
echo "== 4. 실행기 =="
assert "성공 응답이면 검증된 관찰" "run_ok: 1" "$(echo "$out" | sed -n 7p)"
assert "구독 CLI + haiku 로 부른다 (R3)" "model: True argv0: claude" "$(echo "$out" | sed -n 8p)"
assert "호출 실패는 None — 성향 없음(빈 목록)과 구분한다" "run_fail: None" "$(echo "$out" | sed -n 9p)"
assert "JSON 이 아닌 응답도 실패(None) — 다음에 다시 읽는다" "run_garbage: None" "$(echo "$out" | sed -n 10p)"
assert "진짜로 성향이 없으면 빈 목록" "run_empty: []" "$(echo "$out" | sed -n 11p)"
assert "시간 초과 로그에 발화(프롬프트)를 싣지 않는다" "log_no_prompt: True" "$(echo "$out" | sed -n 12p)"

echo "== 5. 성향 표는 기억 운반(sync)에 실리지 않는다 (목표 5) =="
hits=$(grep -l -E 'persona|global\.db' "$REPO_ROOT"/scripts/hermes-sync.py "$REPO_ROOT"/scripts/hermes_sync_*.py 2>/dev/null | wc -l | tr -d ' ')
assert "sync 코드가 성향 표·global.db 를 참조하지 않는다" "0" "$hits"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
