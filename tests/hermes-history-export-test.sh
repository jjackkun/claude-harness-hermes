#!/usr/bin/env bash
# session_history → .hermes/history/*.jsonl export 검증 (HOME 격리)
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$REPO_ROOT/scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/fakehome"; mkdir -p "$HOME"
PROJ="$T/proj"; DB="$PROJ/.hermes/state.db"
PASS=0; FAIL=0
assert() { local d="$1" e="$2" a="$3"
  if [[ "$e" == "$a" ]]; then echo "  ✓ $d"; PASS=$((PASS+1))
  else echo "  ✗ $d (expected='$e' actual='$a')"; FAIL=$((FAIL+1)); fi }

python3 "$S/hermes-init.py" --both "$PROJ" >/dev/null 2>&1
SID="11111111-2222-3333-4444-555555555555"
python3 - "$DB" "$SID" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1]); sid = sys.argv[2]
rows = [("첫 질문","user"),("첫 답변","assistant"),("둘째 질문","user")]
for c, r in rows:
    con.execute("INSERT INTO session_history (content, role, timestamp, project_id, session_id) VALUES (?,?,?,?,?)",
                (c, r, "2026-07-21T10:00:00.000000", "proj", sid))
con.commit()
PY

echo "== 1. export 산출물 =="
python3 "$S/hermes-export-history.py" --db "$DB" --project "$PROJ" --session "$SID" >/dev/null 2>&1
f="$(ls "$PROJ/.hermes/history/"*"$SID".jsonl 2>/dev/null | head -1)"
assert "history 파일 1개 생성" 1 "$(ls "$PROJ/.hermes/history/" 2>/dev/null | wc -l)"
assert "행 수 = JSONL 라인 수" 3 "$(wc -l < "$f" 2>/dev/null || echo 0)"

echo "== 2. seq 부여 + 순서 보존 =="
out="$(python3 - "$f" <<'PY'
import json, sys
lines=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()]
print("OK" if [l["seq"] for l in lines]==list(range(len(lines))) and [l["role"] for l in lines]==["user","assistant","user"] else "BAD")
PY
)"
assert "seq 0..N-1 + 대화 순서 보존" "OK" "$out"

echo "== 3. 멱등 — 재실행해도 파일 1개, 라인 중복 없음 =="
python3 "$S/hermes-export-history.py" --db "$DB" --project "$PROJ" --session "$SID" >/dev/null 2>&1
assert "재실행 후에도 파일 1개" 1 "$(ls "$PROJ/.hermes/history/" 2>/dev/null | wc -l)"
assert "재실행 후에도 3줄" 3 "$(wc -l < "$(ls "$PROJ/.hermes/history/"*.jsonl 2>/dev/null | head -1)" 2>/dev/null || echo 0)"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
