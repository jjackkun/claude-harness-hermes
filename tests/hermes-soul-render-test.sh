#!/usr/bin/env bash
# 출근 본문의 기억 선별 — "아직 기억 없음" 과 "선별 실패" 를 가른다 (백로그 memory-select-empty-table-warning).
#
#   1 표 없음: state.db 는 있는데 memory_events 가 없다(갓 설치 · 기억 0건) → 경고 0 B · MEMORY.md 파일 폴백
#   2 표 깨짐: memory_events 는 있는데 읽기가 실패한다 → [agent-soul WARN] 기억 선별 실패 1줄 · 파일 폴백
#   3 정상: 기억 1건 → 선별 본문(머리 "기억 (선별") · 경고 0 B
#
# 실행: bash tests/hermes-soul-render-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

AID="01a0ae58-6aa6-7202-ae81-7d27af7b5617"
fixture() {   # $1 = 프로젝트 경로. 명부 1명 · MEMORY.md 파일 · 빈 state.db
  local p="$1"
  mkdir -p "$p/.hermes/agents/$AID"
  printf '{"agents":[{"agent_id":"%s","name":"게이트QA","slug":"gate-qa","status":"active"}]}' "$AID" > "$p/.hermes/agents.json"
  printf '# 파일 기억\n- 파일에서 온 문장\n' > "$p/.hermes/agents/$AID/MEMORY.md"
  python3 -c "import sqlite3,sys; sqlite3.connect(sys.argv[1]).execute('CREATE TABLE IF NOT EXISTS other(x)')" "$p/.hermes/state.db"
}
render() {    # $1 = 프로젝트. stdout → $1/out, stderr → $1/err
  python3 "$S/hermes_soul_render.py" "$1" "$AID" > "$1/out" 2> "$1/err"
}

echo "1 표 없음 — 경고 없이 파일 폴백"
P1="$T/p1"; fixture "$P1"; render "$P1"
assert "stderr 0 B" 0 "$(wc -c < "$P1/err")"
assert "MEMORY.md 파일 본문이 실린다" 1 "$(has "$(cat "$P1/out")" "파일에서 온 문장")"

echo "2 표 깨짐 — 지금처럼 경고 1줄 + 파일 폴백"
P2="$T/p2"; fixture "$P2"
python3 -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('CREATE TABLE memory_events(x)'); c.commit()" "$P2/.hermes/state.db"
render "$P2"
assert "WARN 1줄" 1 "$(grep -c '\[agent-soul WARN\] 기억 선별 실패' "$P2/err")"
assert "MEMORY.md 파일 본문이 실린다" 1 "$(has "$(cat "$P2/out")" "파일에서 온 문장")"

echo "3 정상 — DB 선별 본문 · 경고 없음"
P3="$T/p3"; fixture "$P3"
python3 - "$P3/.hermes/state.db" "$AID" "$S" <<'PY'
import sqlite3, sys
sys.path.insert(0, sys.argv[3])
from hermes_memory_events import record
con = sqlite3.connect(sys.argv[1])
record(con, {"memory_id": "m1", "kind": "memory.added", "agent_id": sys.argv[2], "universe_id": "u1",
             "ts": "2026-10-03T00:00:00Z", "body": "DB 에서 온 문장"})
PY
render "$P3"
assert "stderr 0 B" 0 "$(wc -c < "$P3/err")"
assert "선별 본문 머리" 1 "$(has "$(cat "$P3/out")" "기억 (선별 1/1")"
assert "DB 기억 문장" 1 "$(has "$(cat "$P3/out")" "DB 에서 온 문장")"

echo
echo "결과: $PASS 통과 / $FAIL 실패"
(( FAIL == 0 ))
