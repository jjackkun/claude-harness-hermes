#!/usr/bin/env bash
# 리뷰가 기억이 되는 경로 (계획 2026-09-18-agent-teaching 목표 1·2, C-21) — 조직 2단·에이전트 3명 픽스처.
#   리뷰 절: finished → 바로 위 rank 에게 리뷰 봉투(지시, 자동) · 위 rank 없으면 human · 리뷰의 리뷰는 없음
#   기억 절: approved/corrected → 리뷰받은 에이전트 memory_events + MEMORY.md · about 형식 거부 · 본문 마스킹
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$REPO_ROOT/scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/fakehome"; mkdir -p "$HOME"
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
P="$TMP/proj"; mkdir -p "$P/.hermes"; git -C "$P" init -q; git -C "$P" config user.name tester
python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1; DB="$P/.hermes/state.db"
PYTHONPATH="$S" python3 -c "from hermes_universe import ensure_universe_id as e; e('$P')"
cat > "$P/.hermes/organization.yaml" <<'EOF2'
discipline: [백엔드, QA]
rank: [리드, 담당]
unit:
  users: {}
  공통: {}
EOF2
py() { PYTHONPATH="$S" python3 -c "$1"; }
py "from hermes_org import ensure_unit_ids; ensure_unit_ids('$P')
from hermes_roster import load_roster, add_agent, save_roster
from hermes_org import load_org
org=load_org('$P'); r=load_roster('$P')
for n,o in (('리드A',('백엔드','리드','users')),('담당B',('백엔드','담당','users')),('담당D',('QA','담당','공통'))):
    add_agent(r, n, dict(zip(('discipline','rank','unit'),o)), org, 'human:tester')
save_roster('$P', r)"
ID() { python3 -c "import json;print([a['agent_id'] for a in json.load(open('$P/.hermes/agents.json'))['agents'] if a['name']=='$1'][0])"; }
LA="$(ID 리드A)"; DB_="$(ID 담당B)"; DD="$(ID 담당D)"
R="from hermes_handoff import open_handoff, resolve
from hermes_review_chain import reviewer_for, open_review, close_review, record_teaching, TeachingError"
q() { python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone()[0])" "$DB" "$1" 2>/dev/null || echo err; }

echo "== 1. 리뷰어 선택 =="
assert "담당B(users) 의 리뷰어는 리드A" "agent:$LA" "$(py "$R; print(reviewer_for('$P','$DB_'))")"
assert "담당D(공통, 위 rank 없음) 의 리뷰어는 human" human "$(py "$R; print(reviewer_for('$P','$DD'))")"

echo "== 2. finished → 리뷰 봉투 자동 개봉 (목표 1) =="
touch "$P/ok.txt"
H1="$(py "$R; print(open_handoff('$DB','$P','agent:$DB_',{'goal':'users 조회 API 를 만든다','done_when':'file:ok.txt'},by='human:tester'))")"
py "$R; resolve('$DB','$P','$H1','finished','agent:$DB_')" >/dev/null
REV="$(q "select task_id from journal_events where kind='task.assigned' and intent like '리뷰:%' and parent_task_id='$H1'")"
assert "리뷰 봉투가 열림(parent = 원 봉투)" 1 "$([[ -n "$REV" && "$REV" != err ]] && echo 1 || echo 0)"
DEC="$(q "select decision from journal_events where task_id='$REV' and kind='task.assigned'")"
assert "리뷰어 = 리드A" 1 "$(grep -c "to=agent:$LA" <<<"$DEC")"
assert "kind = 지시(거절 불가)" 1 "$(grep -c 'kind=지시' <<<"$DEC")"
assert "decision 에 review-of·reviewee·verified" 1 "$(grep -c "review-of=$H1;reviewee=$DB_;verified=gate-pass" <<<"$DEC")"
assert "리뷰 봉투 done_when 은 manual" 1 "$(grep -c 'done_when=manual' <<<"$DEC")"
H2="$(py "$R; print(open_handoff('$DB','$P','agent:$DD',{'goal':'QA 체크','done_when':'file:ok.txt'},by='human:tester'))")"
py "$R; resolve('$DB','$P','$H2','finished','agent:$DD')" >/dev/null
assert "위 rank 없으면 human 에게 열림" 1 "$(q "select count(*) from journal_events where kind='task.assigned' and parent_task_id='$H2' and decision like '%to=human%'")"

