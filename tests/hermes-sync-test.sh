#!/usr/bin/env bash
# 운반 계층 검증 (계획 docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 6~11·14·15).
#
#   두 클론 A·B 가 bare 원격 하나를 공유한다.
#   - push: refs/hermes/sync 에 조각·이력·자물쇠가 오르고, 코드 브랜치·작업 트리는 변화 0 (목표 6)
#   - 두 클론이 각자 push 해도 둘 다 올라간다, --force 0 (목표 7)
#   - 열쇠 없는 클론은 H-10 안내를 내고 DB 변경 0, 자물쇠 등록 뒤 pull 로 합류·복호·재색인 (목표 8)
#   - "기억 없음" 3분류가 서로 다른 문구 (목표 9)
#   - backfill 두 번 → 조각 수 동일 (목표 10)
#   - 원격 이력의 자유 글 3칸은 age 암호문, 기계 칸은 평문 (목표 11)
#   - age 없는 컴퓨터에서 훅 exit 0 · 한 줄 알림 · DB 변경 0 (목표 14)
#   - 참조 거부 서버 → "이식 불가 — 사람 판단" (목표 15)
#
# 열쇠는 임시 HOME 에만 만든다. 실행: bash tests/hermes-sync-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}
command -v age >/dev/null 2>&1 || { echo "  ✗ 전제: age 미설치"; echo "PASS=0 FAIL=1"; exit 1; }

