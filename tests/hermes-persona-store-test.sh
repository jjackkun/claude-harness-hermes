#!/usr/bin/env bash
# 사용자 성향 표 — 관찰 저장. 근거 인용이 없으면 거부한다.
# 근거: docs/exec-plans/active/2026-09-22-user-persona-distill-plan.md 목표 2
#
# 실행: bash tests/hermes-persona-store-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

out=$(python3 - "$REPO_ROOT" "$TMP/g.db" <<'EOF'
import importlib.util, sqlite3, sys
spec = importlib.util.spec_from_file_location("st", sys.argv[1] + "/scripts/hermes_persona_store.py")
st = importlib.util.module_from_spec(spec); spec.loader.exec_module(st)
con = sqlite3.connect(sys.argv[2]); st.ensure_schema(con)
base = {"facet": "workflow", "key": "no-form-spam", "statement": "폼 질문을 연달아 띄우지 않는다",
        "tier": "t1", "source_path": "/p/a.jsonl", "line": 3, "session_id": "s1",
        "observed_at": "2026-09-22T01:00:00Z"}
st.add_observation(con, {**base, "quote": "연달아 띄우지 마"})
for bad in ({**base, "quote": ""}, {**base, "quote": "   "}, {k: v for k, v in base.items()}):
    try:
        st.add_observation(con, bad); print("accepted")
    except ValueError:
        print("rejected")
st.add_observation(con, {**base, "quote": "또 폼이야", "line": 9})
print("rows:", con.execute("SELECT COUNT(*) FROM persona_observation").fetchone()[0])
print("keys:", st.list_keys(con))
EOF
)
assert "빈 인용은 거부" "rejected" "$(echo "$out" | sed -n 1p)"
assert "공백 인용도 거부" "rejected" "$(echo "$out" | sed -n 2p)"
assert "인용 칸이 없어도 거부" "rejected" "$(echo "$out" | sed -n 3p)"
assert "인용 있는 관찰은 저장되고, 같은 키도 여러 줄로 쌓인다 (반복 횟수의 재료)" "rows: 2" "$(echo "$out" | sed -n 4p)"
assert "키 목록은 중복 없이 (면, 키, 문장)" "keys: [('workflow', 'no-form-spam', '폼 질문을 연달아 띄우지 않는다')]" "$(echo "$out" | sed -n 5p)"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
