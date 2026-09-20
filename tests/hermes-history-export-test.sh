#!/usr/bin/env bash
# session_history → .hermes/history/<session_id>/<순번>.jsonl **턴 조각** export 검증 (HOME 격리)
#
# 2026-09-16: 세션당 파일 하나를 매 턴 전량 재작성하던 방식에서 추가 전용 조각으로 바뀌었다.
# 근거: docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 1·2
#   - 원문은 코드 브랜치에 커밋하지 않는다(gitignore 예외 제거) → 4절
#   - 조각은 한 번 쓰면 바뀌지 않는다 → 3절
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$REPO_ROOT/scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/fakehome"; mkdir -p "$HOME"
PROJ="$T/proj"; DB="$PROJ/.hermes/state.db"
PASS=0; FAIL=0
assert() { local d="$1" e="$2" a="$3"
  if [[ "$e" == "$a" ]]; then echo "  ✓ $d"; PASS=$((PASS+1))
  else echo "  ✗ $d (expected='$e' actual='$a')"; FAIL=$((FAIL+1)); fi }

# 조각 도우미 — 인자 없는 cat/md5sum 이 stdin 을 기다리지 않도록 항상 파일 존재를 확인한다
frags() { ls "$1/.hermes/history/$2/"*.jsonl 2>/dev/null || true; }
frag_count() { frags "$1" "$2" | grep -c . || true; }
frag_lines() { local fs; fs="$(frags "$1" "$2")"; if [[ -n "$fs" ]]; then cat $fs | grep -c . ; else echo 0; fi }
first_frag() { frags "$1" "$2" | head -1; }
md5of() { if [[ -n "${1:-}" && -f "${1:-}" ]]; then md5sum "$1" | awk '{print $1}'; else echo none; fi }
rows_in() { python3 -c "
import sqlite3,sys
q='SELECT COUNT(*) FROM session_history' + (\" WHERE session_id='%s'\" % sys.argv[2] if len(sys.argv)>2 else '')
print(sqlite3.connect(sys.argv[1]).execute(q).fetchone()[0])" "$@"; }

python3 "$S/hermes-init.py" --both "$PROJ" >/dev/null 2>&1
SID="11111111-2222-3333-4444-555555555555"
add_rows() { python3 - "$1" "$2" "$3" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1]); sid = sys.argv[2]
pairs = [("첫 질문","user"),("첫 답변","assistant"),("둘째 질문","user")] if sys.argv[3] == "base" \
        else [("이어간 답변","assistant")]
for c, r in pairs:
    con.execute("INSERT INTO session_history (content, role, timestamp, project_id, session_id)"
                " VALUES (?,?,?,?,?)", (c, r, "2026-07-21T10:00:00.000000", "proj", sid))
con.commit()
PY
}
add_rows "$DB" "$SID" base

echo "== 1. export 산출물은 조각 하나 =="
python3 "$S/hermes-export-history.py" --db "$DB" --project "$PROJ" --session "$SID" >/dev/null 2>&1
assert "조각 1개 생성" 1 "$(frag_count "$PROJ" "$SID")"
assert "행 수 = 조각 줄 수" 3 "$(frag_lines "$PROJ" "$SID")"
assert "조각 이름은 순번 4자리" "0000.jsonl" "$(basename "$(first_frag "$PROJ" "$SID")")"

echo "== 2. seq 부여 + 순서 보존 =="
assert "seq 0..N-1 + 대화 순서 보존" "OK" "$(python3 - "$(first_frag "$PROJ" "$SID")" <<'PY'
import json, sys
lines=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()]
print("OK" if [l["seq"] for l in lines]==list(range(len(lines)))
      and [l["role"] for l in lines]==["user","assistant","user"] else "BAD")
PY
)"

echo "== 3. 추가 전용 — 새 줄만 새 조각으로 (목표 2) =="
python3 "$S/hermes-export-history.py" --db "$DB" --project "$PROJ" --session "$SID" >/dev/null 2>&1
assert "새 줄이 없으면 조각도 늘지 않는다" 1 "$(frag_count "$PROJ" "$SID")"
before_md5="$(md5of "$(first_frag "$PROJ" "$SID")")"
add_rows "$DB" "$SID" more
python3 "$S/hermes-export-history.py" --db "$DB" --project "$PROJ" --session "$SID" >/dev/null 2>&1
assert "새 줄이 생기면 조각이 하나 는다" 2 "$(frag_count "$PROJ" "$SID")"
assert "기존 조각은 바이트 불변" "$before_md5" "$(md5of "$(first_frag "$PROJ" "$SID")")"
assert "조각 전체 4줄(중복 없음)" 4 "$(frag_lines "$PROJ" "$SID")"
assert "새 조각의 seq 는 3부터" 3 "$(python3 -c "
import json,sys
print(json.loads(open(sys.argv[1],encoding='utf-8').readline())['seq'])" "$(frags "$PROJ" "$SID" | tail -1)")"

