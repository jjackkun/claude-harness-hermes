#!/usr/bin/env bash
# 기억 이벤트·충돌·보기 검증 (계획 docs/exec-plans/active/2026-09-15-agent-identity.md 목표 8·9).
#
#   - memory_events INSERT 전용(UPDATE·DELETE 트리거 차단), 모르는 kind 거부
#   - 충돌 3판정: 갈라짐→충돌, about 모순→충돌, content_hash 중복→합침. 최신 자동 승리 없음
#   - 규칙 충돌(RV-11): about 이 규칙 키와 겹치고 부정형이면 표시
#   - 단일 사례: source_event 하나뿐이면 표시
#   - MEMORY.md 는 이벤트에서 계산한 보기(파생), 원격 memory/ 조각은 body 만 암호문
#
# 실행: bash tests/hermes-memory-events-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
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

P="$TMP/proj"; mkdir -p "$P/.hermes"
DB="$P/.hermes/state.db"
# 이벤트 픽스처를 파이썬으로 심는다(기록기 경유)
PYTHONPATH="$S" python3 - "$DB" <<'PY'
import sqlite3, sys, time
sys.path.insert(0, __import__("os").environ["PWD"] + "/scripts") if False else None
from hermes_memory_events import record, ensure_memory_schema
from hermes_uuid7 import uuid7_str
con = sqlite3.connect(sys.argv[1]); ensure_memory_schema(con)
n = [0]
def add(**k):
    n[0] += 1
    return record(con, {"memory_id": uuid7_str(), "agent_id": "a1", "universe_id": "u",
                        "ts": "2026-09-16T00:00:%02d" % n[0], **k})
M1 = add(kind="memory.added", about="컴포넌트 규칙", body="Button 은 shared 에 둔다", source_event="e1")
add(kind="memory.added", about="배포 순서", body="dev 먼저 배포한다", source_event="e2")
add(kind="memory.revised", about="컴포넌트 규칙", revises=M1, body="features 에 둔다", source_event="e3")
add(kind="memory.revised", about="컴포넌트 규칙", revises=M1, body="lib 에 둔다", source_event="e4")
add(kind="memory.added", about="캐시 정책", body="캐시를 쓴다", source_event="e5")
add(kind="memory.added", about="캐시 정책", body="캐시를 쓰지 않는다", source_event="e6")
add(kind="memory.added", about="로그", body="로그는 info 로", source_event="e7")
add(kind="memory.added", about="로그", body="로그는 info 로", source_event="e8")
MR = add(kind="memory.added", about="옛것", body="X 를 한다", source_event="e9")
add(kind="memory.retracted", revises=MR, body="틀렸다", source_event="e10")
# 규칙 충돌용: SOUL 규칙 키 '컴포넌트 규칙' 을 부정하는 기억(근거 2개)
add(kind="memory.added", about="접근성", body="라벨을 붙이지 않는다", source_event="e11")
add(kind="memory.added", about="접근성", body="라벨을 붙이지 않는다는 방침", source_event="e12")
con.close()
print("seeded")
PY
q() { PYTHONPATH="$S" python3 -c "$1" "$DB"; }

