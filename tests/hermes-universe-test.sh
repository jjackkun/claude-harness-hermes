#!/usr/bin/env bash
# 소우주 키(universe.id) 검증 (계획 docs/exec-plans/active/2026-09-15-universe-id-journal.md 목표 1·2).
#
#   - 설치 시 .hermes/universe.id 가 생기고 git 이 추적한다(.gitignore 예외)
#   - 재설치해도 값이 바뀌지 않는다
#   - 폴더 이름을 바꿔도 키가 같다 (폴더 이름을 키로 쓰던 것의 대체)
#   - 키가 없으면 폴더 이름으로 폴백하고 경고한다
#   - 설치 시 명부(.hermes/agents.json)에 main 한 명이 생긴다
#
# 격리: 저장소를 임시 사본에 복사하고 HOME 을 바꿔 실행한다.
# 실행: bash tests/hermes-universe-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail
export HARNESS_TOOL_INSTALL=0   # 설치기의 외부 도구 다운로드는 테스트에서 끈다(네트워크 0) — tests/tool-installers-test.sh 가 따로 실측

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
export HOME="$TMP/fakehome"
mkdir -p "$HOME"
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

SANDBOX="$TMP/harness"; mkdir -p "$SANDBOX"
tar -c --exclude=.git -C "$REPO_ROOT" . | tar -x -C "$SANDBOX"
rm -f "$SANDBOX/.installed-projects" "$SANDBOX/.installed-projects.codex"
git -C "$SANDBOX" init -q
git -C "$SANDBOX" remote add origin git@example.invalid:factory.git

PROJ="$TMP/proj"; mkdir -p "$PROJ"; git -C "$PROJ" init -q
UID_FILE="$PROJ/.hermes/universe.id"
ROSTER="$PROJ/.hermes/agents.json"
py() { PYTHONPATH="$SANDBOX/scripts" python3 -c "$1" "$@"; }

echo "== 1. 설치가 키를 만든다 (목표 1) =="
bash "$SANDBOX/project-claude.sh" "$PROJ" harness hermes >"$TMP/install.log" 2>&1
assert "설치 종료 코드 0" "0" "$?"
assert "universe.id 존재" "1" "$([[ -f "$UID_FILE" ]] && echo 1 || echo 0)"
FIRST="$(cat "$UID_FILE")"
assert "UUID 형식" "ok" "$(python3 -c "
import uuid,sys
try: uuid.UUID('$FIRST'); print('ok')
except ValueError: print('bad')")"
assert "git 추적 대상(무시 아님)" "1" "$(git -C "$PROJ" check-ignore -v .hermes/universe.id 2>/dev/null | grep -c '!.hermes/universe.id')"
assert "명부에 main 한 명" "main" "$(python3 -c "
import json; a=json.load(open('$ROSTER'))['agents']; print(a[0]['name'] if len(a)==1 else len(a))")"
assert "main 의 agent_id 는 UUIDv7" "7" "$(python3 -c "
import json,uuid; print(uuid.UUID(json.load(open('$ROSTER'))['agents'][0]['agent_id']).version)")"
assert "명부도 git 추적 대상" "1" "$(git -C "$PROJ" check-ignore -v .hermes/agents.json 2>/dev/null | grep -c '!.hermes/agents.json')"

echo ""
echo "== 2. 재설치해도 키가 그대로 (목표 1) =="
bash "$SANDBOX/project-claude.sh" "$PROJ" harness hermes >/dev/null 2>&1
assert "재설치 후 값 동일" "$FIRST" "$(cat "$UID_FILE")"
ROSTER_ID="$(python3 -c "import json;print(json.load(open('$ROSTER'))['agents'][0]['agent_id'])")"
bash "$SANDBOX/project-claude.sh" "$PROJ" harness hermes >/dev/null 2>&1
assert "재설치 후 main id 동일" "$ROSTER_ID" "$(python3 -c "import json;print(json.load(open('$ROSTER'))['agents'][0]['agent_id'])")"