BARE="$TMP/bare"; git init -q --bare "$BARE"
mk_clone() {  # <dir> <HOME>
  mkdir -p "$1/scripts/data" "$1/.hermes" "$2"
  cp "$S"/*.py "$S/hermes-keys.sh" "$S/hermes-sync.py" "$1/scripts/"
  cp "$REPO_ROOT/assets/data/bip39-english.txt" "$1/scripts/data/"
  cp "$REPO_ROOT/assets/hooks/claude-sessionstart-sync-pull.sh" "$1/scripts/" 2>/dev/null || true
  git init -q "$1"; git -C "$1" config user.name jjackkun; git -C "$1" config user.email t@t
  git -C "$1" remote add origin "$BARE"
  git -C "$1" commit -q --allow-empty -m init
  python3 "$S/hermes-init.py" --project "$1" >/dev/null 2>&1
  # 기존 절(2~10)은 잠금 모드 + 원문 운반을 검증한다 — T-17 뒤 원문은 옵션이라 명시한다. 기본 정책은 12절이 따로 본다.
  echo '{"push": true, "history": true}' > "$1/.hermes/sync.json"
}
A="$TMP/A"; HA="$TMP/homeA"; B="$TMP/B"; HB="$TMP/homeB"
mk_clone "$A" "$HA"; mk_clone "$B" "$HB"
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$A')"
cp "$A/.hermes/universe.id" "$B/.hermes/"          # clone 으로 받는 커밋 파일을 흉내
UNI="$(cat "$A/.hermes/universe.id")"
SYNC_A() { HOME="$HA" python3 "$A/scripts/hermes-sync.py" --project "$A" "$@"; }
SYNC_B() { HOME="$HB" python3 "$B/scripts/hermes-sync.py" --project "$B" "$@"; }
KEYS_A() { HOME="$HA" bash "$A/scripts/hermes-keys.sh" "$@" --project "$A"; }
KEYS_B() { HOME="$HB" bash "$B/scripts/hermes-keys.sh" "$@" --project "$B"; }
remote_ls() { git -C "$A" fetch -q origin "+refs/hermes/sync:refs/hermes/sync-remote" 2>/dev/null; git -C "$A" ls-tree -r --name-only refs/hermes/sync-remote 2>/dev/null; }
rows() { python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]+'/.hermes/state.db').execute(sys.argv[2]).fetchone()[0])" "$1" "$2" 2>/dev/null || echo err; }

echo "== 1. 없음 3분류 — 저장소 없음 (목표 9) =="
KEYS_A init >/dev/null 2>&1
assert "원격에 저장소 없음 문구" 1 "$(SYNC_A status | grep -c '기억 저장소.*없습니다')"

echo ""
echo "== 2. A push — 조각·이력·자물쇠 (목표 6·11) =="
mkdir -p "$A/.hermes/history/sess-1"
printf '{"seq":0,"session_id":"sess-1","project_id":"p","role":"user","timestamp":"2026-09-16T00:00:00","content":"A 의 대화 원문 첫 줄"}\n' > "$A/.hermes/history/sess-1/0000.jsonl"
HOME="$HA" python3 "$A/scripts/hermes-journal.py" --project "$A" emit --json '{"kind":"task.started","task_id":"t1","intent":"비밀 의도 한 줄","actor":"agent:main"}' >/dev/null
HEAD_BEFORE="$(git -C "$A" rev-parse HEAD)"; WT_BEFORE="$(git -C "$A" status --porcelain | md5sum)"
SYNC_A push >"$TMP/pushA.out" 2>&1
assert "push 종료 코드 0" 0 "$?"
assert "원격에 refs/hermes/sync 존재" 1 "$(git ls-remote "$BARE" refs/hermes/sync | grep -c .)"
assert "코드 브랜치 HEAD 불변" "$HEAD_BEFORE" "$(git -C "$A" rev-parse HEAD)"
assert "작업 트리 변경 0(전후 동일)" "$WT_BEFORE" "$(git -C "$A" status --porcelain | md5sum)"
assert "원격에 조각 1개" 1 "$(remote_ls | grep -c '^history/sess-1/0000\.enc$')"
assert "원격에 이력 1개" 1 "$(remote_ls | grep -cE '^journal/[0-9]{4}/[0-9]{2}/[0-9]{2}/.*\.json$')"
assert "원격에 자물쇠 + 감싼 마스터" 2 "$(remote_ls | grep -c '^keys/jjackkun/')"
assert "조각은 age 암호문" 1 "$(git -C "$A" show refs/hermes/sync-remote:history/sess-1/0000.enc | head -c 21 | grep -c 'age-encryption.org')"
JPATH="$(remote_ls | grep '^journal/')"
assert "이력의 intent 는 age 암호문(J-07)" 1 "$(git -C "$A" show "refs/hermes/sync-remote:$JPATH" | python3 -c "import json,sys;print(1 if json.load(sys.stdin)['intent'].startswith('-----BEGIN AGE ENCRYPTED FILE-----') else 0)")"
assert "이력의 기계 칸(kind)은 평문" task.started "$(git -C "$A" show "refs/hermes/sync-remote:$JPATH" | python3 -c "import json,sys;print(json.load(sys.stdin)['kind'])")"
assert "원문 어디에도 평문 없음" 0 "$(git -C "$A" show refs/hermes/sync-remote:history/sess-1/0000.enc | grep -ac '대화 원문')"
SYNC_A push >"$TMP/pushA2.out" 2>&1
assert "재push 는 올릴 것 없음(멱등)" 1 "$(grep -c '올릴 것 없음' "$TMP/pushA2.out")"

echo ""
echo "== 3. B — 열쇠 없음 → H-10 안내, DB 변경 0 (목표 8·9) =="
DB_B_BEFORE="$(md5sum "$B/.hermes/state.db" | awk '{print $1}')"
SYNC_B pull >"$TMP/pullB.out" 2>&1
assert "pull 종료 코드 0(멈추지 않음)" 0 "$?"
assert "'열쇠가 없습니다' 안내" 1 "$(grep -c '열쇠가 없습니다' "$TMP/pullB.out")"
assert "안내에 조각 수(1건) 포함" 1 "$(grep -c '조각 1건' "$TMP/pullB.out")"
assert "state.db 변경 0" "$DB_B_BEFORE" "$(md5sum "$B/.hermes/state.db" | awk '{print $1}')"
assert "status 도 열쇠 없음 분류" 1 "$(SYNC_B status | grep -c '열쇠가 없습니다')"

echo ""
echo "== 4. B 합류 — 자물쇠 등록 → pull 로 마스터 풀고 조각 복호 (목표 8) =="
# B 는 자기 컴퓨터 자물쇠만 만든다(마스터 없음). 실제로는 age-keygen 을 사람이 세션 밖에서.
mkdir -p "$HB/.hermes/keys/$UNI"; age-keygen -o "$HB/.hermes/keys/$UNI/computer.key" >/dev/null 2>&1
B_LOCK="$(age-keygen -y "$HB/.hermes/keys/$UNI/computer.key")"
KEYS_A add-computer "$B_LOCK" >/dev/null 2>&1      # A 에서 B 자물쇠 등록
SYNC_A push >/dev/null 2>&1                        # 감싼 마스터가 원격으로
SYNC_B pull >"$TMP/pullB2.out" 2>&1
assert "B 가 감싼 마스터를 받아 풀었다" 1 "$(grep -c '감싼 마스터를 받아 풀었습니다' "$TMP/pullB2.out")"
assert "B 마스터 열쇠 생성(0600)" 600 "$(stat -c '%a' "$HB/.hermes/keys/$UNI/master.key")"
assert "B 에 조각이 복호돼 놓임" 1 "$([[ -f "$B/.hermes/history/sess-1/0000.jsonl" ]] && echo 1 || echo 0)"
assert "복호된 조각 내용 동일" "$(cat "$A/.hermes/history/sess-1/0000.jsonl")" "$(cat "$B/.hermes/history/sess-1/0000.jsonl")"
assert "B 이력에 이벤트 적재, intent 평문 복원" "비밀 의도 한 줄" "$(rows "$B" "select intent from journal_events where task_id='t1'")"
assert "sync_cursor 에 받은 경로 기록(조각 1 + 이력 1)" 2 "$(rows "$B" "select count(*) from sync_cursor")"
python3 "$S/hermes-reindex.py" --db "$B/.hermes/state.db" --project "$B" >/dev/null 2>&1
assert "재색인으로 session_history 복원" 1 "$(rows "$B" "select count(*) from session_history where session_id='sess-1'")"
SYNC_B pull >"$TMP/pullB3.out" 2>&1
assert "재pull 은 새 항목 0(멱등)" 1 "$(grep -c '새 항목 0건' "$TMP/pullB3.out")"

echo ""
echo "== 5. 두 클론 동시 push — 둘 다 올라감, --force 0 (목표 7) =="
mkdir -p "$A/.hermes/history/sess-A2" "$B/.hermes/history/sess-B2"
printf '{"seq":0,"session_id":"sess-A2","project_id":"p","role":"user","timestamp":"2026-09-16T01:00:00","content":"A2"}\n' > "$A/.hermes/history/sess-A2/0000.jsonl"
printf '{"seq":0,"session_id":"sess-B2","project_id":"p","role":"user","timestamp":"2026-09-16T01:00:00","content":"B2"}\n' > "$B/.hermes/history/sess-B2/0000.jsonl"
SYNC_A push >/dev/null 2>&1; SYNC_B push >"$TMP/pushB.out" 2>&1
assert "B push(뒤늦은 쪽) 성공" 0 "$?"
assert "원격 트리에 두 조각 모두" 2 "$(remote_ls | grep -cE '^history/sess-(A2|B2)/0000\.enc$')"
assert "push 명령에 --force 없음" 0 "$(grep -c 'push.*--force\|--force.*push' "$S/hermes_sync_ref.py")"
SYNC_A pull >/dev/null 2>&1
assert "A 가 B 조각을 받아 복호" 1 "$([[ -f "$A/.hermes/history/sess-B2/0000.jsonl" ]] && echo 1 || echo 0)"

echo ""
echo "== 6. backfill 멱등 (목표 10) =="
python3 - "$A/.hermes/state.db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
for i in range(3):
    c.execute("INSERT INTO session_history (content, role, timestamp, project_id, session_id) VALUES (?,?,?,?,?)",
              (f"옛 원문 {i}", "user", "2026-09-10T00:00:00", "p", "old-sess"))
c.commit()
PY
SYNC_A backfill >/dev/null 2>&1
N1="$(remote_ls | grep -c '^history/')"; F1="$(find "$A/.hermes/history" -name '*.jsonl' | wc -l)"
SYNC_A backfill >/dev/null 2>&1
assert "두 번 backfill 해도 원격 조각 수 동일" "$N1" "$(remote_ls | grep -c '^history/')"
assert "두 번 backfill 해도 로컬 조각 수 동일" "$F1" "$(find "$A/.hermes/history" -name '*.jsonl' | wc -l)"
assert "old-sess 조각이 원격에 있음" 1 "$(remote_ls | grep -c '^history/old-sess/0000\.enc$')"

echo ""
echo "== 7. 없음 3분류 — 조회 0건 (목표 9) =="
C="$TMP/C"; HC="$TMP/homeC"; mk_clone "$C" "$HC"; cp "$A/.hermes/universe.id" "$C/.hermes/"
cp -r "$HA/.hermes" "$HC/"                          # 열쇠는 있음(같은 사람의 다른 컴퓨터 가정)
EMPTY_BARE="$TMP/bare2"; git init -q --bare "$EMPTY_BARE"; git -C "$C" remote set-url origin "$EMPTY_BARE"
HOME="$HC" python3 "$C/scripts/hermes-sync.py" --project "$C" push >/dev/null 2>&1   # 자물쇠만 올라간다
OUT_C="$(HOME="$HC" python3 "$C/scripts/hermes-sync.py" --project "$C" status)"
assert "저장소·열쇠 있으나 조각 0 → '기억 0건'" 1 "$(grep -c '기억 0건' <<<"$OUT_C")"
OUT_A="$(SYNC_A status)"; OUT_B0="$(cat "$TMP/pullB.out")"
assert "세 문구가 서로 다름" 3 "$(printf '%s\n%s\n%s\n' "기억 저장소(refs/hermes/sync)가 없습니다" "$(grep -o '열쇠가 없습니다' <<<"$OUT_B0" | head -1)" "$(grep -o '기억 0건' <<<"$OUT_C")" | sort -u | wc -l)"

echo ""
echo "== 8. 이식 꺼짐(기본) — sync.json 없으면 로컬 전용 =="
D="$TMP/D"; mk_clone "$D" "$TMP/homeD"; rm -f "$D/.hermes/sync.json"
assert "push 는 '이식 꺼짐' 한 줄, rc 0" 1 "$(HOME="$TMP/homeD" python3 "$D/scripts/hermes-sync.py" --project "$D" push | grep -c '이식 꺼짐')"

echo ""
echo "== 9. age 없는 컴퓨터 — 훅 exit 0 · 한 줄 · DB 변경 0 (목표 14) =="
DB_A_BEFORE="$(md5sum "$A/.hermes/state.db" | awk '{print $1}')"
NOAGE="$TMP/noage"; mkdir -p "$NOAGE"; for b in git bash sed grep cat wc head awk basename dirname mktemp stat mkdir date timeout printf sh; do ln -sf "$(command -v $b)" "$NOAGE/$b"; done
# python3 는 pyenv 심(shim)일 수 있어 최소 PATH 에서 pyenv 를 못 찾는다(2026-09-20 실측) — 실제 실행 파일을 링크한다
ln -sf "$(python3 -c 'import sys; print(sys.executable)')" "$NOAGE/python3"
OUT_NOAGE="$(PATH="$NOAGE" HOME="$HA" python3 "$A/scripts/hermes-sync.py" --project "$A" pull 2>&1)"
assert "age 없음: pull rc 0" 0 "$?"
assert "age 없음: 한 줄 알림" 1 "$(grep -c 'age 가 없어' <<<"$OUT_NOAGE")"
assert "age 없음: state.db 변경 0" "$DB_A_BEFORE" "$(md5sum "$A/.hermes/state.db" | awk '{print $1}')"
HOOK="$REPO_ROOT/assets/hooks/claude-sessionstart-sync-pull.sh"
OUT_HOOK="$(echo '{"source":"startup"}' | PATH="$NOAGE" HOME="$HA" CLAUDE_PROJECT_DIR="$A" bash "$HOOK" 2>&1)"
assert "세션 시작 훅: age 없어도 exit 0" 0 "$?"
assert "세션 시작 훅: stdout 무출력(컨텍스트 오염 방지)" "" "$OUT_HOOK"

echo ""
echo "== 10. 참조 거부 서버 → 이식 불가 (목표 15) =="
REJ="$TMP/reject"; git init -q --bare "$REJ"
cat > "$REJ/hooks/update" <<'EOF'
#!/bin/sh
case "$1" in refs/hermes/*) echo "refusing custom refs" >&2; exit 1;; esac
EOF
chmod +x "$REJ/hooks/update"
E="$TMP/E"; mk_clone "$E" "$TMP/homeE"; cp "$A/.hermes/universe.id" "$E/.hermes/"; cp -r "$HA/.hermes" "$TMP/homeE/"
git -C "$E" remote set-url origin "$REJ"
OUT_E="$(HOME="$TMP/homeE" python3 "$E/scripts/hermes-sync.py" --project "$E" push 2>&1)"
assert "거부 서버: '이식 불가 — 사람 판단'" 1 "$(grep -c '이식 불가 — 사람 판단' <<<"$OUT_E")"

echo ""
echo "== 11. 기억 왕복 — A 의 memory_events → 원격 암호문 → B 의 memory_events·MEMORY.md (계획 agent-memory-roundtrip 목표 2) =="
AID="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['agents'][0]['agent_id'])" "$A/.hermes/agents.json" 2>/dev/null || PYTHONPATH="$S" python3 -c "from hermes_uuid7 import uuid7_str;print(uuid7_str())")"
[[ -f "$A/.hermes/agents.json" ]] && cp "$A/.hermes/agents.json" "$B/.hermes/"   # 명부는 커밋 파일 — clone 으로 받는 것을 흉내
PYTHONPATH="$S" python3 - "$A/.hermes/state.db" "$AID" "$UNI" <<'PY'
import sqlite3, sys
from hermes_memory_events import record, ensure_memory_schema
from hermes_uuid7 import uuid7_str
con = sqlite3.connect(sys.argv[1]); ensure_memory_schema(con)
aid, uni = sys.argv[2], sys.argv[3]
def ev(**k): return record(con, {"memory_id": uuid7_str(), "agent_id": aid, "universe_id": uni, **k})
ev(ts="2026-09-20T00:00:01", kind="memory.added", about="gate/r-size", body="400줄 넘기 전에 파일을 나눈다", source_event="review:1")
m2 = ev(ts="2026-09-20T00:00:02", kind="memory.added", about="sync/keys", body="열쇠는 세션 안에서 만든다", source_event="review:2")
ev(ts="2026-09-20T00:00:03", kind="memory.retracted", revises=m2, body="틀렸다 — 열쇠는 세션 밖에서(T-11)", source_event="review:3")
con.commit(); con.close()
PY
SYNC_A push >"$TMP/pushMem.out" 2>&1
assert "원격에 기억 조각 3(이벤트 1개 = 파일 1개)" 3 "$(remote_ls | grep -c "^memory/$AID/")"
MPATH="$(remote_ls | grep "^memory/$AID/" | head -1)"
assert "원격 기억 본문은 암호문(평문 0)" 0 "$(git -C "$A" show "refs/hermes/sync-remote:$MPATH" | grep -c '파일을 나눈다\|열쇠는 세션')"
assert "원격 기억의 기계 칸(about)은 평문" 1 "$(git -C "$A" show "refs/hermes/sync-remote:$MPATH" | grep -c '"about"')"
SYNC_B pull >"$TMP/pullMem.out" 2>&1
assert "B 에 기억 3건 적재" 3 "$(rows "$B" "select count(*) from memory_events where agent_id='$AID'")"
assert "B 기억 본문 평문 복원" "400줄 넘기 전에 파일을 나눈다" "$(rows "$B" "select body from memory_events where about='gate/r-size'")"
IDS_Q="select group_concat(memory_id) from (select memory_id from memory_events where agent_id='$AID' order by memory_id)"
assert "A·B memory_id 집합 동일" "$(rows "$A" "$IDS_Q")" "$(rows "$B" "$IDS_Q")"
BMD="$B/.hermes/agents/$AID/MEMORY.md"
assert "B MEMORY.md 가 pull 만으로 생성" 1 "$([[ -f "$BMD" ]] && echo 1 || echo 0)"
assert "B MEMORY.md 에 유효 기억" 1 "$(grep -c '400줄 넘기 전에' "$BMD")"
assert "B MEMORY.md 에 철회된 기억 없음" 0 "$(grep -c '열쇠는 세션 안에서' "$BMD")"
HOME="$HA" python3 "$A/scripts/hermes-agent.py" --project "$A" refresh-memory "$AID" >/dev/null 2>&1
assert "A·B MEMORY.md 내용 동일" "$(md5sum < "$A/.hermes/agents/$AID/MEMORY.md")" "$(md5sum < "$BMD")"
SYNC_B pull >"$TMP/pullMem2.out" 2>&1
assert "재pull 새 항목 0(멱등)" 1 "$(grep -c '새 항목 0건' "$TMP/pullMem2.out")"

echo ""
echo "== 12. 발전 재료 왕복 — 요약·패턴 수는 기본 운반, 원문은 옵션 (T-17, 계획 transport-plain 목표 1·2) =="
F="$TMP/F"; HF="$TMP/homeF"; G="$TMP/G"; HG="$TMP/homeG"; mk_clone "$F" "$HF"; mk_clone "$G" "$HG"
cp "$A/.hermes/universe.id" "$F/.hermes/"; cp "$A/.hermes/universe.id" "$G/.hermes/"
cp -r "$HA/.hermes" "$HF/"; cp -r "$HA/.hermes" "$HG/"                  # 같은 열쇠(잠금 모드 유지, 평문 모드는 14절)
echo '{"push": true}' > "$F/.hermes/sync.json"; echo '{"push": true}' > "$G/.hermes/sync.json"   # 기본 정책: history 없음
mkdir -p "$F/.hermes/history/sess-F"; printf '{"seq":0,"session_id":"sess-F","project_id":"p","role":"user","timestamp":"2026-09-20T00:00:00","content":"F 원문"}\n' > "$F/.hermes/history/sess-F/0000.jsonl"
python3 - "$F/.hermes/state.db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.executescript("""
CREATE TABLE IF NOT EXISTS session_summary (session_id TEXT PRIMARY KEY, project_id TEXT, slots_json TEXT, last_msg_count INTEGER DEFAULT 0, turn_count INTEGER DEFAULT 0, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE IF NOT EXISTS pattern_count (id INTEGER PRIMARY KEY AUTOINCREMENT, pattern_key TEXT NOT NULL UNIQUE, count INTEGER DEFAULT 1, last_seen DATETIME DEFAULT CURRENT_TIMESTAMP, crystallized INTEGER DEFAULT 0);
""")
con.execute("INSERT INTO session_summary VALUES ('s1','p','{\"decisions\":[\"요약 하나\"]}',3,2,'2026-09-20 01:00:00')")
con.execute("INSERT INTO session_summary VALUES ('s2','p','{\"decisions\":[\"요약 둘\"]}',5,4,'2026-09-20 02:00:00')")
con.execute("INSERT INTO pattern_count (pattern_key,count,last_seen,crystallized) VALUES ('테스트 먼저 돌린다',2,'2026-09-20 01:00:00',0)")
con.execute("INSERT INTO pattern_count (pattern_key,count,last_seen,crystallized) VALUES ('로그를 파일로 받는다',1,'2026-09-20 01:00:00',0)")
con.commit()
PY
HOME="$HF" python3 "$F/scripts/hermes-sync.py" --project "$F" push >"$TMP/pushF.out" 2>&1
assert "F push rc 0" 0 "$?"
FLS() { git -C "$F" fetch -q origin "+refs/hermes/sync:refs/hermes/sync-remote" 2>/dev/null; git -C "$F" ls-tree -r --name-only refs/hermes/sync-remote 2>/dev/null; }
assert "원격에 요약 2" 2 "$(FLS | grep -c '^summary/s[12]/')"
assert "원격에 패턴 2" 2 "$(FLS | grep -c '^pattern/')"
assert "원문(history/sess-F)은 기본 정책에서 안 올라감" 0 "$(FLS | grep -c '^history/sess-F/')"
SPATH="$(FLS | grep '^summary/s1/' | head -1)"
assert "요약 자유 글은 암호문(잠금 모드)" 0 "$(git -C "$F" show "refs/hermes/sync-remote:$SPATH" | grep -c '요약 하나')"
HOME="$HG" python3 "$G/scripts/hermes-sync.py" --project "$G" pull >"$TMP/pullG.out" 2>&1
assert "G 에 요약 2 적재" 2 "$(rows "$G" "select count(*) from session_summary")"
assert "G 요약 본문 평문 복원" 1 "$(rows "$G" "select count(*) from session_summary where slots_json like '%요약 둘%'")"
assert "G 패턴 count 일치(2)" 2 "$(rows "$G" "select count from pattern_count where pattern_key='테스트 먼저 돌린다'")"
python3 -c "import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);c.execute(\"update pattern_count set count=3 where pattern_key='테스트 먼저 돌린다'\");c.commit()" "$F/.hermes/state.db"
HOME="$HF" python3 "$F/scripts/hermes-sync.py" --project "$F" push >/dev/null 2>&1
HOME="$HG" python3 "$G/scripts/hermes-sync.py" --project "$G" pull >"$TMP/pullG2.out" 2>&1
assert "F 에서 1회 더 본 뒤 G 재pull → count 3(키별 max)" 3 "$(rows "$G" "select count from pattern_count where pattern_key='테스트 먼저 돌린다'")"
HOME="$HG" python3 "$G/scripts/hermes-sync.py" --project "$G" pull >"$TMP/pullG3.out" 2>&1
assert "재pull 새 항목 0(멱등)" 1 "$(grep -c '새 항목 0건' "$TMP/pullG3.out")"
echo '{"push": true, "history": true}' > "$F/.hermes/sync.json"
HOME="$HF" python3 "$F/scripts/hermes-sync.py" --project "$F" push >/dev/null 2>&1
assert "정책 history:true 면 원문이 올라간다(옵션)" 1 "$(FLS | grep -c '^history/sess-F/0000\.enc$')"

echo ""
echo "== 14. 평문 모드 — 열쇠 없이 요약·기억·이력이 오간다, 업로드 직전 마스킹, 원문은 거부 (T-18·T-20, 계획 transport-plain 목표 3·4) =="
P="$TMP/P"; HP="$TMP/homeP"; Q="$TMP/Q"; HQ="$TMP/homeQ"; mk_clone "$P" "$HP"; mk_clone "$Q" "$HQ"
cp "$A/.hermes/universe.id" "$P/.hermes/"; cp "$A/.hermes/universe.id" "$Q/.hermes/"; cp "$P/.hermes/agents.json" "$Q/.hermes/" 2>/dev/null || true
echo '{"push": true, "mode": "plain"}' > "$P/.hermes/sync.json"; echo '{"push": true, "mode": "plain"}' > "$Q/.hermes/sync.json"
PAID="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['agents'][0]['agent_id'])" "$P/.hermes/agents.json" 2>/dev/null || PYTHONPATH="$S" python3 -c "from hermes_uuid7 import uuid7_str;print(uuid7_str())")"
PYTHONPATH="$S" python3 - "$P/.hermes/state.db" "$PAID" "$UNI" <<'PY'
import sqlite3, sys
from hermes_memory_events import record, ensure_memory_schema
from hermes_uuid7 import uuid7_str
con = sqlite3.connect(sys.argv[1]); ensure_memory_schema(con)
record(con, {"memory_id": uuid7_str(), "agent_id": sys.argv[2], "universe_id": sys.argv[3], "ts": "2026-09-20T03:00:00",
             "kind": "memory.added", "about": "gate/r-size", "body": "400줄 넘기 전에 파일을 나눈다 — 담당 jjackkun 연락처 010-1234-5678, 계좌 110-123-456789",
             "source_event": "review:p"})
con.commit(); con.close()
PY
HOME="$HP" python3 "$P/scripts/hermes-journal.py" --project "$P" emit --json '{"kind":"task.started","task_id":"tp","intent":"고객 사무실(서울 강남구 테헤란로 12) 방문 뒤 정리","actor":"agent:main"}' >/dev/null
KEYS_BEFORE="$(remote_ls | grep -c '^keys/')"
OUT_P="$(PATH="$NOAGE" HOME="$HP" python3 "$P/scripts/hermes-sync.py" --project "$P" push 2>&1)"; RC_P=$?
assert "평문 push: 열쇠도 age 도 없이 rc 0" 0 "$RC_P"
assert "평문 push: age 없음 안내가 안 나온다" 0 "$(grep -c 'age 가 없어' <<<"$OUT_P")"
PLS() { git -C "$P" fetch -q origin "+refs/hermes/sync:refs/hermes/sync-remote" 2>/dev/null; git -C "$P" ls-tree -r --name-only refs/hermes/sync-remote 2>/dev/null; }
MP="$(PLS | grep "^memory/$PAID/" | head -1)"
assert "원격 기억 본문이 평문" 1 "$(git -C "$P" show "refs/hermes/sync-remote:$MP" | grep -c '파일을 나눈다')"
assert "업로드 직전 마스킹: 전화" 1 "$(git -C "$P" show "refs/hermes/sync-remote:$MP" | grep -c 'REDACTED:PHONE')"
assert "업로드 직전 마스킹: 계좌" 1 "$(git -C "$P" show "refs/hermes/sync-remote:$MP" | grep -c 'REDACTED:ACCOUNT')"
assert "업로드 직전 마스킹: git 작성자 이름(자동 정답지)" 0 "$(git -C "$P" show "refs/hermes/sync-remote:$MP" | grep -c 'jjackkun')"
JP="$(PLS | grep '^journal/' | grep -v "$(remote_ls | grep '^journal/' | head -1 | xargs basename 2>/dev/null)" | tail -1)"
assert "이력 자유 글도 평문+주소 마스킹" 1 "$(git -C "$P" show "refs/hermes/sync-remote:$JP" | grep -c 'REDACTED:ADDRESS')"
assert "평문 모드는 keys/ 를 올리지 않는다" "$KEYS_BEFORE" "$(PLS | grep -c '^keys/')"
OUT_Q="$(PATH="$NOAGE" HOME="$HQ" python3 "$Q/scripts/hermes-sync.py" --project "$Q" pull 2>&1)"; RC_Q=$?
assert "평문 pull: 열쇠·age 없이 rc 0" 0 "$RC_Q"
assert "평문 pull: 열쇠 없음(H-10) 안내가 안 나온다" 0 "$(grep -c 'H-10' <<<"$OUT_Q")"
assert "Q 에 기억 적재(평문)" 1 "$(rows "$Q" "select count(*) from memory_events where agent_id='$PAID'")"
assert "Q MEMORY.md 생성" 1 "$([[ -f "$Q/.hermes/agents/$PAID/MEMORY.md" ]] && echo 1 || echo 0)"
assert "Q 이력 intent 복원(주소는 가려진 채)" 1 "$(rows "$Q" "select count(*) from journal_events where task_id='tp' and intent like '%REDACTED:ADDRESS%'")"
assert "Q 는 원문(.enc)·keys 를 대기 목록에 두지 않는다(재pull 0건)" 1 "$(PATH="$NOAGE" HOME="$HQ" python3 "$Q/scripts/hermes-sync.py" --project "$Q" pull 2>&1 | grep -c '새 항목 0건')"
# 리뷰(2026-09-20) 3건: 건너뛴 암호문은 집계에 안 남는다 · 마스킹된 pattern_key 도 원본 해시로 병합 · 본문 속 "-----BEGIN AGE" 글자는 오탐 아님
assert "Q status: 잠금 조각을 건너뛰어도 '안 받은 조각 0건'" 1 "$(PATH="$NOAGE" HOME="$HQ" python3 "$Q/scripts/hermes-sync.py" --project "$Q" status 2>&1 | grep -c '아직 안 받은 조각 0건')"
python3 - "$P/.hermes/state.db" "$Q/.hermes/state.db" <<'PY'
import sqlite3, sys
for db, cnt in ((sys.argv[1], 2), (sys.argv[2], 1)):
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE IF NOT EXISTS pattern_count (id INTEGER PRIMARY KEY AUTOINCREMENT, pattern_key TEXT NOT NULL UNIQUE, count INTEGER DEFAULT 1, last_seen DATETIME DEFAULT CURRENT_TIMESTAMP, crystallized INTEGER DEFAULT 0)")
    con.execute("INSERT OR REPLACE INTO pattern_count (pattern_key,count,last_seen,crystallized) VALUES ('jjackkun 의 빌드 실패 키',?, '2026-09-20 05:00:00',0)", (cnt,))
    con.commit()
PY
PYTHONPATH="$S" python3 - "$P/.hermes/state.db" "$PAID" "$UNI" <<'PY'
import sqlite3, sys
from hermes_memory_events import record, ensure_memory_schema
from hermes_uuid7 import uuid7_str
con = sqlite3.connect(sys.argv[1]); ensure_memory_schema(con)
record(con, {"memory_id": uuid7_str(), "agent_id": sys.argv[2], "universe_id": sys.argv[3], "ts": "2026-09-20T04:00:00",
             "kind": "memory.added", "about": "sync/format", "body": "age 파일은 -----BEGIN AGE ENCRYPTED FILE----- 로 시작한다는 메모", "source_event": "review:q"})
con.commit(); con.close()
PY
HOME="$HP" python3 "$P/scripts/hermes-sync.py" --project "$P" push >/dev/null 2>&1
PATH="$NOAGE" HOME="$HQ" python3 "$Q/scripts/hermes-sync.py" --project "$Q" pull >/dev/null 2>&1
assert "마스킹된 pattern_key 가 원본 해시로 병합(count 2, 행 1)" "2 1" "$(rows "$Q" "select count from pattern_count where pattern_key='jjackkun 의 빌드 실패 키'") $(rows "$Q" "select count(*) from pattern_count where pattern_key like '%빌드 실패 키'")"
assert "본문에 '-----BEGIN AGE' 글자가 있는 평문 기억도 받는다(오탐 없음)" 1 "$(rows "$Q" "select count(*) from memory_events where about='sync/format'")"
HOOKQ="$REPO_ROOT/assets/hooks/claude-sessionstart-sync-pull.sh"; : > "$Q/.hermes/hooks.log"
echo '{"source":"startup"}' | PATH="$NOAGE" HOME="$HQ" CLAUDE_PROJECT_DIR="$Q" bash "$HOOKQ" >/dev/null 2>&1
assert "세션 시작 훅: 평문 모드는 age 없이 pull 을 돈다(skip:no-age 0, 목표 6)" 0 "$(grep -c 'skip:no-age' "$Q/.hermes/hooks.log")"
echo '{"push": true, "mode": "plain", "history": true}' > "$P/.hermes/sync.json"
HOME="$HP" python3 "$P/scripts/hermes-sync.py" --project "$P" push >/dev/null 2>&1
assert "평문 + history:true → push 거부 exit 2" 2 "$?"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