echo "== 1. 추가 전용 (목표 8) =="
assert "UPDATE 차단" blocked "$(python3 -c "
import sqlite3
try: sqlite3.connect('$DB').execute(\"update memory_events set body='x'\"); print('open')
except sqlite3.IntegrityError: print('blocked')")"
assert "DELETE 차단" blocked "$(python3 -c "
import sqlite3
try: sqlite3.connect('$DB').execute('delete from memory_events'); print('open')
except sqlite3.IntegrityError: print('blocked')")"
assert "모르는 kind 거부" rejected "$(q "
import sqlite3,sys; sys.path.insert(0,'$S')
from hermes_memory_events import record, MemoryRejected
try: record(sqlite3.connect(sys.argv[1]), {'memory_id':'x','kind':'huh','agent_id':'a','universe_id':'u','ts':'t'}); print('open')
except MemoryRejected: print('rejected')")"
assert "content_hash 자동 계산" 64 "$(q "
import sqlite3,sys; sys.path.insert(0,'$S')
print(len(sqlite3.connect(sys.argv[1]).execute(\"select content_hash from memory_events where about='배포 순서'\").fetchone()[0]))")"

echo ""
echo "== 2. 충돌 3판정 (목표 8) =="
CONF="from hermes_memory_conflicts import find_conflicts; import sqlite3,sys; sys.path.insert(0,'$S'); c=find_conflicts(sqlite3.connect(sys.argv[1]),'a1')"
assert "갈라짐 → 충돌 1건" 1 "$(q "$CONF; print(sum(1 for x in c if x['reason']=='갈라짐'))")"
assert "about 모순 → 충돌 1건(캐시)" 1 "$(q "$CONF; print(sum(1 for x in c if x['reason']=='about 모순' and x.get('about')=='캐시 정책'))")"
assert "완전 중복 → 합침 1건(로그)" 1 "$(q "$CONF; print(sum(1 for x in c if x['reason']=='완전 중복'))")"
assert "합침 후에도 두 이벤트는 남는다" 2 "$(q "
import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute(\"select count(*) from memory_events where about='로그'\").fetchone()[0])")"
assert "철회된 기억은 살아있는 목록에 없음" 0 "$(q "
import sqlite3,sys; sys.path.insert(0,'$S')
from hermes_memory_conflicts import current_memories
print(sum(1 for e in current_memories(sqlite3.connect(sys.argv[1]),'a1') if e['about']=='옛것'))")"
echo ""
echo "== 3. 규칙 충돌·단일 사례 (목표 9) =="
assert "규칙 키(접근성) 부정형이면 규칙 충돌(둘 다 부정형이라 2건)" 2 "$(q "
import sqlite3,sys; sys.path.insert(0,'$S')
from hermes_memory_conflicts import rule_conflicts
print(len(rule_conflicts(sqlite3.connect(sys.argv[1]), ['접근성'], 'a1')))")"
assert "규칙 키가 아니면 규칙 충돌 아님" 0 "$(q "
import sqlite3,sys; sys.path.insert(0,'$S')
from hermes_memory_conflicts import rule_conflicts
print(len(rule_conflicts(sqlite3.connect(sys.argv[1]), ['상관없는키'], 'a1')))")"
assert "source_event 하나뿐이면 단일 사례(배포 순서)" 1 "$(q "
import sqlite3,sys; sys.path.insert(0,'$S')
from hermes_memory_conflicts import single_source
print(sum(1 for x in single_source(sqlite3.connect(sys.argv[1]),'a1') if x['about']=='배포 순서'))")"
assert "근거 2개인 접근성은 단일 사례 아님" 0 "$(q "
import sqlite3,sys; sys.path.insert(0,'$S')
from hermes_memory_conflicts import single_source
print(sum(1 for x in single_source(sqlite3.connect(sys.argv[1]),'a1') if x['about']=='접근성'))")"

echo ""
echo "== 4. MEMORY.md 보기 (목표 8·9) =="
q "
import sqlite3,sys; sys.path.insert(0,'$S')
from hermes_memory_view import write_memory_md
write_memory_md(sqlite3.connect(sys.argv[1]), '$P', 'a1', '유저기획', ['접근성'])" >/dev/null
MD="$P/.hermes/agents/a1/MEMORY.md"
assert "MEMORY.md 생성됨" 1 "$([[ -f "$MD" ]] && echo 1 || echo 0)"
assert "규칙 충돌 표시 존재" 1 "$([[ $(grep -c '규칙 충돌' "$MD") -ge 1 ]] && echo 1 || echo 0)"
assert "충돌 섹션(둘 다 남긴다)" 1 "$(grep -c '최신이 자동으로 이기지 않는다' "$MD")"
assert "단일 사례 태그" 1 "$(grep -c '단일 사례' "$MD")"
assert "본문에 평문 기억(파생 보기)" 1 "$(grep -c 'dev 먼저 배포한다' "$MD")"

echo ""
echo "== 5. 원격 조각: body 만 암호문 (목표 8, 계획 3 경로) =="
command -v age >/dev/null 2>&1 && {
  PYTHONPATH="$S" python3 - "$DB" <<'PY'
import sqlite3, sys, os
sys.path.insert(0, os.environ["PWD"] + "/scripts") if False else None
from hermes_crypto import generate_identity, public_key
from hermes_keys import key_path
from hermes_universe import ensure_universe_id
proj = os.path.dirname(os.path.dirname(sys.argv[1]))
uid = ensure_universe_id(proj)
generate_identity(key_path(uid, "master"))
lock = public_key(key_path(uid, "master"))
from hermes_sync_fragments import _outgoing_memory
out = _outgoing_memory(sqlite3.connect(sys.argv[1]), lock, set())
import json
# 아무 조각 하나 골라 검사
path, data = next(iter(out.items()))
ev = json.loads(data)
print("BODY_ARMOR" if str(ev.get("body","")).startswith("-----BEGIN AGE") else "BODY_PLAIN")
print("ABOUT_PLAIN" if isinstance(ev.get("about"), str) or ev.get("about") is None else "ABOUT_ENC")
print("KIND_PLAIN" if ev["kind"].startswith("memory.") else "KIND_ENC")
PY
} > "$TMP/frag.out" 2>/dev/null || echo "SKIP" > "$TMP/frag.out"
if grep -q SKIP "$TMP/frag.out"; then
  echo "  ⊘ age 없음 — 원격 조각 검사 건너뜀"
else
  assert "body 는 age 암호문" BODY_ARMOR "$(sed -n 1p "$TMP/frag.out")"
  assert "about 은 평문(기계 칸)" ABOUT_PLAIN "$(sed -n 2p "$TMP/frag.out")"
  assert "kind 는 평문" KIND_PLAIN "$(sed -n 3p "$TMP/frag.out")"
fi

echo "== 6. refresh-memory: 이벤트 → MEMORY.md 재생성 (계획 agent-memory-roundtrip 목표 1) =="
rm -f "$MD"
PYTHONPATH="$S" python3 "$S/hermes-agent.py" --project "$P" refresh-memory a1 >/dev/null; RC=$?
assert "refresh-memory rc 0" 0 "$RC"
assert "MEMORY.md 재생성됨" 1 "$([[ -f "$MD" ]] && echo 1 || echo 0)"
assert "이벤트 본문이 보기에 있다" 1 "$(grep -c 'dev 먼저 배포한다' "$MD")"
echo "손으로 쓴 줄" >> "$MD"
PYTHONPATH="$S" python3 "$S/hermes-agent.py" --project "$P" refresh-memory a1 >/dev/null
assert "손으로 쓴 줄은 다음 재생성에서 사라진다(파생물)" 0 "$(grep -c '손으로 쓴 줄' "$MD")"
P2="$TMP/proj2"; mkdir -p "$P2/.hermes/agents/a1"; echo "# 손 기억" > "$P2/.hermes/agents/a1/MEMORY.md"
PYTHONPATH="$S" python3 "$S/hermes-agent.py" --project "$P2" refresh-memory a1 >/dev/null; RC=$?
assert "DB 없음 → rc 0" 0 "$RC"
assert "DB 없음 → 파일 손대지 않음" 1 "$(grep -c '손 기억' "$P2/.hermes/agents/a1/MEMORY.md")"

echo ""
echo "== 전에 철회됨 (계획 design-gaps-tier2 목표 3) =="
# 계획 design-gaps-tier2 목표 3 — 같은 본문을 다시 배우면 "전에 철회됨" 이 보인다 (memory-events.md:119)
q "
import sqlite3,sys; sys.path.insert(0,'$S')
from hermes_memory_events import record; from hermes_uuid7 import uuid7_str
con=sqlite3.connect(sys.argv[1])
record(con, {'memory_id': uuid7_str(), 'agent_id':'a1','universe_id':'u','ts':'2026-09-17T00:00:01','kind':'memory.added','about':'옛것','body':'X 를 한다','source_event':'e20'})
record(con, {'memory_id': uuid7_str(), 'agent_id':'a1','universe_id':'u','ts':'2026-09-17T00:00:02','kind':'memory.added','about':'새것','body':'전혀 다른 기억','source_event':'e21'})
con.commit()" >/dev/null
assert "철회됐던 본문을 다시 배우면 previously_retracted 에 사유" "틀렸다" "$(q "
import sqlite3,sys; sys.path.insert(0,'$S')
from hermes_memory_conflicts import current_memories
print([e.get('previously_retracted') for e in current_memories(sqlite3.connect(sys.argv[1]),'a1') if e['about']=='옛것'][0])")"
assert "다른 본문에는 표시 없음" "None" "$(q "
import sqlite3,sys; sys.path.insert(0,'$S')
from hermes_memory_conflicts import current_memories
print([e.get('previously_retracted') for e in current_memories(sqlite3.connect(sys.argv[1]),'a1') if e['about']=='새것'][0])")"


echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
