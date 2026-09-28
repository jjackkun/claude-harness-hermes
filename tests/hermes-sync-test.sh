#!/usr/bin/env bash
# 운반 계층 검증 — 운반에 남은 것은 패턴 수와 판정을 통과한 공통 요약뿐이다
# (계획 docs/exec-plans/completed/2026-09-28-carry-agent-knowledge.md 목표 9·10, 결정 T-22·T-23·A-11).
#
#   두 클론이 bare 원격 하나를 공유한다.
#   1 저장소 없음 문구
#   2 잠금 모드 push — 요약·패턴·자물쇠가 오르고, 코드 브랜치·작업 트리 변화 0 · 요약 자유 글은 암호문 ·
#     기억·이력·원문 파일은 **오르지 않는다**(기억·이력은 git 파일, 원문은 저장 안 함)
#   3 열쇠 없는 클론 — H-10 안내, DB 변경 0 · 4 자물쇠 등록 뒤 pull 로 합류·복호
#   5 두 클론 동시 push — 둘 다 올라감, --force 0 · 6 "기억 없음" 3분류가 서로 다른 문구
#   7 정책 꺼짐 · 8 age 없는 컴퓨터(훅 exit 0·한 줄·DB 변경 0) · 9 참조 거부 서버
#   10 옛 판이 원격에 남긴 history/·memory/·journal/ 는 받지 않는다(오류 없이 건너뜀)
#   11 평문 모드 — 열쇠 없이 요약·패턴이 오간다 · 업로드 직전 마스킹 · 판정 안 된(대기·미판정) 항목은 안 오른다 ·
#      패턴 키별 max · 남은 "history": true 키는 무시된다
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
mk_clone() {  # <dir> <HOME> [정책 JSON]
  mkdir -p "$1/scripts/data" "$1/.hermes" "$2"
  cp "$S"/*.py "$S/hermes-keys.sh" "$S/hermes-sync.py" "$1/scripts/"
  cp "$REPO_ROOT/assets/data/bip39-english.txt" "$1/scripts/data/"
  git init -q "$1"; git -C "$1" config user.name jjackkun; git -C "$1" config user.email t@t
  git -C "$1" remote add origin "$BARE"
  git -C "$1" commit -q --allow-empty -m init
  python3 "$S/hermes-init.py" --project "$1" >/dev/null 2>&1
  echo "${3:-{\"push\": true\}}" > "$1/.hermes/sync.json"
}
rows() { python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]+'/.hermes/state.db').execute(sys.argv[2]).fetchone()[0])" "$1" "$2" 2>/dev/null || echo err; }
# 표가 없으면 0 — "안 왔다" 를 재는 자리에서 표 부재를 오류로 치지 않는다
count_or0() { python3 -c "
import sqlite3,sys
c=sqlite3.connect(sys.argv[1]+'/.hermes/state.db')
has=c.execute(\"select count(*) from sqlite_master where type='table' and name=?\",(sys.argv[2],)).fetchone()[0]
print(c.execute(sys.argv[3]).fetchone()[0] if has else 0)" "$1" "$2" "$3" 2>/dev/null || echo err; }
# 공통 요약 한 건 + 그 항목들을 판정 표에 적는다(<dir> <sid> <status> <항목...>)
seed_summary() {
  local dir="$1" sid="$2" status="$3"; shift 3
  PYTHONPATH="$S" python3 - "$dir/.hermes/state.db" "$sid" "$status" "$@" <<'PY'
import json, sqlite3, sys
from hermes_summary_owner import ensure_agent_column
from hermes_privacy_pending import mark
db, sid, status, items = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
con = sqlite3.connect(db)
con.execute("CREATE TABLE IF NOT EXISTS session_summary (session_id TEXT PRIMARY KEY, project_id TEXT, slots_json TEXT, "
            "last_msg_count INTEGER DEFAULT 0, turn_count INTEGER DEFAULT 0, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)")
ensure_agent_column(con)
con.execute("INSERT OR REPLACE INTO session_summary (session_id, project_id, slots_json, updated_at) VALUES (?,?,?,?)",
            (sid, "p", json.dumps({"decisions": items}, ensure_ascii=False), "2026-09-28 01:00:00"))
if status != "none":
    for t in items:
        mark(con, "summary", sid, t, status)
con.commit()
PY
}
seed_pattern() {  # <dir> <key> <count> [판정 상태 — 기본 clean, none 이면 판정 기록 없음]
  PYTHONPATH="$S" python3 - "$1/.hermes/state.db" "$2" "$3" "${4:-clean}" <<'PY'
import sqlite3, sys
from hermes_privacy_pending import mark
con = sqlite3.connect(sys.argv[1])
if sys.argv[4] != "none":
    mark(con, "pattern", "", sys.argv[2], sys.argv[4])
con.execute("CREATE TABLE IF NOT EXISTS pattern_count (id INTEGER PRIMARY KEY AUTOINCREMENT, pattern_key TEXT NOT NULL UNIQUE, "
            "count INTEGER DEFAULT 1, last_seen DATETIME DEFAULT CURRENT_TIMESTAMP, crystallized INTEGER DEFAULT 0)")
con.execute("INSERT OR REPLACE INTO pattern_count (pattern_key,count,last_seen,crystallized) VALUES (?,?,'2026-09-28 01:00:00',0)",
            (sys.argv[2], int(sys.argv[3])))
con.commit()
PY
}

A="$TMP/A"; HA="$TMP/homeA"; B="$TMP/B"; HB="$TMP/homeB"
mk_clone "$A" "$HA"; mk_clone "$B" "$HB"
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$A')"
cp "$A/.hermes/universe.id" "$B/.hermes/"          # clone 으로 받는 커밋 파일을 흉내
UNI="$(cat "$A/.hermes/universe.id")"
SYNC_A() { HOME="$HA" python3 "$A/scripts/hermes-sync.py" --project "$A" "$@"; }
SYNC_B() { HOME="$HB" python3 "$B/scripts/hermes-sync.py" --project "$B" "$@"; }
KEYS_A() { HOME="$HA" bash "$A/scripts/hermes-keys.sh" "$@" --project "$A"; }
remote_ls() { git -C "$A" fetch -q origin "+refs/hermes/sync:refs/hermes/sync-remote" 2>/dev/null; git -C "$A" ls-tree -r --name-only refs/hermes/sync-remote 2>/dev/null; }

echo "== 1. 저장소 없음 =="
KEYS_A init >/dev/null 2>&1
assert "원격에 저장소 없음 문구" 1 "$(SYNC_A status | grep -c '기억 저장소.*없습니다')"

echo ""
echo "== 2. 잠금 모드 push — 요약·패턴·자물쇠만, 기억·이력·원문은 안 오른다 =="
seed_summary "$A" s-a1 clean "배포는 금요일" "스테이징 먼저 확인"
seed_pattern "$A" "테스트 먼저 돌린다" 2
mkdir -p "$A/.hermes/history/sess-1"
printf '{"seq":0,"session_id":"sess-1","content":"옛 원문 한 줄"}\n' > "$A/.hermes/history/sess-1/0000.jsonl"
HOME="$HA" python3 "$A/scripts/hermes-journal.py" --project "$A" emit --json '{"kind":"task.started","task_id":"t1","intent":"비밀 의도 한 줄","actor":"agent:main"}' >/dev/null
PYTHONPATH="$S" python3 - "$A/.hermes/state.db" "$UNI" <<'PY'
import sqlite3, sys
from hermes_memory_events import record
con = sqlite3.connect(sys.argv[1])
record(con, {"memory_id": "m1", "kind": "memory.added", "agent_id": "ag", "universe_id": sys.argv[2],
             "ts": "2026-09-28T00:00:00Z", "about": "x", "body": "기억 본문"})
PY
HEAD_BEFORE="$(git -C "$A" rev-parse HEAD)"; WT_BEFORE="$(git -C "$A" status --porcelain | md5sum)"
SYNC_A push >"$TMP/pushA.out" 2>&1
assert "push 종료 코드 0" 0 "$?"
assert "원격에 refs/hermes/sync 존재" 1 "$(git ls-remote "$BARE" refs/hermes/sync | grep -c .)"
assert "코드 브랜치 HEAD 불변" "$HEAD_BEFORE" "$(git -C "$A" rev-parse HEAD)"
assert "작업 트리 변경 0(전후 동일)" "$WT_BEFORE" "$(git -C "$A" status --porcelain | md5sum)"
assert "원격에 요약 1" 1 "$(remote_ls | grep -c '^summary/s-a1/')"
assert "원격에 패턴 1" 1 "$(remote_ls | grep -c '^pattern/')"
assert "원격에 자물쇠 + 감싼 마스터" 2 "$(remote_ls | grep -c '^keys/jjackkun/')"
assert "원문은 오르지 않는다(T-23)" 0 "$(remote_ls | grep -c '^history/')"
assert "이력은 오르지 않는다(git 파일, A-11)" 0 "$(remote_ls | grep -c '^journal/')"
assert "기억은 오르지 않는다(git 파일, A-11)" 0 "$(remote_ls | grep -c '^memory/')"
SPATH="$(remote_ls | grep '^summary/s-a1/' | head -1)"
assert "요약 자유 글은 암호문(평문 0)" 0 "$(git -C "$A" show "refs/hermes/sync-remote:$SPATH" | grep -c '배포는 금요일')"
SYNC_A push >"$TMP/pushA2.out" 2>&1
assert "재push 는 올릴 것 없음(멱등)" 1 "$(grep -c '올릴 것 없음' "$TMP/pushA2.out")"

echo ""
echo "== 3. B — 열쇠 없음 → H-10 안내, DB 변경 0 =="
DB_B_BEFORE="$(md5sum "$B/.hermes/state.db" | awk '{print $1}')"
SYNC_B pull >"$TMP/pullB.out" 2>&1
assert "pull 종료 코드 0(멈추지 않음)" 0 "$?"
assert "'열쇠가 없습니다' 안내" 1 "$(grep -c '열쇠가 없습니다' "$TMP/pullB.out")"
assert "안내의 조각 수는 요약·패턴만(2건)" 1 "$(grep -c '조각 2건' "$TMP/pullB.out")"
assert "state.db 변경 0" "$DB_B_BEFORE" "$(md5sum "$B/.hermes/state.db" | awk '{print $1}')"
assert "status 도 열쇠 없음 분류" 1 "$(SYNC_B status | grep -c '열쇠가 없습니다')"

echo ""
echo "== 4. B 합류 — 자물쇠 등록 → pull 로 마스터 풀고 요약 복호 =="
mkdir -p "$HB/.hermes/keys/$UNI"; age-keygen -o "$HB/.hermes/keys/$UNI/computer.key" >/dev/null 2>&1
B_LOCK="$(age-keygen -y "$HB/.hermes/keys/$UNI/computer.key")"
KEYS_A add-computer "$B_LOCK" >/dev/null 2>&1
SYNC_A push >/dev/null 2>&1
SYNC_B pull >"$TMP/pullB2.out" 2>&1
assert "B 가 감싼 마스터를 받아 풀었다" 1 "$(grep -c '감싼 마스터를 받아 풀었습니다' "$TMP/pullB2.out")"
assert "B 마스터 열쇠 생성(0600)" 600 "$(stat -c '%a' "$HB/.hermes/keys/$UNI/master.key")"
assert "B 에 요약 평문 복원" 1 "$(rows "$B" "select count(*) from session_summary where slots_json like '%배포는 금요일%'")"
assert "B 패턴 count 2" 2 "$(rows "$B" "select count from pattern_count where pattern_key='테스트 먼저 돌린다'")"
assert "B 에 기억·이력은 운반으로 안 온다" "0 0" "$(count_or0 "$B" memory_events "select count(*) from memory_events") $(count_or0 "$B" journal_events "select count(*) from journal_events where task_id='t1'")"
SYNC_B pull >"$TMP/pullB3.out" 2>&1
assert "재pull 은 새 항목 0(멱등)" 1 "$(grep -c '새 항목 0건' "$TMP/pullB3.out")"

echo ""
echo "== 5. 두 클론 동시 push — 둘 다 올라감, --force 0 =="
seed_summary "$A" s-a2 clean "A 둘째 요약"; seed_summary "$B" s-b2 clean "B 둘째 요약"
SYNC_A push >/dev/null 2>&1; SYNC_B push >"$TMP/pushB.out" 2>&1
assert "B push(뒤늦은 쪽) 성공" 0 "$?"
assert "원격 트리에 두 요약 모두" 2 "$(remote_ls | grep -cE '^summary/s-(a2|b2)/')"
assert "push 명령에 --force 없음" 0 "$(grep -c 'push.*--force\|--force.*push' "$S/hermes_sync_ref.py")"
SYNC_A pull >/dev/null 2>&1
assert "A 가 B 요약을 받아 복호" 1 "$(rows "$A" "select count(*) from session_summary where slots_json like '%B 둘째 요약%'")"

echo ""
echo "== 6. 없음 3분류 — 서로 다른 문구 =="
C="$TMP/C"; HC="$TMP/homeC"; mk_clone "$C" "$HC"; cp "$A/.hermes/universe.id" "$C/.hermes/"
cp -r "$HA/.hermes" "$HC/"
EMPTY_BARE="$TMP/bare2"; git init -q --bare "$EMPTY_BARE"; git -C "$C" remote set-url origin "$EMPTY_BARE"
HOME="$HC" python3 "$C/scripts/hermes-sync.py" --project "$C" push >/dev/null 2>&1   # 자물쇠만 올라간다
OUT_C="$(HOME="$HC" python3 "$C/scripts/hermes-sync.py" --project "$C" status)"
assert "저장소·열쇠 있으나 조각 0 → '기억 0건'" 1 "$(grep -c '기억 0건' <<<"$OUT_C")"
OUT_B0="$(cat "$TMP/pullB.out")"
assert "세 문구가 서로 다름" 3 "$(printf '%s\n%s\n%s\n' "기억 저장소(refs/hermes/sync)가 없습니다" "$(grep -o '열쇠가 없습니다' <<<"$OUT_B0" | head -1)" "$(grep -o '기억 0건' <<<"$OUT_C")" | sort -u | wc -l)"

echo ""
echo "== 7. 이식 꺼짐 — sync.json 없으면 로컬 전용 =="
D="$TMP/D"; mk_clone "$D" "$TMP/homeD"; rm -f "$D/.hermes/sync.json"
assert "push 는 '이식 꺼짐' 한 줄" 1 "$(HOME="$TMP/homeD" python3 "$D/scripts/hermes-sync.py" --project "$D" push | grep -c '이식 꺼짐')"

echo ""
echo "== 8. age 없는 컴퓨터 — 훅 exit 0 · 한 줄 · DB 변경 0 =="
DB_A_BEFORE="$(md5sum "$A/.hermes/state.db" | awk '{print $1}')"
NOAGE="$TMP/noage"; mkdir -p "$NOAGE"; for b in git bash sed grep cat wc head awk basename dirname mktemp stat mkdir date timeout printf sh; do ln -sf "$(command -v $b)" "$NOAGE/$b"; done
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
echo "== 9. 참조 거부 서버 → 이식 불가 =="
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
echo "== 10. 옛 판이 남긴 history/·memory/·journal/ 는 받지 않는다 =="
OLD="$TMP/oldpieces"; git clone -q "$BARE" "$OLD" 2>/dev/null
git -C "$OLD" fetch -q origin "+refs/hermes/sync:refs/hermes/sync" 2>/dev/null
( cd "$OLD" && git read-tree refs/hermes/sync \
  && printf 'x' | git hash-object -w --stdin >/dev/null \
  && for p in history/old/0000.enc memory/ag/m9.json journal/2026/09/01/e9.json; do
       b="$(printf '{"body":"옛 조각"}' | git hash-object -w --stdin)"; git update-index --add --cacheinfo 100644 "$b" "$p"; done \
  && t="$(git write-tree)" && c="$(git commit-tree "$t" -p refs/hermes/sync -m old)" \
  && git push -q origin "$c:refs/hermes/sync" ) >/dev/null 2>&1
assert "원격에 옛 갈래 3개를 심었다" 3 "$(remote_ls | grep -cE '^(history|memory|journal)/')"
SYNC_B pull >/dev/null 2>&1; RC_OLD=$?
assert "옛 갈래가 있어도 pull rc 0" 0 "$RC_OLD"
OUT_OLD="$(SYNC_B pull 2>&1)"
assert "옛 갈래는 대기 목록에도 없다(다시 pull 해도 새 항목 0건)" 1 "$(grep -c '새 항목 0건' <<<"$OUT_OLD")"
assert "옛 기억 조각이 DB 에 들어오지 않는다" 0 "$(count_or0 "$B" memory_events "select count(*) from memory_events where memory_id='m9'")"
assert "status 의 '안 받은 조각' 에도 옛 갈래가 안 잡힌다" 1 "$(SYNC_B status | grep -c '아직 안 받은 조각 0건')"

echo ""
echo "== 11. 평문 모드 — 열쇠 없이 요약·패턴, 업로드 직전 마스킹, 판정 안 된 항목은 안 오른다 =="
PBARE="$TMP/pbare"; git init -q --bare "$PBARE"
P="$TMP/P"; HP="$TMP/homeP"; Q="$TMP/Q"; HQ="$TMP/homeQ"
mk_clone "$P" "$HP" '{"push": true, "mode": "plain", "history": true}'; mk_clone "$Q" "$HQ" '{"push": true, "mode": "plain"}'
git -C "$P" remote set-url origin "$PBARE"; git -C "$Q" remote set-url origin "$PBARE"
cp "$A/.hermes/universe.id" "$P/.hermes/"; cp "$A/.hermes/universe.id" "$Q/.hermes/"
seed_summary "$P" s-p1 clean "배포 담당 연락처 010-1234-5678 로 알림"
seed_summary "$P" s-p2 pending "요즘 허리가 아프다"
seed_summary "$P" s-p3 none "판정 안 한 옛 문장"
seed_pattern "$P" "빌드 전에 린트" 2
seed_pattern "$P" "판정 안 한 패턴 키" 1 none
OUT_P="$(PATH="$NOAGE" HOME="$HP" python3 "$P/scripts/hermes-sync.py" --project "$P" push 2>&1)"; RC_P=$?
assert "평문 push: 열쇠도 age 도 없이 rc 0 (남은 history 키는 무시)" 0 "$RC_P"
PLS() { git -C "$P" fetch -q origin "+refs/hermes/sync:refs/hermes/sync-remote" 2>/dev/null; git -C "$P" ls-tree -r --name-only refs/hermes/sync-remote 2>/dev/null; }
SP1="$(PLS | grep '^summary/s-p1/' | head -1)"
assert "판정 통과 요약은 평문으로 오른다" 1 "$(git -C "$P" show "refs/hermes/sync-remote:$SP1" | grep -c '배포 담당')"
assert "업로드 직전 마스킹: 전화" 1 "$(git -C "$P" show "refs/hermes/sync-remote:$SP1" | grep -c 'REDACTED:PHONE')"
SP2="$(PLS | grep '^summary/s-p2/' | head -1)"; SP3="$(PLS | grep '^summary/s-p3/' | head -1)"
assert "검토 대기 항목은 안 오른다" 0 "$(git -C "$P" show "refs/hermes/sync-remote:$SP2" 2>/dev/null | grep -c '허리')"
assert "판정 안 한 항목은 안 오른다" 0 "$(git -C "$P" show "refs/hermes/sync-remote:$SP3" 2>/dev/null | grep -c '옛 문장')"
assert "평문 모드는 keys/ 를 올리지 않는다" 0 "$(PLS | grep -c '^keys/')"
assert "판정 안 한 패턴 키는 안 오른다(리뷰 HIGH)" 0 "$(for f in $(PLS | grep '^pattern/'); do git -C "$P" show "refs/hermes/sync-remote:$f"; done | grep -c '판정 안 한 패턴 키')"
assert "판정 통과 패턴 키는 오른다" 1 "$(for f in $(PLS | grep '^pattern/'); do git -C "$P" show "refs/hermes/sync-remote:$f"; done | grep -c '빌드 전에 린트')"
OUT_Q="$(PATH="$NOAGE" HOME="$HQ" python3 "$Q/scripts/hermes-sync.py" --project "$Q" pull 2>&1)"; RC_Q=$?
assert "평문 pull: 열쇠·age 없이 rc 0" 0 "$RC_Q"
assert "평문 pull: H-10 안내 없음" 0 "$(grep -c 'H-10' <<<"$OUT_Q")"
assert "Q 에 요약 적재(가려진 채)" 1 "$(rows "$Q" "select count(*) from session_summary where slots_json like '%REDACTED:PHONE%'")"
assert "Q 에 대기 문장은 없다" 0 "$(rows "$Q" "select count(*) from session_summary where slots_json like '%허리%'")"
seed_pattern "$P" "빌드 전에 린트" 3; seed_pattern "$Q" "빌드 전에 린트" 1
PATH="$NOAGE" HOME="$HP" python3 "$P/scripts/hermes-sync.py" --project "$P" push >/dev/null 2>&1
PATH="$NOAGE" HOME="$HQ" python3 "$Q/scripts/hermes-sync.py" --project "$Q" pull >/dev/null 2>&1
assert "패턴은 키별 max(3)" 3 "$(rows "$Q" "select count from pattern_count where pattern_key='빌드 전에 린트'")"
HOOKQ="$REPO_ROOT/assets/hooks/claude-sessionstart-sync-pull.sh"; : > "$Q/.hermes/hooks.log"
echo '{"source":"startup"}' | PATH="$NOAGE" HOME="$HQ" CLAUDE_PROJECT_DIR="$Q" bash "$HOOKQ" >/dev/null 2>&1
assert "세션 시작 훅: 평문 모드는 age 없이 pull 을 돈다(skip:no-age 0)" 0 "$(grep -c 'skip:no-age' "$Q/.hermes/hooks.log")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
