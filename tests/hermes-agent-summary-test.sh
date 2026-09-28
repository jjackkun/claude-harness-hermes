#!/usr/bin/env bash
# 대화 요약을 에이전트별 기억으로 (계획 docs/exec-plans/completed/2026-09-28-agent-conversation-memory.md 목표 1~6, C-29).
#
#   1 스키마: 옛 session_summary 에 agent_id 칸을 더한다(두 번 돌려도 하나 · 기존 행 보존) · 다섯 생성 지점이 모두 보장 함수를 부른다
#   2 방: 방 주인 기록(match=owner)이 있는 세션의 요약 → agent_id = 주인 명부 id · 없으면 NULL
#   3 @ 호출: SubagentStart 기록(match=mention)이 있는 서브에이전트만 → sub:<id> 행, agent_id = 명부 id · 기록 없음(내부 보조)·명부 밖 → 행 0
#   4 주입: 출근 본문에 "나와 나눈 최근 대화" — 자기 키 요약만 · 4,096 B 상한 · 은퇴자 → 본문 없음
#   5 공통만: 회상(최신 1건·키워드)·드리밍 재료에 에이전트 키 요약이 안 들어간다
#   6 운반: 에이전트 요약은 운반에 안 실린다(A-11) · 들여오기가 보존 · 구버전(칸 없는) 몸통이 와도 로컬 agent_id 유지
#   자기 검사: 주입 구획을 끄면 4 가 빨개진다
#
# 요약용 모델 호출은 가짜 claude(고정 5칸 JSON)로 대신한다 — 사용량 0.
# 실행: bash tests/hermes-agent-summary-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset HERMES_AGENT_ID HERMES_SUMMON_NONCE

GQ="01a0ae58-6aa6-7202-ae81-7d27af7b5617"; BL="01a0b728-2040-7e30-ab2d-cee957be526e"; OLD="01a0ae58-6a84-75bd-8bfa-9c85c2ce2be4"
P="$T/proj"; mkdir -p "$P/.hermes/agents/$GQ" "$P/.hermes/agents/$BL" "$P/.hermes/agents/$OLD"
ln -s "$S" "$P/scripts"
cat > "$P/.hermes/agents.json" <<EOF
{"agents": [
  {"agent_id": "$GQ", "name": "게이트QA", "slug": "gate-qa", "status": "probation", "org": {}},
  {"agent_id": "$BL", "name": "백로그 관리자", "slug": "backlog-manager", "status": "probation", "org": {}},
  {"agent_id": "$OLD", "name": "옛담당", "slug": "old-hand", "status": "retired", "org": {}}
]}
EOF
for id in "$GQ" "$BL" "$OLD"; do printf '# 정체성\n\n## 역할\n시험 역할.\n' > "$P/.hermes/agents/$id/SOUL.md"; done
DB="$P/.hermes/state.db"
q() { python3 -c "import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone(); print(r[0] if r else '')" "$DB" "$1"; }
J() { env -u HERMES_AGENT_ID python3 "$S/hermes-journal.py" --project "$P" emit --json "$1" >/dev/null 2>&1; }

echo "== 1. 스키마"
python3 - "$DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE session_summary (session_id TEXT PRIMARY KEY, project_id TEXT, slots_json TEXT, "
          "last_msg_count INTEGER DEFAULT 0, turn_count INTEGER DEFAULT 0, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)")
c.execute("INSERT INTO session_summary VALUES ('old-1','p','{\"facts\":[\"옛 공통\"]}',3,1,'2026-09-01 00:00:00')")
c.commit()
PY
for i in 1 2; do PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_summary_owner import ensure_agent_column
c=sqlite3.connect('$DB'); ensure_agent_column(c); c.commit()"; done
assert "agent_id 칸 하나" 1 "$(q "SELECT COUNT(*) FROM pragma_table_info('session_summary') WHERE name='agent_id'")"
assert "기존 행 보존(agent_id NULL)" "old-1|" "$(q "SELECT session_id||'|'||IFNULL(agent_id,'') FROM session_summary")"
for f in hermes-init.py hermes-recall.py hermes-summarize.py hermes-dream.py hermes_sync_learning.py; do
  assert "  $f 가 보장 함수를 부른다" 1 "$(grep -c 'ensure_agent_column(' "$S/$f" | awk '{print ($1>0)?1:0}')"