echo ""
echo "== 3. 폴더 이름이 바뀌어도 키가 같다 (목표 2 의 전제) =="
MOVED="$TMP/renamed"; mv "$PROJ" "$MOVED"
assert "이름 바꾼 뒤에도 같은 키" "$FIRST" "$(PYTHONPATH="$SANDBOX/scripts" python3 -c "
from hermes_universe import universe_id; print(universe_id('$MOVED'))" 2>/dev/null)"
mv "$MOVED" "$PROJ"

echo ""
echo "== 4. 키가 없으면 폴더 이름으로 폴백 + 경고 =="
NOKEY="$TMP/nokey"; mkdir -p "$NOKEY"
out=$(PYTHONPATH="$SANDBOX/scripts" python3 -c "
from hermes_universe import universe_id; print(universe_id('$NOKEY'))" 2>"$TMP/warn.txt")
assert "폴더 이름으로 폴백" "nokey" "$out"
assert "경고 한 줄" "1" "$(grep -c 'universe.id 없음' "$TMP/warn.txt")"
assert "읽기만으로 키를 만들지 않음" "0" "$([[ -f "$NOKEY/.hermes/universe.id" ]] && echo 1 || echo 0)"

echo ""
echo "== 5. ensure 는 만들고, 두 번 불러도 같다 =="
NEW="$TMP/newproj"; mkdir -p "$NEW"
A=$(PYTHONPATH="$SANDBOX/scripts" python3 -c "
from hermes_universe import ensure_universe_id; print(ensure_universe_id('$NEW'))")
B=$(PYTHONPATH="$SANDBOX/scripts" python3 -c "
from hermes_universe import ensure_universe_id; print(ensure_universe_id('$NEW'))")
assert "두 번 불러도 같은 값" "$A" "$B"
assert "임시 파일이 남지 않음" "0" "$(find "$NEW/.hermes" -name '*.tmp' | wc -l)"

echo ""
echo "== 6. UUIDv7 은 시간순 정렬 =="
assert "연속 생성 10개가 문자열 정렬로도 시간순" "ok" "$(PYTHONPATH="$SANDBOX/scripts" python3 -c "
from hermes_uuid7 import uuid7_str
import time
v=[]
for _ in range(10):
    v.append(uuid7_str()); time.sleep(0.002)
print('ok' if v==sorted(v) else v)")"
assert "버전 필드가 7" "7" "$(PYTHONPATH="$SANDBOX/scripts" python3 -c "
import uuid; from hermes_uuid7 import uuid7; print(uuid7().version)")"

echo ""
echo "== 7. 세 스크립트가 키를 쓴다 — 폴더 이름이 바뀌어도 같은 project_id (목표 2) =="
DB="$PROJ/.hermes/state.db"
TR="$TMP/tr.jsonl"
python3 -c "
import json,sys
m=lambda t,x: json.dumps({'type':t,'message':{'role':t,'content':[{'type':'text','text':x}]}})
open(sys.argv[1],'w').write('\n'.join(
  m('user','universe 키 전환 확인 절차를 다시 점검 부탁합니다 %d'%i)+'\n'+
  m('assistant','universe 키 전환 규칙대로 진행합니다 점검 %d'%i) for i in range(3)))
" "$TR"
python3 "$PROJ/scripts/hermes-save-session.py" --db "$DB" --transcript "$TR" --session-id uni-a >/dev/null 2>&1
saved_a="$(python3 -c "
import sqlite3;print(sqlite3.connect('$DB').execute(
  \"select distinct project_id from session_history where session_id='uni-a'\").fetchone()[0])" 2>/dev/null)"
assert "save-session 이 universe.id 를 project_id 로 저장(session_history)" "$FIRST" "$saved_a"

MOVED2="$TMP/renamed2"; mv "$PROJ" "$MOVED2"
python3 "$MOVED2/scripts/hermes-save-session.py" --db "$MOVED2/.hermes/state.db" --transcript "$TR" --session-id uni-b >/dev/null 2>&1
saved_b="$(python3 -c "
import sqlite3;print(sqlite3.connect('$MOVED2/.hermes/state.db').execute(
  \"select distinct project_id from session_history where session_id='uni-b'\").fetchone()[0])" 2>/dev/null)"
assert "폴더 이름을 바꿔도 같은 project_id" "$FIRST" "$saved_b"
mv "$MOVED2" "$PROJ"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
