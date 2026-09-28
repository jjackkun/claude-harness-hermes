#!/usr/bin/env bash
# 에이전트 지식이 컴퓨터를 따라간다 (계획 docs/exec-plans/completed/2026-09-28-carry-agent-knowledge.md).
#
#   1 사람 칸: 요약에 person(git user.name) · 주입은 부른 사람과 나눈 대화만(칸 이전 행은 넣는다)
#   2 파일(목표 4·5·6): A 가 내보낸 기억·대화 요약·작업 이력을 B 가 들인다 — 판정 대기 문장은 파일에 없다 ·
#     기억이 들어오면 MEMORY.md · 인계를 맡기고 끝낸 기록이 같이 와서 B 의 인계 대기가 비어 있다 · 보조 호출 줄은 안 간다
#   3 R-privacy(목표 8): 스테이징된 기억 줄·스킬이 확인 전이면 막고(1) 통과면 흐른다(0) · 판정 표가 없으면 건너뜀(2)
#   4 git 설정(목표 7): 설치기 블록 뒤 세 경로가 추적되고 MEMORY.md 는 무시 · 두 가지에서 같은 jsonl 끝에 줄을 더해도 병합 충돌 없음
#
# 모델 호출은 가짜 claude 로 대신한다 — 사용량 0.
# 실행: bash tests/hermes-carry-knowledge-test.sh

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

GQ="01a0ae58-6aa6-7202-ae81-7d27af7b5617"
new_proj() {   # new_proj <dir> <git 사용자>
  local p="$1"
  mkdir -p "$p/.hermes/agents/$GQ"
  git -C "$p" init -q 2>/dev/null; git -C "$p" config user.name "$2"; git -C "$p" config user.email "$2@test"
  ln -s "$S" "$p/scripts"
  printf '{"agents": [{"agent_id": "%s", "name": "게이트QA", "slug": "gate-qa", "status": "probation", "org": {}}]}\n' "$GQ" > "$p/.hermes/agents.json"
  printf '# 정체성\n\n## 역할\n시험 역할.\n' > "$p/.hermes/agents/$GQ/SOUL.md"
  python3 "$S/hermes-init.py" --db "$p/.hermes/state.db" >/dev/null 2>&1
}
q() { python3 -c "import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone(); print('' if r is None or r[0] is None else r[0])" "$1" "$2"; }

# 가짜 claude — 고정 5칸 JSON
BIN="$T/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo '{"decisions":["가짜 결정"],"open":[],"prefs":[],"facts":["가짜 사실"],"next":[],"flagged":[]}'
EOF
chmod +x "$BIN/claude"; export PATH="$BIN:$PATH"