done

echo "== 2. 방의 요약은 방 주인 몫"
FAKE="$T/bin"; mkdir -p "$FAKE"
cat > "$FAKE/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo '{"decisions":["요약시험 결정"],"open":[],"prefs":[],"facts":["요약시험 사실"],"next":[]}'
EOF
chmod +x "$FAKE/claude"
mktr() { python3 -c "
import json,sys
with open(sys.argv[1],'w') as f:
    for r,t in (('user','안녕 게이트'),('assistant','네 게이트QA 입니다')):
        f.write(json.dumps({'type':r,'message':{'role':r,'content':t}},ensure_ascii=False)+'\n')" "$1"; }
summ() {  # summ <session> <transcript> [추가 인자]
  local sid="$1" tp="$2"; shift 2
  PATH="$FAKE:$PATH" python3 "$S/hermes-summarize.py" --db "$DB" --transcript "$tp" --project-id p --session-id "$sid" --project-dir "$P" "$@" >/dev/null 2>&1
}
ROOM="aaaa1111-0000-0000-0000-000000000001"; MAIN="cccc3333-0000-0000-0000-000000000003"
J "{\"kind\":\"task.assigned\",\"session_id\":\"$ROOM\",\"actor\":\"agent:gate-qa\",\"decision\":\"match=owner slug=gate-qa agent=$GQ\",\"evidence\":{\"template\":\"gate-qa\"}}"
mktr "$T/room.jsonl"; mktr "$T/main.jsonl"
summ "$ROOM" "$T/room.jsonl"; summ "$MAIN" "$T/main.jsonl"
assert "방 세션 요약 → agent_id = 게이트QA" "$GQ" "$(q "SELECT agent_id FROM session_summary WHERE session_id='$ROOM'")"
assert "주인 없는 세션 → NULL(공통)" "" "$(q "SELECT IFNULL(agent_id,'') FROM session_summary WHERE session_id='$MAIN'")"
summ "$ROOM" "$T/room.jsonl"
assert "다시 요약해도 주인 유지" "$GQ" "$(q "SELECT agent_id FROM session_summary WHERE session_id='$ROOM'")"

echo "== 3. @ 호출의 대화"
HOOK="$REPO_ROOT/assets/hooks/claude-subagentstop-summarize.sh"
SUB="a1b2c3d4e5f6a7b8"; INNER="ffff0000ffff0000"
J "{\"kind\":\"task.assigned\",\"task_id\":\"$SUB\",\"session_id\":\"$MAIN\",\"decision\":\"match=mention slug=backlog-manager agent=$BL\",\"evidence\":{\"template\":\"backlog-manager\"}}"
mktr "$T/sub.jsonl"; mktr "$T/inner.jsonl"
stop() {  # stop <sub id> <agent_type> <transcript>
  python3 -c "import json,sys; print(json.dumps({'session_id':'$MAIN','agent_id':sys.argv[1],'agent_type':sys.argv[2],'agent_transcript_path':sys.argv[3]}))" "$1" "$2" "$3" \
    | PATH="$FAKE:$PATH" CLAUDE_PROJECT_DIR="$P" HERMES_SUMMARY_FOREGROUND=1 bash "$HOOK" >/dev/null 2>&1
}
stop "$SUB" backlog-manager "$T/sub.jsonl"
assert "Start 기록 있는 호출 → sub:<id> 행, 백로그 관리자 몫" "$BL" "$(q "SELECT agent_id FROM session_summary WHERE session_id='sub:$SUB'")"
stop "$INNER" gate-qa "$T/inner.jsonl"
assert "Start 기록 없는 호출(내부 보조) → 행 0" 0 "$(q "SELECT COUNT(*) FROM session_summary WHERE session_id='sub:$INNER'")"
stop "eeee9999eeee9999" Explore "$T/inner.jsonl"
assert "명부 밖(Explore) → 행 0" 0 "$(q "SELECT COUNT(*) FROM session_summary WHERE session_id='sub:eeee9999eeee9999'")"

echo "== 4. 주입"
render() { PYTHONPATH="$S" python3 "$S/hermes_soul_render.py" "$P" "$1" 2>/dev/null; }
O="$(render "$GQ")"
assert "게이트QA 본문에 대화 구획" 1 "$(has "$O" '--- 나와 나눈 최근 대화 ---')"
assert "  자기 요약 내용" 1 "$(has "$O" '요약시험 사실')"
O="$(render "$BL")"
assert "백로그 관리자 본문에 자기(@) 요약" 1 "$(has "$O" '요약시험 결정')"
python3 - "$DB" "$GQ" <<'PY'
import json, sqlite3, sys
c = sqlite3.connect(sys.argv[1])
big = json.dumps({"facts": ["긴줄" * 400] * 5}, ensure_ascii=False)
for i in range(4):
    c.execute("INSERT INTO session_summary (session_id, project_id, slots_json, agent_id, updated_at) VALUES (?,?,?,?,?)",
              (f"big-{i}", "p", big, sys.argv[2], f"2026-09-2{i} 00:00:00"))
c.execute("INSERT INTO session_summary (session_id, project_id, slots_json, updated_at) VALUES ('common-x','p','{\"facts\":[\"공통비밀\"]}','2026-09-29 00:00:00')")
c.commit()
PY
O="$(render "$GQ")"
SEC="$(awk '/--- 나와 나눈 최근 대화 ---/{f=1} f' <<<"$O")"
assert "  구획이 4,096 B 이하" 1 "$(( $(printf '%s' "$SEC" | wc -c) <= 4096 + 64 ))"
assert "  공통 요약은 안 들어감" 0 "$(has "$O" '공통비밀')"
assert "은퇴자 → 본문 없음" 0 "$(render "$OLD" | wc -c | tr -d ' ')"

echo "== 5. 공통만 쓰는 곳"
R="$(PYTHONPATH="$S" python3 -c "
import importlib.util
s=importlib.util.spec_from_file_location('r','$S/hermes-recall.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
import sqlite3; c=sqlite3.connect('$DB'); r=m.latest_other_summary(c,'p','none'); print(r['session_id'] if r else '')" 2>/dev/null)"
assert "회상(최신 1건) → 공통 요약" "common-x" "$R"
R="$(PYTHONPATH="$S" python3 -c "
import importlib.util
s=importlib.util.spec_from_file_location('d','$S/hermes-dream.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
import sqlite3; c=sqlite3.connect('$DB'); print(' '.join(sorted(x['session_id'] for x in m.collect_summaries(c,None))))" 2>/dev/null)"
assert "드리밍 재료에 에이전트 요약 없음" "$MAIN common-x old-1" "$R"

echo "== 6. 운반"
R="$(PYTHONPATH="$S" python3 -c "
import sqlite3, json; from hermes_sync_learning import _outgoing_summaries
c=sqlite3.connect('$DB'); out=_outgoing_summaries(c, lambda t: t, set())
print(sum(1 for k in out if '/$ROOM/' in k))" 2>/dev/null)"
assert "운반에 에이전트 요약은 안 실린다(git 파일 conversations/ 가 옮긴다, A-11)" 0 "$R"
PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_sync_learning import _import_summary
c=sqlite3.connect('$DB')
_import_summary(c,'u',{'session_id':'$ROOM','project_id':'p','slots_json':'{}','updated_at':'2099-01-01 00:00:00'})
_import_summary(c,'u',{'session_id':'far-1','project_id':'p','slots_json':'{}','updated_at':'2099-01-01 00:00:00','agent_id':'$BL'})
c.commit()" 2>/dev/null
assert "구버전 몸통(칸 없음) → 로컬 agent_id 유지" "$GQ" "$(q "SELECT agent_id FROM session_summary WHERE session_id='$ROOM'")"
assert "새 몸통의 agent_id 가 들어온다" "$BL" "$(q "SELECT agent_id FROM session_summary WHERE session_id='far-1'")"

echo "== 7. 리뷰 반영 — 동시 칸 추가 · 이력 인덱스 · 들여오기 한 문장"
R="$(PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_summary_owner import _add_column
c=sqlite3.connect('$DB'); _add_column(c, 'agent_id'); _add_column(c, 'agent_id'); print('ok')" 2>&1 | tail -1)"
assert "이미 있는 칸을 또 더해도 죽지 않는다(동시 실행)" ok "$R"
assert "이력에 session_id 인덱스" 1 "$(q "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='journal_session_kind_idx'")"
PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_sync_learning import _import_summary
c=sqlite3.connect('$DB')
_import_summary(c,'u',{'session_id':'far-1','project_id':'p','slots_json':'{\"facts\":[\"옛것\"]}','updated_at':'2000-01-01 00:00:00'})
c.commit()" 2>/dev/null
assert "더 오래된 몸통은 덮지 않는다" "{}" "$(q "SELECT slots_json FROM session_summary WHERE session_id='far-1'")"
PYTHONPATH="$S" python3 -c "
import sqlite3; from hermes_sync_learning import _import_summary
c=sqlite3.connect('$DB')
_import_summary(c,'u',{'session_id':'far-1','project_id':'p','slots_json':'{\"facts\":[\"새것\"]}','updated_at':'2100-01-01 00:00:00'})
c.commit()" 2>/dev/null
assert "더 새 몸통(칸 없음)은 본문만 갱신, 주인 유지" "$BL" "$(q "SELECT agent_id FROM session_summary WHERE session_id='far-1' AND slots_json LIKE '%새것%'")"

echo "== 8. 코드 리뷰 반영 — 도우미 없는 회상 · lifecycle"
N="$T/nohelper"; mkdir -p "$N"; for f in "$S"/*.py; do ln -s "$f" "$N/"; done; rm "$N/hermes_summary_owner.py"
OLDDB="$T/old.db"; python3 -c "
import sqlite3; c=sqlite3.connect('$OLDDB')
c.execute('CREATE TABLE session_summary (session_id TEXT PRIMARY KEY, project_id TEXT, slots_json TEXT, last_msg_count INTEGER DEFAULT 0, turn_count INTEGER DEFAULT 0, updated_at DATETIME)')
c.execute(\"INSERT INTO session_summary VALUES ('o1','p','{}',0,0,'2026-09-01 00:00:00')\"); c.commit()"
R="$(cd "$N" && python3 -c "
import importlib.util, sqlite3
s=importlib.util.spec_from_file_location('r','$N/hermes-recall.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
c=sqlite3.connect('$OLDDB'); m._ensure_schema(c); r=m.latest_other_summary(c,'p','none'); print(r['session_id'] if r else 'none')" 2>&1 | tail -1)"
assert "도우미 없는 옛 DB 에서도 회상이 돈다" o1 "$R"

echo "== 자기 검사 — 주입 구획을 끄면 4 가 빨개진다"
M="$T/mut"; mkdir -p "$M"; for f in "$S"/*.py; do ln -s "$f" "$M/"; done
rm "$M/hermes_soul_render.py"; sed 's/render_agent_summaries(project, agent_id)/""/' "$S/hermes_soul_render.py" > "$M/hermes_soul_render.py"
O="$(PYTHONPATH="$M" python3 "$M/hermes_soul_render.py" "$P" "$GQ" 2>/dev/null)"
assert "변이 → 대화 구획 없음" 0 "$(has "$O" '나와 나눈 최근 대화')"

echo ""; echo "결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