echo "== 4. gitignore: 원문 조각은 커밋되지 않는다 (목표 1) =="
command -v log_info >/dev/null 2>&1 || log_info() { :; }
source "$REPO_ROOT/lib/harness_installers.sh"
GP="$T/gitproj"; mkdir -p "$GP/.hermes/history/sess-1"
( cd "$GP" && git init -q )
printf '{"seq":0}\n' > "$GP/.hermes/history/sess-1/0000.jsonl"
GITIGNORE_ENTRIES=(); source "$REPO_ROOT/presets/workflow/hermes.conf" >/dev/null 2>&1 || true
install_harness_gitignore "$GP" "claude"
if ( cd "$GP" && git check-ignore -q .hermes/history/sess-1/0000.jsonl ); then ig=1; else ig=0; fi
assert "새 조각은 무시된다(원문이 코드 브랜치로 안 나간다)" 1 "$ig"
# 대조 단언 — conf 로드 실패로 GITIGNORE_ENTRIES 가 비면 위 단언이 가짜로 통과한다
# git 2.25 의 check-ignore 는 부정 패턴(!…)에 맞아도 exit 0 을 돌려준다 — -v 로 맞은 패턴을 보고 '!' 로 시작하면 추적으로 읽는다(roster 테스트와 같은 방식, 2026-09-20).
_ignored() { local m; m="$(cd "$1" && git check-ignore -v "$2" 2>/dev/null | awk -F'\t' '{print $1}' | sed -E 's/^[^:]*:[0-9]+://')"; [[ -n "$m" && "${m:0:1}" != "!" ]]; }
if _ignored "$GP" .hermes/factory.json; then ig2=1; else ig2=0; fi
assert "대조: factory.json 은 예외로 추적된다(conf 로드 증명)" 0 "$ig2"

echo "== 5. 재색인: 빈 DB + 조각 → session_history 복원 =="
PROJ2="$T/proj2"; DB2="$PROJ2/.hermes/state.db"
python3 "$S/hermes-init.py" --both "$PROJ2" >/dev/null 2>&1
mkdir -p "$PROJ2/.hermes/history"
cp -r "$PROJ/.hermes/history/$SID" "$PROJ2/.hermes/history/"
assert "사전: 빈 DB" 0 "$(rows_in "$DB2")"
python3 "$S/hermes-reindex.py" --db "$DB2" --project "$PROJ2" >/dev/null 2>&1
assert "재색인 후 4행 복원" 4 "$(rows_in "$DB2")"
assert "대화 순서 복원(seq 순)" "user,assistant,user,assistant" "$(python3 -c "
import sqlite3;print(','.join(r[0] for r in sqlite3.connect('$DB2').execute(
  \"SELECT role FROM session_history WHERE session_id='$SID'\")))")"

echo "== 5b. 재색인 멱등 — 두 번 돌려도 중복 없음 =="
python3 "$S/hermes-reindex.py" --db "$DB2" --project "$PROJ2" >/dev/null 2>&1
assert "재실행 후에도 4행" 4 "$(rows_in "$DB2")"

echo "== 6. 역-export 보정: DB에만 있는 세션을 조각으로 =="
SID2="99999999-8888-7777-6666-555555555555"
python3 - "$DB2" "$SID2" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("INSERT INTO session_history (content, role, timestamp, project_id, session_id)"
            " VALUES (?,?,?,?,?)", ("DB에만 있는 턴","user","2026-07-21T11:00:00.000000","proj",sys.argv[2]))
con.commit()
PY
python3 "$S/hermes-reindex.py" --db "$DB2" --project "$PROJ2" --backfill >/dev/null 2>&1
assert "역-export 로 조각 생성" 1 "$(frag_count "$PROJ2" "$SID2")"

echo "== 6b. 안전 가드: 손상된 조각이 멀쩡한 DB 를 지우지 않는다 =="
python3 - "$(first_frag "$PROJ2" "$SID")" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
lines[1] = '{"seq":1,"role":"assist'          # 의도적 파손(JSON 미완결)
open(sys.argv[1], "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
python3 "$S/hermes-reindex.py" --db "$DB2" --project "$PROJ2" >/dev/null 2>&1
assert "손상 세션은 스킵 — DB 4행 보존(순손실 없음)" 4 "$(rows_in "$DB2" "$SID")"

echo "== 7. 재색인 자동 트리거: 조각이 DB보다 많으면 SessionStart 가 재색인 =="
GUARD="$REPO_ROOT/assets/hooks/claude-sessionstart-history-reindex.sh"
PROJ3="$T/proj3"; DB3="$PROJ3/.hermes/state.db"
python3 "$S/hermes-init.py" --both "$PROJ3" >/dev/null 2>&1
mkdir -p "$PROJ3/.hermes/history"
cp -r "$PROJ/.hermes/history/$SID" "$PROJ3/.hermes/history/"   # 조각만 있고 DB 는 빈 상태
out3="$(echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$PROJ3" bash "$GUARD")"
assert "훅 stdout 무출력(컨텍스트 오염 방지)" "" "$out3"
for _ in $(seq 1 30); do
  [[ "$(rows_in "$DB3")" != "0" ]] && break
  sleep 0.5
done
assert "재색인이 자동 실행되어 행 복원" 4 "$(rows_in "$DB3")"

echo "== 8. 이어간 세션 감지: 새 조각이 도착하면 재색인 =="
# 다른 컴퓨터에서 이어간 세션은 **새 조각**으로 온다(같은 파일을 고치지 않는다).
python3 - "$PROJ3/.hermes/history/$SID/0002.jsonl" "$SID" <<'PY'
import json, sys
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(
    {"seq":4,"session_id":sys.argv[2],"project_id":"proj","role":"assistant",
     "timestamp":"2026-07-21T10:00:04.000000","content":"다른 컴퓨터에서 이어간 답변"},
    ensure_ascii=False) + "\n")
PY
assert "사전: 조각 3개" 3 "$(frag_count "$PROJ3" "$SID")"
out8="$(echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$PROJ3" bash "$GUARD")"
assert "훅 stdout 무출력(컨텍스트 오염 방지)" "" "$out8"
for _ in $(seq 1 30); do
  [[ "$(rows_in "$DB3" "$SID")" == "5" ]] && break
  sleep 0.5
done
assert "이어간 세션이 재색인되어 4→5 행 증가" 5 "$(rows_in "$DB3" "$SID")"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