echo "== 1. 사람 칸"
A="$T/a"; new_proj "$A" "alice"; DBA="$A/.hermes/state.db"
TR="$T/tr.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"안녕"}}' '{"type":"assistant","message":{"role":"assistant","content":"네"}}' > "$TR"
python3 "$S/hermes-summarize.py" --db "$DBA" --transcript "$TR" --session-id s-alice --project-dir "$A" --agent-id "$GQ" >/dev/null 2>&1
assert "요약에 person = git user.name" "alice" "$(q "$DBA" "SELECT person FROM session_summary WHERE session_id='s-alice'")"
python3 -c "
import sqlite3,sys; c=sqlite3.connect(sys.argv[1])
c.execute(\"INSERT INTO session_summary (session_id,project_id,slots_json,updated_at,agent_id,person) VALUES ('s-bob','u','{\\\"decisions\\\":[\\\"밥의 결정\\\"]}','2026-09-28 10:00:00',?, 'bob')\", (sys.argv[2],))
c.execute(\"INSERT INTO session_summary (session_id,project_id,slots_json,updated_at,agent_id,person) VALUES ('s-old','u','{\\\"decisions\\\":[\\\"칸 이전 결정\\\"]}','2026-09-27 10:00:00',?, NULL)\", (sys.argv[2],))
c.commit()" "$DBA" "$GQ"
OUT="$(cd "$A" && python3 -c "import sys; sys.path.insert(0,'$S'); from hermes_agent_summaries import render_agent_summaries as r; print(r('$A','$GQ'))")"
assert "주입: 부른 사람(alice) 대화는 들어간다" 1 "$(has "$OUT" "가짜 결정")"
assert "주입: 다른 사람(bob) 대화는 안 들어간다" 0 "$(has "$OUT" "밥의 결정")"
assert "주입: 칸 이전(person 없음) 대화는 들어간다" 1 "$(has "$OUT" "칸 이전 결정")"
OUTB="$(python3 -c "import sys; sys.path.insert(0,'$S'); from hermes_agent_summaries import render_agent_summaries as r; print(r('$A','$GQ', who='bob'))")"
assert "주입: bob 이 부르면 bob 대화가 들어간다" 1 "$(has "$OUTB" "밥의 결정")"
assert "주입: bob 이 부르면 alice 대화는 안 들어간다" 0 "$(has "$OUTB" "가짜 결정")"
python3 "$S/hermes-summarize.py" --db "$DBA" --transcript "$TR" --session-id s-bob --project-dir "$A" --agent-id "$GQ" >/dev/null 2>&1
assert "이미 붙은 person 은 다른 사람이 갱신해도 안 바뀐다" "bob" "$(q "$DBA" "SELECT person FROM session_summary WHERE session_id='s-bob'")"

echo "== 2. 파일로 내보내고 다른 컴퓨터가 들인다"
python3 -c "
import sqlite3,sys; sys.path.insert(0,'$S')
from hermes_memory_events import record
from hermes_journal_schema import ensure_schema
c=sqlite3.connect('$DBA'); ensure_schema(c)
record(c, {'memory_id':'m-ok','kind':'memory.added','agent_id':'$GQ','universe_id':'u','ts':'2026-09-28T01:00:00Z','about':'배포','body':'배포 전 스테이징 확인'})
record(c, {'memory_id':'m-held','kind':'memory.added','agent_id':'$GQ','universe_id':'u','ts':'2026-09-28T02:00:00Z','about':'사적','body':'요즘 잠을 못 잔다'})
cols='event_id,ts,kind,universe_id,task_id,actor,requested_by,evidence,decision,lesson'
rows=[('e1','2026-09-28T03:00:00Z','task.assigned','u','t1','agent:gate-qa','human:alice','{\"template\": \"gate-qa\"}','to=agent:$GQ kind=요청',None),
      ('e2','2026-09-28T04:00:00Z','task.finished','u','t1','agent:gate-qa','human:alice','{\"template\": \"gate-qa\"}',None,None),
      ('e3','2026-09-28T05:00:00Z','task.finished','u','sub-x','agent:sub-x','human:alice','{\"template\": \"Explore\"}',None,None),
      ('e4','2026-09-28T06:00:00Z','task.finished','u','sub-y','agent:sub-y','human:alice','{\"template\": \"gate-qa\"}',None,'테스트는 먼저 돌린다')]
for r in rows: c.execute(f'INSERT INTO journal_events ({cols}) VALUES (?,?,?,?,?,?,?,?,?,?)', r)
c.commit()
from hermes_privacy_pending import mark
mark(c,'memory','m-held','요즘 잠을 못 잔다','pending'); c.commit()"
python3 "$S/hermes-knowledge-files.py" export --project "$A" >/dev/null 2>&1
MF="$A/.hermes/agents/$GQ/memory.jsonl"
assert "기억 파일에 통과한 기억" 1 "$(grep -c "스테이징 확인" "$MF" 2>/dev/null)"
assert "기억 파일에 검토 대기 기억은 없다" 0 "$(grep -c "잠을 못" "$MF" 2>/dev/null)"
CF="$A/.hermes/agents/$GQ/conversations/alice/s-alice.json"
assert "대화 요약 파일(사람별 폴더)" 1 "$([[ -f "$CF" ]] && echo 1 || echo 0)"
assert "대화 요약 파일은 5칸 요약" 1 "$(has "$(cat "$CF" 2>/dev/null)" "가짜 결정")"
assert "bob 과의 대화는 bob 폴더" 1 "$([[ -f "$A/.hermes/agents/$GQ/conversations/bob/s-bob.json" ]] && echo 1 || echo 0)"
JF="$A/.hermes/journal.jsonl"
assert "이력: 인계 줄" 1 "$(grep -c '"e1"' "$JF" 2>/dev/null)"
assert "이력: 인계의 끝남 기록" 1 "$(grep -c '"e2"' "$JF" 2>/dev/null)"
assert "이력: 명부 밖 보조 호출은 안 간다" 0 "$(grep -c '"e3"' "$JF" 2>/dev/null)"
assert "이력: 교훈 줄은 간다" 1 "$(grep -c '"e4"' "$JF" 2>/dev/null)"
python3 "$S/hermes-knowledge-files.py" export --project "$A" >/dev/null 2>&1
assert "두 번 내보내도 줄이 늘지 않는다" 1 "$(grep -c "스테이징 확인" "$MF")"

B="$T/b"; new_proj "$B" "alice"; DBB="$B/.hermes/state.db"
cp "$MF" "$B/.hermes/agents/$GQ/"; cp -r "$A/.hermes/agents/$GQ/conversations" "$B/.hermes/agents/$GQ/"; cp "$JF" "$B/.hermes/"
python3 "$S/hermes-knowledge-files.py" import --project "$B" >/dev/null 2>&1
assert "B: 기억이 들어왔다" 1 "$(q "$DBB" "SELECT COUNT(*) FROM memory_events WHERE memory_id='m-ok'")"
assert "B: MEMORY.md 가 다시 만들어졌다" 1 "$(has "$(cat "$B/.hermes/agents/$GQ/MEMORY.md" 2>/dev/null)" "스테이징 확인")"
assert "B: 대화 요약이 사람과 함께 들어왔다" alice "$(q "$DBB" "SELECT person FROM session_summary WHERE session_id='s-alice'")"
OUTB2="$(python3 -c "import sys; sys.path.insert(0,'$S'); from hermes_agent_summaries import render_agent_summaries as r; print(r('$B','$GQ'))")"
assert "B: 게이트QA 를 부르면 A 에서 나눈 대화를 안다" 1 "$(has "$OUTB2" "가짜 결정")"
assert "B: 인계가 들어왔다" 1 "$(q "$DBB" "SELECT COUNT(*) FROM journal_events WHERE event_id='e1'")"
QB="$(python3 -c "import sys; sys.path.insert(0,'$S'); from hermes_handoff_queue import queue; print(len(queue('$DBB','agent:$GQ')))")"
assert "B: 끝난 인계는 대기에 없다" 0 "$QB"
python3 "$S/hermes-knowledge-files.py" import --project "$B" >/dev/null 2>&1
assert "B: 두 번 들여도 늘지 않는다" 1 "$(q "$DBB" "SELECT COUNT(*) FROM memory_events WHERE memory_id='m-ok'")"

echo "== 2b. 리뷰 반영 — 인계 지시문 판정 · 폴더와 다른 id 버림 · 동시 붙이기"
python3 -c "
import sqlite3,sys; sys.path.insert(0,'$S'); from hermes_privacy_pending import mark
c=sqlite3.connect('$DBA')
c.execute(\"INSERT INTO journal_events (event_id,ts,kind,universe_id,task_id,actor,requested_by,evidence,intent) VALUES ('e5','2026-09-28T07:00:00Z','task.assigned','u','t5','agent:gate-qa','human:alice','{}','병원 예약 좀 잡아 줘')\")
mark(c,'journal','e5','병원 예약 좀 잡아 줘','pending'); c.commit()"
python3 "$S/hermes-knowledge-files.py" export --project "$A" >/dev/null 2>&1
assert "대기 중인 인계 지시문(intent) 줄은 안 나간다" 0 "$(grep -c '"e5"' "$JF")"
printf '%s\n' '{"memory_id":"m-evil","kind":"memory.added","agent_id":"../../evil","universe_id":"u","ts":"2026-09-28T00:00:00Z","body":"x"}' >> "$B/.hermes/agents/$GQ/memory.jsonl"
python3 "$S/hermes-knowledge-files.py" import --project "$B" >/dev/null 2>&1
assert "폴더와 다른 agent_id 줄은 들이지 않는다" 0 "$(q "$DBB" "SELECT COUNT(*) FROM memory_events WHERE memory_id='m-evil'")"
LK="$T/lock.jsonl"
for i in 1 2 3 4; do PYTHONPATH="$S" python3 -c "
from hermes_jsonl_lock import locked_append
locked_append('$LK','id',[{'id':f'k{n}'} for n in range(50)])" & done; wait
assert "네 프로세스가 동시에 붙여도 줄이 겹치지 않는다" 50 "$(wc -l < "$LK" | tr -d ' ')"

echo "== 3. R-privacy 게이트"
GATE="$REPO_ROOT/assets/hooks/check-privacy.py"
rc_of() { (cd "$1" && python3 "$GATE" >/dev/null 2>&1; echo $?); }
git -C "$A" add -f ".hermes/agents/$GQ/memory.jsonl" >/dev/null 2>&1
assert "통과한 기억 줄만 스테이징 → 통과" 0 "$(rc_of "$A")"
python3 -c "
import sqlite3,sys; sys.path.insert(0,'$S'); from hermes_privacy_pending import decide, text_hash
c=sqlite3.connect('$DBA'); decide(c, text_hash('배포 전 스테이징 확인'), 'drop'); c.commit()"
assert "스테이징된 줄이 지움으로 바뀌면 → 막음" 1 "$(rc_of "$A")"
python3 -c "
import sqlite3,sys; sys.path.insert(0,'$S'); from hermes_privacy_pending import decide, text_hash
c=sqlite3.connect('$DBA'); decide(c, text_hash('배포 전 스테이징 확인'), 'keep'); c.commit()"
mkdir -p "$A/.hermes/skills"; printf '# 새 스킬\n판정 안 한 본문\n' > "$A/.hermes/skills/new-skill.md"
git -C "$A" add -f .hermes/skills/new-skill.md >/dev/null 2>&1
assert "판정 안 한 스킬 스테이징 → 막음" 1 "$(rc_of "$A")"
python3 "$S/hermes-knowledge-files.py" export --project "$A" >/dev/null 2>&1
assert "내보내기가 스킬을 판정한 뒤 → 통과" 0 "$(rc_of "$A")"
OUTG="$(cd "$A" && python3 "$GATE" 2>&1)"
assert "통과 때는 아무것도 안 찍는다" "" "$OUTG"
N="$T/nodb"; mkdir -p "$N/.hermes/skills"; git -C "$N" init -q; printf 'x\n' > "$N/.hermes/skills/s.md"; git -C "$N" add -f .hermes/skills/s.md
assert "판정 표 없는 저장소 → 건너뜀(2)" 2 "$(rc_of "$N")"
M="$T/none"; mkdir -p "$M"; git -C "$M" init -q; printf 'x\n' > "$M/a.txt"; git -C "$M" add a.txt
assert "지식 파일이 스테이징 안 됐으면 → 통과" 0 "$(rc_of "$M")"
echo "== 4. git 설정 — .gitignore 예외 · merge=union"
log_info() { :; }; log_warn() { :; }
source "$REPO_ROOT/lib/harness_installers.sh" 2>/dev/null
source "$REPO_ROOT/lib/gitattributes_block.sh"
GITIGNORE_ENTRIES=(); GITATTRIBUTES_ENTRIES=()
eval "$(grep -E '^(GITIGNORE|GITATTRIBUTES)_ENTRIES\+=' "$REPO_ROOT/presets/workflow/hermes.conf")"
G="$T/gi"; mkdir -p "$G/.hermes/agents/$GQ/conversations/alice"; git -C "$G" init -q; git -C "$G" config user.name t; git -C "$G" config user.email t@t
install_harness_gitignore "$G" "claude"; install_harness_gitattributes "$G"
_tracked() { local m; m="$(cd "$G" && git check-ignore -v "$1" 2>/dev/null | awk -F'\t' '{print $1}' | sed -E 's/^[^:]*:[0-9]+://')"; [[ -z "$m" || "${m:0:1}" == "!" ]] && echo 1 || echo 0; }
assert "memory.jsonl 추적" 1 "$(_tracked ".hermes/agents/$GQ/memory.jsonl")"
assert "conversations/<사람>/<세션>.json 추적" 1 "$(_tracked ".hermes/agents/$GQ/conversations/alice/s.json")"
assert "journal.jsonl 추적" 1 "$(_tracked .hermes/journal.jsonl)"
assert "MEMORY.md 는 계속 무시(파생물)" 0 "$(_tracked ".hermes/agents/$GQ/MEMORY.md")"
assert "state.db 는 계속 무시" 0 "$(_tracked .hermes/state.db)"
install_harness_gitattributes "$G"
assert ".gitattributes 블록은 다시 깔아도 하나" 1 "$(grep -c '>>> harness-agent-preset' "$G/.gitattributes")"
J2="$G/.hermes/journal.jsonl"
printf '{"event_id":"base"}\n' > "$J2"; git -C "$G" add -A >/dev/null; git -C "$G" commit -qm base
git -C "$G" checkout -qb other; printf '{"event_id":"from-b"}\n' >> "$J2"; git -C "$G" commit -qam b
git -C "$G" checkout -q - ; printf '{"event_id":"from-a"}\n' >> "$J2"; git -C "$G" commit -qam a
git -C "$G" merge -q --no-edit other >/dev/null 2>&1; RC=$?
assert "두 가지가 같은 jsonl 끝에 줄을 더해도 병합 성공" 0 "$RC"
assert "병합 뒤 양쪽 줄이 다 있다" 3 "$(wc -l < "$J2" | tr -d ' ')"
echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
