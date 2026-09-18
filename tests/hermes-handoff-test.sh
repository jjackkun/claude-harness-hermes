#!/usr/bin/env bash
# 인계 봉투·done_when 검증 (계획 docs/exec-plans/active/2026-09-15-agent-identity.md 목표 10·11·12).
#
#   - 봉투 검증기: goal·done_when 없으면 차단, done_when 은 다섯 형식만, inputs 는 참조만(원문 거부)
#   - done_when 다섯 형식의 기계 검증(test·file·gate·commit·manual). manual 만 none
#   - 되돌아오는 네 방식이 이벤트로 남는다(finished·declined·question·expired)
#   - 만료: 세션 시작 훅이 기한 지난 미시작 봉투에 handoff.expired. expires_at 없으면 만료 없음
#   - task.started·handoff.question 있는 봉투는 만료 안 됨
#
# 실행: bash tests/hermes-handoff-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
H="$REPO_ROOT/assets/hooks"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/fakehome"; mkdir -p "$HOME"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

P="$TMP/proj"; mkdir -p "$P/scripts"; cp "$S"/*.py "$P/scripts/"; git -C "$P" init -q; git -C "$P" config user.name tester; git -C "$P" config user.email t@t
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$P')"
python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1
DB="$P/.hermes/state.db"
py() { PYTHONPATH="$S" python3 -c "$1" "$P"; }
q() { python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone()[0])" "$DB" "$1" 2>/dev/null || echo err; }

echo "== 1. 봉투 검증기 (목표 10) =="
V="import sys; sys.path.insert(0,'$S'); from hermes_handoff import validate_envelope, HandoffError"
chk() { py "$V
try: validate_envelope($1); print('accepted')
except HandoffError: print('rejected')"; }
assert "goal 비면 차단" rejected "$(chk "{'goal':'', 'done_when':'manual'}")"
assert "done_when 비면 차단" rejected "$(chk "{'goal':'x', 'done_when':''}")"
assert "done_when 형식 틀리면 차단" rejected "$(chk "{'goal':'x', 'done_when':'대충끝나면'}")"
assert "inputs 에 원문(공백 있는 문장) 차단" rejected "$(chk "{'goal':'x','done_when':'manual','inputs':['이건 원문 붙여넣기 입니다']}")"
assert "goal 여러 줄 차단" rejected "$(chk "{'goal':'x\ny', 'done_when':'manual'}")"
assert "정상 봉투 통과" accepted "$(chk "{'goal':'로그인 고치기','done_when':'file:src/a.js','inputs':['src/a.js','01a0a991-0000-7000-8000-000000000000']}")"

echo ""
echo "== 2. done_when 다섯 형식 (목표 12) =="
W="import sys; sys.path.insert(0,'$S'); from hermes_done_when import verify"
echo x > "$P/exists.txt"
git -C "$P" commit -q --allow-empty -m base
mkdir -p "$P/.harness"; printf '{"rule":"R-ok","verdict":"pass"}\n{"rule":"R-no","verdict":"block"}\n' > "$P/.harness/gate-events.jsonl"
assert "file: 존재 → pass" pass "$(py "$W; print(verify('file:exists.txt','$P'))")"
assert "file: 없음 → fail" fail "$(py "$W; print(verify('file:nope.txt','$P'))")"
assert "commit:HEAD → pass" pass "$(py "$W; print(verify('commit:HEAD','$P'))")"
assert "commit: 없는 해시 → fail" fail "$(py "$W; print(verify('commit:deadbeef1234','$P'))")"
assert "gate: pass 규칙 → pass" pass "$(py "$W; print(verify('gate:R-ok','$P'))")"
assert "gate: block 규칙 → fail" fail "$(py "$W; print(verify('gate:R-no','$P'))")"
assert "manual → none (이 형식만)" none "$(py "$W; print(verify('manual','$P'))")"
echo 'exit 0' > "$P/tests-ok.sh"; echo 'exit 1' > "$P/tests-no.sh"
assert "test: 통과 스크립트 → pass" pass "$(py "$W; print(verify('test:tests-ok.sh','$P'))")"
assert "test: 실패 스크립트 → fail" fail "$(py "$W; print(verify('test:tests-no.sh','$P'))")"

echo ""
echo "== 3. 되돌아오는 네 방식 (목표 10) =="
R="import sys; sys.path.insert(0,'$S'); from hermes_handoff import open_handoff, resolve"
HID="$(py "$R
print(open_handoff('$DB','$P','agent:x',{'goal':'g','done_when':'file:exists.txt'},by='human:tester'))")"
assert "open → task.assigned 1건" 1 "$(q "select count(*) from journal_events where kind='task.assigned' and task_id='$HID'")"
assert "task.assigned 지시자 = 사람" 1 "$(q "select count(*) from journal_events where task_id='$HID' and requested_by='human:tester'")"
py "$R; resolve('$DB','$P','$HID','finished','agent:x')" >/dev/null
assert "finished → file 존재라 verified pass" pass "$(q "select verified from journal_events where kind='task.finished' and task_id='$HID'")"
# 보내는 쪽이 사람이면 지시라 거절 불가 — 거절 경로는 명부 밖 에이전트(요청·미상)로 낸다
HID2="$(py "$R; print(open_handoff('$DB','$P','agent:x',{'goal':'g2','done_when':'file:no.txt'},by='agent:y'))")"
py "$R; resolve('$DB','$P','$HID2','declined','agent:x',reason='담당 아님')" >/dev/null
assert "declined 이벤트(claimed blocked)" 1 "$(q "select count(*) from journal_events where kind='handoff.declined' and claimed='blocked'")"
py "$R; resolve('$DB','$P','$HID2','question','agent:x',reason='inputs 부족')" >/dev/null
assert "question 이벤트" 1 "$(q "select count(*) from journal_events where kind='handoff.question'")"

echo ""
echo "== 3b. 봉투 kind·return_to·constraints·blocked (계획 design-coverage-gaps 목표 4·5·6) =="
# 명부·조직: 리드(위) → 담당(아래) = 지시, 같은 unit 담당끼리 = 협업, 다른 unit = 요청
cat > "$P/.hermes/organization.yaml" <<'EOF2'
discipline: [백엔드, QA]
rank: [리드, 담당]
unit:
  users: {}
  공통: {}
EOF2
py "import sys; sys.path.insert(0,'$S'); from hermes_org import ensure_unit_ids; ensure_unit_ids('$P')
from hermes_roster import load_roster, add_agent, save_roster
from hermes_org import load_org
org=load_org('$P'); r=load_roster('$P')
for n,o in (('리드A',('백엔드','리드','users')),('담당B',('백엔드','담당','users')),('담당C',('QA','담당','users')),('담당D',('QA','담당','공통'))):
    add_agent(r, n, dict(zip(('discipline','rank','unit'),o)), org, 'human:tester')
save_roster('$P', r)"
ID() { python3 -c "import json;print([a['agent_id'] for a in json.load(open('$P/.hermes/agents.json'))['agents'] if a['name']=='$1'][0])"; }
LA="agent:$(ID 리드A)"; DB_="agent:$(ID 담당B)"; DC="agent:$(ID 담당C)"; DD="agent:$(ID 담당D)"
ENV="{'goal':'g','done_when':'manual','constraints':'결제 모듈은 손대지 않는다'}"
H_DIR="$(py "$R; print(open_handoff('$DB','$P','$DB_',$ENV,by='$LA'))")"
H_COL="$(py "$R; print(open_handoff('$DB','$P','$DC',$ENV,by='$DB_'))")"
H_REQ="$(py "$R; print(open_handoff('$DB','$P','$DD',$ENV,by='$DB_'))")"
H_HUM="$(py "$R; print(open_handoff('$DB','$P','$DB_',$ENV,by='human:tester'))")"
kind_of() { q "select decision from journal_events where kind='task.assigned' and task_id='$1'" | grep -o 'kind=[^ ]*'; }
assert "리드→담당 = 지시" "kind=지시" "$(kind_of "$H_DIR")"
assert "같은 unit 담당끼리 = 협업" "kind=협업" "$(kind_of "$H_COL")"
assert "다른 unit = 요청" "kind=요청" "$(kind_of "$H_REQ")"
assert "사람→에이전트 = 지시" "kind=지시" "$(kind_of "$H_HUM")"
assert "return_to 기본 = from" "1" "$(q "select count(*) from journal_events where task_id='$H_DIR' and decision like '%return_to=$LA%'")"
assert "constraints 보존(decision)" "1" "$(q "select count(*) from journal_events where task_id='$H_DIR' and decision like '%constraints=결제 모듈은 손대지 않는다%'")"
assert "지시 declined → 거부" "1" "$(py "$R
try: resolve('$DB','$P','$H_DIR','declined','$DB_',reason='싫다'); print(0)
except Exception as e: print(1 if '지시' in str(e) else str(e))")"
assert "협업 declined → 기록" "1" "$(py "$R; resolve('$DB','$P','$H_COL','declined','$DC',reason='담당 아님')"; q "select count(*) from journal_events where kind='handoff.declined' and task_id='$H_COL'")"
assert "요청 declined 사유 없음 → 거부" "1" "$(py "$R
try: resolve('$DB','$P','$H_REQ','declined','$DD'); print(0)
except Exception as e: print(1 if '사유' in str(e) else str(e))")"
py "$R; resolve('$DB','$P','$H_DIR','blocked','$DB_',reason='rule:R-secret')" >/dev/null
assert "blocked → task.finished claimed=blocked" "1" "$(q "select count(*) from journal_events where kind='task.finished' and task_id='$H_DIR' and claimed='blocked'")"
assert "blocked evidence.reason=rule:R-secret" "1" "$(q "select count(*) from journal_events where kind='task.finished' and task_id='$H_DIR' and evidence like '%\"reason\": \"rule:R-secret\"%'")"
assert "blocked 인데 rule: 꼴 아님 → 거부" "1" "$(py "$R
try: resolve('$DB','$P','$H_HUM','blocked','$DB_',reason='그냥'); print(0)
except Exception as e: print(1 if 'rule:' in str(e) else str(e))")"
assert "명부에 없는 에이전트끼리 → 요청(미상)" "kind=요청(미상)" "$(kind_of "$HID2")"

echo ""
echo "== 3c. 2차 되묻기 승격·우선순위 대기열 (계획 design-gaps-tier2 목표 5·6) =="
# 목표 5 — 같은 봉투의 두 번째 handoff.question 은 사람에게 올라간다 (handoff-contract.md:83)
HQ="$(py "$R; print(open_handoff('$DB','$P','$DC',{'goal':'되묻기','done_when':'manual'},by='$LA'))")"
py "$R; resolve('$DB','$P','$HQ','question','$DC',reason='inputs 칸이 비었다')" >/dev/null
assert "1차 되묻기 → escalate 없음" 0 "$(q "select count(*) from journal_events where kind='handoff.question' and task_id='$HQ' and decision like '%escalate=human%'")"
py "$R; resolve('$DB','$P','$HQ','question','$DC',reason='done_when 이 모호하다')" >/dev/null
assert "2차 되묻기 → decision=escalate=human" 1 "$(q "select count(*) from journal_events where kind='handoff.question' and task_id='$HQ' and decision like '%escalate=human%'")"
assert "gaps 의 escalations 에 그 봉투" 1 "$(py "import sys,sqlite3; sys.path.insert(0,'$S'); from hermes_journal_views import escalations
print(sum(1 for e in escalations(sqlite3.connect('$DB')) if e['task_id']=='$HQ'))")"
# 목표 6 — 열린 봉투는 지시 → 협업 → 요청, 같은 종류는 먼저 온 순 (handoff-contract.md:66)
Q1="$(py "$R; print(open_handoff('$DB','$P','$DC',{'goal':'요청1','done_when':'manual'},by='$DD'))")"
sleep 1
Q2="$(py "$R; print(open_handoff('$DB','$P','$DC',{'goal':'지시1','done_when':'manual'},by='$LA'))")"
sleep 1
Q3="$(py "$R; print(open_handoff('$DB','$P','$DC',{'goal':'협업1','done_when':'manual'},by='$DB_'))")"
sleep 1
Q4="$(py "$R; print(open_handoff('$DB','$P','$DC',{'goal':'지시2','done_when':'manual'},by='$LA'))")"
py "$R; resolve('$DB','$P','$Q3','finished','$DC')" >/dev/null   # 닫힌 봉투는 대기열에서 빠진다
QUEUE="$(py "import sys; sys.path.insert(0,'$S'); from hermes_handoff_queue import queue
print(' '.join(q['goal'] for q in queue('$DB','$DC')))")"
assert "대기열 = 지시1 지시2 요청1 (협업1 은 닫힘·되묻기 봉투는 별도)" "지시1 지시2 요청1" "$(python3 -c "
q='$QUEUE'.split(); print(' '.join(x for x in q if x in ('지시1','지시2','요청1','협업1')))")"
# 리뷰 HIGH — return_to 가 조회 대상과 같은 봉투(리드A 가 담당B 에게 보낸 것)는 리드A 의 대기열에 뜨면 안 된다
QX="$(py "$R; print(open_handoff('$DB','$P','$DB_',{'goal':'남의봉투','done_when':'manual'},by='$LA'))")"
assert "return_to 가 나인 남의 봉투는 내 대기열에 없다" 0 "$(py "import sys; sys.path.insert(0,'$S'); from hermes_handoff_queue import queue
print(sum(1 for q in queue('$DB','$LA') if q['goal']=='남의봉투'))")"
assert "그 봉투는 받는 쪽(담당B) 대기열에 있다" 1 "$(py "import sys; sys.path.insert(0,'$S'); from hermes_handoff_queue import queue
print(sum(1 for q in queue('$DB','$DB_') if q['goal']=='남의봉투'))")"
assert "대기열 항목에 kind" 1 "$(py "import sys; sys.path.insert(0,'$S'); from hermes_handoff_queue import queue
print(1 if all('kind' in q for q in queue('$DB','$DC')) else 0)")"

echo ""
echo "== 3d. 다른 소우주의 일 — 사람 경유 (계획 unplanned-decisions 목표 3, H-04) =="
UNI_ME="$(cat "$P/.hermes/universe.id")"
HX="$(py "$R; print(open_handoff('$DB','$P','$DC',{'goal':'다른 저장소 API 필드 추가','done_when':'manual','universe_id':'01a0b000-0000-7000-8000-00000000dead'},by='$LA'))")"
assert "다른 소우주 → handoff.external 1건" 1 "$(q "select count(*) from journal_events where kind='handoff.external' and task_id='$HX'")"
assert "다른 소우주 → task.assigned 없음" 0 "$(q "select count(*) from journal_events where kind='task.assigned' and task_id='$HX'")"
assert "decision 에 external=<대상>·route=human" 1 "$(q "select count(*) from journal_events where task_id='$HX' and decision like 'external=01a0b000-0000-7000-8000-00000000dead route=human%'")"
assert "대기열에 없음(사람이 처리)" 0 "$(py "import sys; sys.path.insert(0,'$S'); from hermes_handoff_queue import queue
print(sum(1 for x in queue('$DB','$DC') if x['task_id']=='$HX'))")"
HS2="$(py "$R; print(open_handoff('$DB','$P','$DC',{'goal':'같은 소우주','done_when':'manual','universe_id':'$UNI_ME'},by='$LA'))")"
assert "같은 소우주 id 는 평소 경로(task.assigned)" 1 "$(q "select count(*) from journal_events where kind='task.assigned' and task_id='$HS2'")"

echo ""
echo "== 4. 만료 (목표 11) =="
HE="$(py "$R; print(open_handoff('$DB','$P','agent:x',{'goal':'급함','done_when':'manual','expires_at':'2000-01-01T00:00:00Z'},by='human:t'))")"
HN="$(py "$R; print(open_handoff('$DB','$P','agent:x',{'goal':'기한없음','done_when':'manual'},by='human:t'))")"
OUT="$(echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$P" bash "$H/claude-sessionstart-handoff-expiry.sh" 2>&1)"
assert "시작 훅 exit 0" 0 "$?"
assert "기한 지난 봉투가 만료됨" 1 "$(q "select count(*) from journal_events where kind='handoff.expired' and task_id='$HE'")"
assert "기한 없는 봉투는 만료 안 됨" 0 "$(q "select count(*) from journal_events where kind='handoff.expired' and task_id='$HN'")"
assert "만료 알림 stderr" 1 "$(grep -c 'handoff-expiry' <<<"$OUT")"
assert "훅 stdout 무출력" "" "$(echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$P" bash "$H/claude-sessionstart-handoff-expiry.sh" 2>/dev/null)"
# task.started 있는 봉투는 만료 안 됨
HS="$(py "$R; print(open_handoff('$DB','$P','agent:x',{'goal':'시작됨','done_when':'manual','expires_at':'2000-01-01T00:00:00Z'},by='human:t'))")"
py "import sys;sys.path.insert(0,'$S');from hermes_journal import emit; emit('$DB','$P',{'kind':'task.started','task_id':'$HS','actor':'agent:x'})" >/dev/null
echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$P" bash "$H/claude-sessionstart-handoff-expiry.sh" >/dev/null 2>&1
assert "이미 시작된 봉투는 만료 안 됨" 0 "$(q "select count(*) from journal_events where kind='handoff.expired' and task_id='$HS'")"
# 계획 design-gaps-tier2 목표 4 — 만료 원인 기계 판정 (handoff-contract.md:79)
reason_of() { q "select evidence from journal_events where kind='handoff.expired' and task_id='$1'" | grep -o 'expired:[a-z-]*'; }
assert "미시작 만료 → expired:unstarted" "expired:unstarted" "$(reason_of "$HE")"
HK="$(py "$R; print(open_handoff('$DB','$P','agent:x',{'goal':'열쇠없음','done_when':'manual','expires_at':'2000-01-01T00:00:00Z'},by='human:t'))")"
echo '{"remote":"x"}' > "$P/.hermes/sync.json"
HOME="$TMP/nokeyhome" bash -c "echo '{\"source\":\"startup\"}' | CLAUDE_PROJECT_DIR='$P' bash '$H/claude-sessionstart-handoff-expiry.sh'" >/dev/null 2>&1
assert "sync 설정 있고 열쇠 없음 → expired:key-missing" "expired:key-missing" "$(reason_of "$HK")"
rm -f "$P/.hermes/sync.json"
HR="$(py "$R; print(open_handoff('$DB','$P','agent:x',{'goal':'러너죽음','done_when':'manual','expires_at':'2000-01-01T00:00:00Z'},by='human:t'))")"
mkdir -p "$P/.hermes/summons"; echo "$HR" > "$P/.hermes/summons/deadbeef.pending"
echo '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$P" bash "$H/claude-sessionstart-handoff-expiry.sh" >/dev/null 2>&1
assert "pending 파일 남아 있음 → expired:runner-dead" "expired:runner-dead" "$(reason_of "$HR")"
rm -f "$P/.hermes/summons/deadbeef.pending"

echo ""
echo "== 5. 구 스키마·rollback (목표 11 하위호환) =="
OLD="$TMP/old"; mkdir -p "$OLD/scripts" "$OLD/.hermes"; cp "$S"/*.py "$OLD/scripts/"
python3 -c "import sqlite3;sqlite3.connect('$OLD/.hermes/state.db').execute('create table x(a)')"
assert "journal 없는 DB 에서 훅 exit 0" 0 "$(echo '{}' | CLAUDE_PROJECT_DIR="$OLD" bash "$H/claude-sessionstart-handoff-expiry.sh" >/dev/null 2>&1; echo $?)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
