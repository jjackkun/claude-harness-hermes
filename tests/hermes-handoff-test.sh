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
HID2="$(py "$R; print(open_handoff('$DB','$P','agent:x',{'goal':'g2','done_when':'file:no.txt'},by='human:t'))")"
py "$R; resolve('$DB','$P','$HID2','declined','agent:x',reason='담당 아님')" >/dev/null
assert "declined 이벤트(claimed blocked)" 1 "$(q "select count(*) from journal_events where kind='handoff.declined' and claimed='blocked'")"
py "$R; resolve('$DB','$P','$HID2','question','agent:x',reason='inputs 부족')" >/dev/null
assert "question 이벤트" 1 "$(q "select count(*) from journal_events where kind='handoff.question'")"

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

echo ""
echo "== 5. 구 스키마·rollback (목표 11 하위호환) =="
OLD="$TMP/old"; mkdir -p "$OLD/scripts" "$OLD/.hermes"; cp "$S"/*.py "$OLD/scripts/"
python3 -c "import sqlite3;sqlite3.connect('$OLD/.hermes/state.db').execute('create table x(a)')"
assert "journal 없는 DB 에서 훅 exit 0" 0 "$(echo '{}' | CLAUDE_PROJECT_DIR="$OLD" bash "$H/claude-sessionstart-handoff-expiry.sh" >/dev/null 2>&1; echo $?)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
