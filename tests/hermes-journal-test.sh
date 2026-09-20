#!/usr/bin/env bash
# 작업 이력 검증 (계획 docs/exec-plans/active/2026-09-15-universe-id-journal.md 목표 3·4·5·9·12).
#
#   - journal_events 는 추가 전용 (UPDATE·DELETE 는 트리거가 막는다)
#   - 허용목록 밖의 칸·값은 기록되지 않는다 (원문 유입 차단, J-06)
#   - 결과 3층: claimed 는 에이전트, verified 는 기계, accepted 는 사람만
#   - 보기: thread · graph · mismatch
#   - rollback 은 지우지 않고 이름만 바꾼다
#
# 실행: bash tests/hermes-journal-test.sh
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

S="$REPO_ROOT/scripts"
PROJ="$TMP/proj"; mkdir -p "$PROJ/.hermes"
PYTHONPATH="$S" python3 -c "
from hermes_universe import ensure_universe_id; ensure_universe_id('$PROJ')"
UNI="$(cat "$PROJ/.hermes/universe.id")"
DB="$PROJ/.hermes/state.db"
mkdir -p "$PROJ/scripts"
for m in hermes-journal.py hermes_journal.py hermes_journal_schema.py hermes_journal_migrate.py hermes_redact.py hermes_journal_views.py hermes_universe.py hermes_uuid7.py hermes_loop_decisions.py; do cp "$S/$m" "$PROJ/scripts/"; done
J() { python3 "$S/hermes-journal.py" --project "$PROJ" --db "$DB" "$@"; }
q() { python3 -c "
import sqlite3,sys;print(sqlite3.connect('$DB').execute(sys.argv[1]).fetchone()[0])" "$1" 2>/dev/null; }

echo "== 1. 기록과 키 (목표 3) =="
EV1=$(J emit --json '{"kind":"task.started","task_id":"t1","intent":"이력 테스트 시작"}')
assert "event_id 가 UUIDv7" "7" "$(python3 -c "import uuid;print(uuid.UUID('$EV1').version)")"
assert "universe_id 가 자동으로 채워짐" "$UNI" "$(q "select universe_id from journal_events")"
assert "actor 가 기계로 찍힘(agent: 접두)" "1" "$(q "select count(*) from journal_events where actor like 'agent:%'")"
assert "requested_by 가 사람으로 찍힘" "1" "$(q "select count(*) from journal_events where requested_by like 'human:%' or requested_by like 'system:%'")"

echo ""
echo "== 2. 추가 전용 (목표 3) =="
assert "UPDATE 차단" "blocked" "$(python3 -c "
import sqlite3
try: sqlite3.connect('$DB').execute(\"update journal_events set kind='step'\"); print('open')
except sqlite3.IntegrityError: print('blocked')")"
assert "DELETE 차단" "blocked" "$(python3 -c "
import sqlite3
try: sqlite3.connect('$DB').execute('delete from journal_events'); print('open')
except sqlite3.IntegrityError: print('blocked')")"

echo ""
echo "== 3. 허용목록 (목표 4) =="
J emit --json '{"kind":"step","task_id":"t1","raw_text":"대화 원문"}' >/dev/null 2>&1
assert "모르는 칸은 거부(rc=2)" "2" "$?"
J emit --json '{"kind":"step","task_id":"t1","evidence":{"secret":"x"}}' >/dev/null 2>&1
assert "evidence 의 모르는 칸도 거부" "2" "$?"
J emit --json '{"kind":"mystery","task_id":"t1"}' >/dev/null 2>&1
assert "모르는 kind 거부" "2" "$?"
J emit --json '{"kind":"step","task_id":"t1","actor":"root"}' >/dev/null 2>&1
assert "접두어 없는 actor 거부" "2" "$?"
J emit --json '{"kind":"step","task_id":"t1","evidence":{"command":"/usr/bin/curl -H Authorization: Bearer SECRET","exit_code":0}}' >/dev/null
assert "command 는 이름만 남는다" "curl" "$(python3 -c "
import sqlite3,json
row=sqlite3.connect('$DB').execute(
  \"select evidence from journal_events where evidence like '%command%'\").fetchone()[0]
print(json.loads(row)['command'])")"
assert "인자(비밀값)가 남지 않음" "0" "$(q "select count(*) from journal_events where evidence like '%SECRET%'")"
LONG=$(python3 -c "print('가'*600)")
J emit --json "{\"kind\":\"step\",\"task_id\":\"t1\",\"intent\":\"$LONG\"}" >/dev/null 2>&1
assert "긴 자유 글 거부" "2" "$?"
python3 -c "
import json,sys;sys.path.insert(0,'$S')
from hermes_journal_schema import validate, JournalRejected
try:
    validate({'kind':'step','event_id':'e','ts':'t','universe_id':'u','task_id':'t1','actor':'agent:main','intent':'한 줄\n두 줄'})
    print('통과함')
except JournalRejected: print('거부')" > "$TMP/nl.txt"
assert "줄바꿈 있는 자유 글 거부" "거부" "$(cat "$TMP/nl.txt")"

echo ""
echo "== 4. 결과 3층 (목표 5) =="
J emit --json '{"kind":"task.finished","task_id":"t2","claimed":"success","verified":"pass"}' >/dev/null
assert "증거 없으면 기계 판정은 none (에이전트 주장 무시)" "none" "$(q "select verified from journal_events where task_id='t2'")"
J emit --json '{"kind":"task.finished","task_id":"t3","claimed":"success","evidence":{"exit_code":1}}' >/dev/null
assert "exit_code 0 아니면 fail" "fail" "$(q "select verified from journal_events where task_id='t3'")"
J emit --json '{"kind":"task.finished","task_id":"t4","claimed":"success","evidence":{"exit_code":0}}' >/dev/null
assert "exit_code 0 이면 pass" "pass" "$(q "select verified from journal_events where task_id='t4'")"
J emit --json '{"kind":"task.finished","task_id":"t5","claimed":"success","accepted":"human:jjackkun"}' >/dev/null
assert "accepted 는 기록기가 쓰지 않는다(사람만)" "0" "$(q "select count(*) from journal_events where accepted is not null")"

echo ""
echo "== 5. 보기 (목표 9) =="
assert "thread 가 t1 의 이벤트를 모은다" "2" "$(J thread t1 | python3 -c "import json,sys;print(len(json.load(sys.stdin)))")"
# 계획 design-gaps-tier2 목표 2 — actor 가 agent: 인데 task.assigned 짝이 없으면 origin=unknown (identity.md:198,209)
J emit --json '{"kind":"step","task_id":"t-orphan","actor":"agent:ghost","intent":"짝 없는 행위자"}' >/dev/null
J emit --json '{"kind":"task.assigned","task_id":"t-paired","actor":"human:x","intent":"배정"}' >/dev/null
J emit --json '{"kind":"step","task_id":"t-paired","actor":"agent:real","intent":"짝 있는 행위자"}' >/dev/null
assert "짝 없는 agent 행 origin=unknown" "unknown" "$(J thread t-orphan | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['origin'])")"
assert "짝 있는 agent 행 origin=paired" "paired" "$(J thread t-paired | python3 -c "import json,sys;print([r['origin'] for r in json.load(sys.stdin) if r['actor']=='agent:real'][0])")"
assert "사람 행 origin=n/a" "n/a" "$(J thread t-paired | python3 -c "import json,sys;print([r['origin'] for r in json.load(sys.stdin) if r['actor']=='human:x'][0])")"
assert "mismatch 는 주장 성공·기계 실패만" "t3" "$(J mismatch | python3 -c "
import json,sys;d=json.load(sys.stdin);print(d[0]['task_id'] if len(d)==1 else [x['task_id'] for x in d])")"
J emit --json '{"kind":"task.started","task_id":"child","parent_task_id":"t1"}' >/dev/null
assert "graph 가 부모 간선을 낸다" "1" "$(J graph child | python3 -c "
import json,sys;print(sum(1 for e in json.load(sys.stdin)['edges'] if e['type']=='parent'))")"
J emit --json "{\"kind\":\"step\",\"task_id\":\"child\",\"caused_by\":[\"$EV1\"]}" >/dev/null
assert "graph 가 caused_by 간선을 낸다" "1" "$(J graph child | python3 -c "
import json,sys;print(sum(1 for e in json.load(sys.stdin)['edges'] if e['type']=='caused_by'))")"

echo ""
echo "== 6. 미완료 작업 (목표 6 의 바탕) =="
# 세션 종료(--all)는 간격과 무관하게 미완료 전부를 닫는다
assert "끝나지 않은 작업 2건(t1 · child)" "2" "$(J gap-check --all)"
assert "누락 이벤트가 붙었다" "2" "$(q "select count(*) from journal_events where actor='system:claude-stop-journal-gap'")"
assert "누락 이벤트의 claimed 는 abandoned" "2" "$(q "select count(*) from journal_events where claimed='abandoned'")"
assert "다시 돌려도 중복으로 붙지 않음" "0" "$(J gap-check --all)"
# 기본(간격 판정)은 방금 시작한 작업을 끊긴 것으로 보지 않는다
J emit --json '{"kind":"task.started","task_id":"fresh-default"}' >/dev/null
assert "기본 간격(120분) 안이면 누락 0" "0" "$(J gap-check)"

echo ""
echo "== 6-b. 행위자 4경로 (목표 7) =="
# (1) 대화형 기본 — agent:main + git user.name
assert "대화형: actor=agent:main" "agent:main" "$(q "select actor from journal_events where task_id='t1' limit 1")"
# (2) 헤드리스 루프 — 러너가 넣은 지시자
HERMES_REQUESTED_BY="human:runner" J emit --json '{"kind":"step","task_id":"r1"}' >/dev/null
assert "루프: requested_by 를 환경에서 받는다" "human:runner" "$(q "select requested_by from journal_events where task_id='r1'")"
# (3) cron — 사람이 아니라 시스템
HERMES_ACTOR="system:hermes-cron" HERMES_REQUESTED_BY="system:hermes-cron" \
  J emit --json '{"kind":"step","task_id":"c1"}' >/dev/null
assert "cron: actor=system:hermes-cron" "system:hermes-cron" "$(q "select actor from journal_events where task_id='c1'")"
# (4) 하위 에이전트 — 훅이 template 을 남긴다
echo '{"agent_id":"sub-9","agent_type":"code-reviewer","session_id":"s9"}' \
  | CLAUDE_PROJECT_DIR="$PROJ" bash "$REPO_ROOT/assets/hooks/claude-subagentstop-journal.sh" 2>/dev/null
assert "하위 에이전트: evidence.template 에 직무" "code-reviewer" "$(python3 -c "
import sqlite3,json
row=sqlite3.connect('$DB').execute(
  \"select evidence from journal_events where task_id='sub-9'\").fetchone()
print(json.loads(row[0])['template'] if row else 'none')" 2>/dev/null)"
assert "하위 에이전트도 지시자가 채워짐" "1" "$(q "select count(*) from journal_events where task_id='sub-9' and requested_by is not null")"
# (5) loops.started_by — 루프를 시작한 사람이 남는다
assert "loops 에 started_by 칸" "1" "$(python3 -c "
import sqlite3,sys;sys.path.insert(0,'$S')
from hermes_loop import ensure_schema
ensure_schema('$DB')
print(sum(1 for r in sqlite3.connect('$DB').execute('PRAGMA table_info(loops)') if r[1]=='started_by'))")"

echo ""
echo "== 6-c. heartbeat 간격 판정 (목표 13) =="
# 간격 안: 방금 시작한 작업은 끊긴 것이 아니다
J emit --json '{"kind":"task.started","task_id":"hb-fresh"}' >/dev/null
assert "간격 안이면 누락 0" "0" "$(J gap-check --stale-minutes 60)"
# 간격 초과: 마지막 이벤트가 오래된 작업
python3 -c "
import sqlite3,sys;sys.path.insert(0,'$S')
from hermes_uuid7 import uuid7_str
c=sqlite3.connect('$DB')
c.execute(\"insert into journal_events (event_id,ts,kind,universe_id,task_id,actor)\"
          \" values (?,?,?,?,?,?)\",
          (uuid7_str(),'2020-01-01T00:00:00Z','task.started','$UNI','hb-stale','agent:main'))
c.commit()"
assert "간격 넘긴 작업은 누락 1건" "1" "$(J gap-check --stale-minutes 60)"
assert "누락 사유가 heartbeat-timeout" "1" "$(q "select count(*) from journal_events where task_id='hb-stale' and evidence like '%heartbeat-timeout%'")"
BEFORE_ALL="$(q "select count(*) from journal_events where kind='task.started' and task_id not in (select task_id from journal_events where kind='task.finished')")"
SE_BEFORE="$(q "select count(*) from journal_events where evidence like '%session-end%'")"
assert "--all 은 미완료 전부를 닫는다" "$BEFORE_ALL" "$(J gap-check --all)"
assert "--all 뒤 미완료 0" "0" "$(q "select count(*) from journal_events where kind='task.started' and task_id not in (select task_id from journal_events where kind='task.finished')")"
assert "--all 의 사유는 session-end" "$BEFORE_ALL" "$(( $(q "select count(*) from journal_events where evidence like '%session-end%'") - SE_BEFORE ))"
echo '{"heartbeat_minutes": 5}' > "$PROJ/.hermes/journal.json"
J emit --json '{"kind":"task.started","task_id":"hb-cfg"}' >/dev/null
assert "설정 파일의 간격을 읽는다(5분 — 방금 것은 안 걸림)" "0" "$(J gap-check)"
rm -f "$PROJ/.hermes/journal.json"

echo ""
echo "== 6-d. 결정 병기 (목표 8) =="
python3 -c "
import sys;sys.path.insert(0,'$S')
import hermes_loop_decisions as d
d.record('$DB','loop-x',1,['DECISION: 사본을 쓴다 — 링크가 깨진다 — 저장소가 커진다'])" 2>/dev/null
assert "loop_decisions 에 남는다" "1" "$(q "select count(*) from loop_decisions where loop_id='loop-x'")"
assert "journal 에도 decision 이벤트로 남는다" "1" "$(q "select count(*) from journal_events where kind='decision' and task_id='loop-x'")"

echo ""
echo "== 6-e. 로테이션 제외 (목표 10) =="
ROTATE_SKILL="$REPO_ROOT/.hermes/skills/rotate-ephemeral-work-logs.md"   # 결정화 스킬 — .hermes/skills/ 는 .gitignore 라 그 스킬을 만든 기계에만 있다
if [[ -f "$ROTATE_SKILL" ]]; then
  assert "rotate 스킬에 제외 문장" "1" "$(grep -c 'journal_events.*로테이션 대상이 아니다' "$ROTATE_SKILL")"
else
  echo "  SKIP — rotate-ephemeral-work-logs.md 없음(기계 로컬 스킬). 통과로 세지 않는다 (2026-09-20: CI·다른 기계에서 늘 빨갰다)"
fi
assert "cleanup 이 journal_events 를 지우지 않음" "0" "$(grep -c 'DELETE FROM journal_events' "$REPO_ROOT/scripts/hermes-cleanup.py")"

echo ""
echo "== 6b. 자유 글 칸은 기록 전 마스킹된다 (계획 design-coverage-gaps 목표 1) =="
printf 'DEMO_DB_PASSWORD=Qz9!secretValue77\n' > "$PROJ/.env"
cp "$S/hermes_redact.py" "$PROJ/scripts/"
EVM=$(J emit --json '{"kind":"step","task_id":"t1","intent":"비번 Qz9!secretValue77 로 접속, 토큰 ghp_abcdefghijklmnopqrstuvwxyz0123456789 연락 010-1234-5678","lesson":"메일 someone@example.com","decision":"키 Qz9!secretValue77"}')
assert "마스킹 emit 성공" "1" "$([[ -n "$EVM" ]] && echo 1 || echo 0)"
ROW="$(python3 -c "
import sqlite3;r=sqlite3.connect('$DB').execute('select intent,lesson,decision from journal_events where event_id=?',('$EVM',)).fetchone();print(' | '.join(r))")"
assert ".env 값 원문 0건" "0" "$(printf '%s' "$ROW" | grep -c 'Qz9!secretValue77')"
assert "GitHub PAT 원문 0건" "0" "$(printf '%s' "$ROW" | grep -c 'ghp_abcdefghij')"
assert "전화번호 원문 0건" "0" "$(printf '%s' "$ROW" | grep -c '010-1234-5678')"
assert "메일 원문 0건" "0" "$(printf '%s' "$ROW" | grep -c 'someone@example.com')"
assert "[REDACTED: 토큰이 세 칸 모두에" "3" "$(printf '%s' "$ROW" | tr '|' '\n' | grep -c 'REDACTED:')"
assert "마스킹 밖 문장은 보존" "1" "$(printf '%s' "$ROW" | grep -c '로 접속')"
rm -f "$PROJ/.env"

echo "== 6c. 옛 CHECK 를 가진 DB 는 한 트랜잭션으로 옮겨진다 (목표 3) =="
OLD="$TMP/old.db"
python3 - "$OLD" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.executescript("""
CREATE TABLE journal_events (
  event_id TEXT PRIMARY KEY, ts TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('task.assigned','task.started','step','decision',
    'task.handoff','task.finished','correction','tombstone',
    'handoff.declined','handoff.question','handoff.expired','handoff.external')),
  universe_id TEXT NOT NULL, task_id TEXT NOT NULL, parent_task_id TEXT, caused_by TEXT,
  actor TEXT NOT NULL, requested_by TEXT, session_id TEXT,
  claimed TEXT CHECK (claimed IN ('success','failure','partial','blocked','abandoned') OR claimed IS NULL),
  verified TEXT CHECK (verified IN ('pass','fail','none') OR verified IS NULL),
  accepted TEXT, evidence TEXT, intent TEXT, lesson TEXT, decision TEXT);
CREATE INDEX journal_task_idx ON journal_events(task_id, ts);
CREATE INDEX journal_universe_idx ON journal_events(universe_id, ts);
CREATE TRIGGER journal_no_update BEFORE UPDATE ON journal_events BEGIN SELECT RAISE(ABORT,'journal_events is append-only'); END;
CREATE TRIGGER journal_no_delete BEFORE DELETE ON journal_events BEGIN SELECT RAISE(ABORT,'journal_events is append-only'); END;
""")
for i in range(3):
    con.execute("INSERT INTO journal_events(event_id,ts,kind,universe_id,task_id,actor,intent) VALUES (?,?,?,?,?,?,?)",
                (f"e{i}", "2026-09-17T00:00:0%dZ" % i, "step", "u", "t", "human:x", f"옛 행 {i}"))
con.commit()
PY
assert "옛 DB 에 agent.created 는 실패(전제)" "1" "$(python3 -c "
import sqlite3
try:
    sqlite3.connect('$OLD').execute(\"INSERT INTO journal_events(event_id,ts,kind,universe_id,task_id,actor) VALUES ('n','t','agent.created','u','t','human:x')\"); print(0)
except sqlite3.IntegrityError: print(1)")"
PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_journal_schema import ensure_schema
con = sqlite3.connect('$OLD'); ensure_schema(con); con.close()"
q2() { python3 -c "import sqlite3,sys;print(sqlite3.connect('$OLD').execute(sys.argv[1]).fetchone()[0])" "$1" 2>/dev/null; }
assert "행 3 보존" "3" "$(q2 'select count(*) from journal_events')"
assert "내용 보존" "옛 행 2" "$(q2 "select intent from journal_events where event_id='e2'")"
assert "새 kind INSERT 성공" "0" "$(python3 -c "
import sqlite3
sqlite3.connect('$OLD').execute(\"INSERT INTO journal_events(event_id,ts,kind,universe_id,task_id,actor) VALUES ('n','t','agent.created','u','t','human:x')\"); print(0)" 2>&1 | tail -1)"
assert "UPDATE 여전히 거부" "1" "$(python3 -c "
import sqlite3
try: sqlite3.connect('$OLD').execute(\"UPDATE journal_events SET intent='x' WHERE event_id='e0'\"); print(0)
except sqlite3.DatabaseError: print(1)")"
assert "DELETE 여전히 거부" "1" "$(python3 -c "
import sqlite3
try: sqlite3.connect('$OLD').execute(\"DELETE FROM journal_events WHERE event_id='e0'\"); print(0)
except sqlite3.DatabaseError: print(1)")"
assert "인덱스 2개" "2" "$(q2 "select count(*) from sqlite_master where type='index' and name like 'journal_%'")"
assert "disabled 사본 없음" "0" "$(q2 "select count(*) from sqlite_master where name like 'journal_events_disabled_%'")"
assert "두 번째 ensure_schema 는 무변경" "3" "$(PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_journal_schema import ensure_schema
con = sqlite3.connect('$OLD'); ensure_schema(con); print(con.execute('select count(*) from journal_events where kind=\'step\'').fetchone()[0])")"

echo "== 7. rollback 은 지우지 않는다 (목표 12) =="
BEFORE=$(q "select count(*) from journal_events")
J rollback --confirm >/dev/null
assert "테이블 이름만 바뀜(기록 보존)" "$BEFORE" "$(python3 -c "
import sqlite3;c=sqlite3.connect('$DB')
t=[r[0] for r in c.execute(\"select name from sqlite_master where name like 'journal_events_disabled_%'\")]
print(c.execute(f'select count(*) from {t[0]}').fetchone()[0])")"
J emit --json '{"kind":"step","task_id":"t1"}' >/dev/null 2>&1
assert "rollback 뒤 emit 은 조용히 성공(rc=0)" "0" "$?"
assert "rollback 뒤 보기는 빈 목록" "0" "$(J mismatch | python3 -c "import json,sys;print(len(json.load(sys.stdin)))")"
assert "--confirm 없으면 거부" "2" "$(J rollback >/dev/null 2>&1; echo $?)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