echo "== 3. 리뷰 닫기 → 리뷰받은 에이전트의 기억 (목표 2) =="
OUT="$(py "$R; print(close_review('$DB','$P','$REV','corrected','agent:$LA',about='gate/r-size',body='400줄 넘기 전에 나눈다 — 담당 연락처 010-1111-2222')['reviewee'])")"
assert "close_review 가 reviewee(담당B) 를 돌려줌" "$DB_" "$OUT"
assert "담당B memory_events 에 memory.added 1" 1 "$(q "select count(*) from memory_events where agent_id='$DB_' and about='gate/r-size' and kind='memory.added'")"
assert "source_event = review:<id>:corrected:<리뷰어>" 1 "$(q "select count(*) from memory_events where agent_id='$DB_' and source_event='review:$REV:corrected:agent:$LA'")"
assert "본문은 기록 직전 마스킹(전화)" 1 "$(q "select count(*) from memory_events where agent_id='$DB_' and body like '%REDACTED:PHONE%'")"
assert "MEMORY.md 재생성됨(지적 포함)" 1 "$(grep -c '400줄 넘기 전에' "$P/.hermes/agents/$DB_/MEMORY.md")"
assert "리뷰 봉투는 finished 로 닫힘" 1 "$(q "select count(*) from journal_events where task_id='$REV' and kind='task.finished'")"
assert "리뷰의 리뷰는 열리지 않음" 0 "$(q "select count(*) from journal_events where kind='task.assigned' and parent_task_id='$REV'")"
H3="$(py "$R; print(open_handoff('$DB','$P','agent:$DB_',{'goal':'두 번째 일','done_when':'file:ok.txt'},by='human:tester'))")"
py "$R; resolve('$DB','$P','$H3','finished','agent:$DB_')" >/dev/null
REV3="$(q "select task_id from journal_events where kind='task.assigned' and parent_task_id='$H3'")"
py "$R; close_review('$DB','$P','$REV3','approved','agent:$LA',about='test/first')" >/dev/null
assert "approved 도 memory.added('…가 맞았다')" 1 "$(q "select count(*) from memory_events where agent_id='$DB_' and about='test/first' and body like '%맞았다%'")"

echo "== 4. about 형식·본문 거부 (목표 2) =="
for bad in "" "컴포넌트 규칙" "gate/" "unknown/x" "gate/한글"; do
  rc="$(py "$R
try: record_teaching('$DB','$P','$DB_','$bad','x','teach:human:t'); print('accepted')
except TeachingError: print('rejected')")"
  assert "about '$bad' 거부" rejected "$rc"
done
assert "corrected 에 body 없음 → 거부" rejected "$(py "$R
try: close_review('$DB','$P','$REV3','corrected','agent:$LA',about='gate/r-size'); print('accepted')
except TeachingError: print('rejected')")"
assert "리뷰 봉투가 아닌 id → 거부" rejected "$(py "$R
try: close_review('$DB','$P','$H1','approved','agent:$LA',about='gate/x'); print('accepted')
except TeachingError: print('rejected')")"

echo "== 5. 같은 about corrected 누적 수 (목표 3 준비) =="
for i in 1 2; do
  H="$(py "$R; print(open_handoff('$DB','$P','agent:$DB_',{'goal':'일 $i','done_when':'file:ok.txt'},by='human:tester'))")"
  py "$R; resolve('$DB','$P','$H','finished','agent:$DB_')" >/dev/null
  RV="$(q "select task_id from journal_events where kind='task.assigned' and parent_task_id='$H'")"
  N="$(py "$R; print(close_review('$DB','$P','$RV','corrected','agent:$LA',about='gate/r-size',body='또 400줄 넘김 $i')['corrected_count'])")"
done
assert "gate/r-size corrected 누적 3 (결정화 임계)" 3 "$N"

echo; echo "hermes-teaching: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
