#!/usr/bin/env bash
# 사용자 성향 Step 3 — 점수·세 갈래 판정(자동 활성 / 승인 때 질문 / 쌓기만)·합치기 분류.
# 원칙: 스스로 정할 수 있는 것은 묻지 않는다. 애매한 것만 묻는다.
# 근거: docs/exec-plans/completed/2026-09-22-user-persona-distill-plan.md 목표 3 · §6
#
# 실행: bash tests/hermes-persona-score-test.sh
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
import importlib.util, sys
from datetime import datetime, timedelta, timezone
spec = importlib.util.spec_from_file_location("sc", sys.argv[1] + "/scripts/hermes_persona_score.py")
sc = importlib.util.module_from_spec(spec); spec.loader.exec_module(sc)
now = datetime(2026, 9, 22, tzinfo=timezone.utc)
def ob(tier, sid, days, facet="workflow"):
    return {"tier": tier, "session_id": sid, "facet": facet,
            "observed_at": (now - timedelta(days=days)).isoformat()}

print("old_once:", sc.classify_key([ob("t2", "a", 60)], now))
print("inferred_2s:", sc.classify_key([ob("t2", "a", 1), ob("t1", "b", 2)], now))
print("explicit_2s:", sc.classify_key([ob("t0", "a", 1), ob("t2", "b", 2)], now))
print("explicit_1s:", sc.classify_key([ob("t0", "a", 1)], now))
print("same_session_x5:", sc.classify_key([ob("t2", "a", 1)] * 5, now))
print("explicit_2s_stale:", sc.classify_key([ob("t0", "a", 120), ob("t0", "b", 121)], now))
slow = sc.score_key([ob("t2", "a", 60, facet="stack")], now)
fast = sc.score_key([ob("t2", "a", 60, facet="workflow")], now)
print("env_decays_slower:", slow > fast)
print("t0_counts_double:", abs(sc.score_key([ob("t0", "a", 0)], now) - 2 * sc.score_key([ob("t2", "a", 0)], now)) < 1e-9)

keys = [("communication", "clarification-seeking", "모르면 묻는다"),
        ("communication", "clarification-seeking-direct", "모르는 말은 묻는다"),
        ("workflow", "commit-without-asking", "묻지 않고 커밋"),
        ("workflow", "commit-after-asking", "묻고 커밋"),
        ("workflow", "token-efficiency-priority", "토큰 효율"),
        ("workflow", "security-integrity-priority", "보안 우선"),
        ("directives", "clarification-seeking", "다른 면의 같은 키")]
pairs = {(a, b): v for a, b, v in sc.merge_pairs(keys)}
print("prefix_auto:", pairs.get(("communication/clarification-seeking", "communication/clarification-seeking-direct")))
print("opposite_ask:", pairs.get(("workflow/commit-after-asking", "workflow/commit-without-asking")))
print("different_none:", ("workflow/security-integrity-priority", "workflow/token-efficiency-priority") in pairs)
print("cross_facet_none:", any("directives/" in a or "directives/" in b for a, b in pairs))
EOF
)
echo "$out" | sed 's/^/    /'

echo "== 1. 세 갈래 판정 =="
assert "오래전 한 번 → 쌓기만(묻지 않음)"                "old_once: hold"          "$(echo "$out" | sed -n 1p)"
assert "추론만 2세션 → 승인 때 질문"                      "inferred_2s: ask"        "$(echo "$out" | sed -n 2p)"
assert "직접 말한 지시 + 2세션 → 자동 활성"               "explicit_2s: auto"       "$(echo "$out" | sed -n 3p)"
assert "직접 말했어도 1세션 → 쌓기만"                     "explicit_1s: hold"       "$(echo "$out" | sed -n 4p)"
assert "한 세션에서 다섯 번은 한 번으로 센다"             "same_session_x5: hold"   "$(echo "$out" | sed -n 5p)"
assert "넉 달 전 지시는 식어서 자동 활성이 아니다"        "explicit_2s_stale: hold" "$(echo "$out" | sed -n 6p)"
echo "== 2. 점수 =="
assert "환경·스택은 말투·방식보다 천천히 식는다"          "env_decays_slower: True" "$(echo "$out" | sed -n 7p)"
assert "직접 말한 지시는 두 배로 센다"                    "t0_counts_double: True"  "$(echo "$out" | sed -n 8p)"
echo "== 3. 합치기 분류 =="
assert "키 접두어 일치 → 자동 병합"                        "prefix_auto: auto"       "$(echo "$out" | sed -n 9p)"
assert "비슷하지만 뜻이 반대일 수 있는 쌍(0.75) → 질문"    "opposite_ask: ask"       "$(echo "$out" | sed -n 10p)"
assert "다른 성향(0.50) → 합치지도 묻지도 않는다"          "different_none: False"   "$(echo "$out" | sed -n 11p)"
assert "면이 다르면 같은 키여도 합치지 않는다"             "cross_facet_none: False" "$(echo "$out" | sed -n 12p)"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
