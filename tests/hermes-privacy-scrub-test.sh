#!/usr/bin/env bash
# 올리기 전 판정 강화 — B 단계 (계획 docs/exec-plans/active/2026-09-29-privacy-gate-hardening.md 목표 1~4).
#
#   1 내보내기: 파일로 나가는 기억·이력·대화 요약 문장은 지금 규칙으로 가린 것이고, 판정 해시와 파일 문장이 같다
#   2 게이트: 다시 가리면 달라지는 스테이징 문장은 막는다 · 정상 문장은 통과 · 모듈이 없으면 종료 3
#   3 판정 표: 대기(pending) 문장만 원문을 갖는다 · 동작(allowed)은 그대로
#   4 옛 것 정리: hermes-privacy-scrub.py db / files (미리보기 무변경 · 적용 뒤 원문 0 · JSON 유효 · 멱등)
#
# 모델 호출 0(판정은 표에 직접 적는다). 실행: bash tests/hermes-privacy-scrub-test.sh

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
unset HERMES_AGENT_ID HERMES_SUMMON_NONCE CLAUDE_PROJECT_DIR HERMES_DISABLED
# 시험이 공장의 실제 판정 표를 건드리지 않았는지 끝에서 본다.
FACTORY_DB="$REPO_ROOT/.hermes/state.db"
fcount() { [[ -f "$FACTORY_DB" ]] && python3 -c "import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute('select count(*) from privacy_review').fetchone()[0])" "$FACTORY_DB" 2>/dev/null || echo -; }
BEFORE="$(fcount)"

GQ="01a0ae58-6aa6-7202-ae81-7d27af7b5617"
P="$T/proj"; mkdir -p "$P/.hermes/agents/$GQ"
git -C "$P" init -q; git -C "$P" config user.name "alice"; git -C "$P" config user.email "alice@test"
ln -s "$S" "$P/scripts"
printf '{"agents": [{"agent_id": "%s", "name": "게이트QA", "slug": "gate-qa", "status": "probation", "org": {}}]}\n' "$GQ" > "$P/.hermes/agents.json"
printf '# 정체성\n\n## 역할\n시험 역할.\n' > "$P/.hermes/agents/$GQ/SOUL.md"
DB="$P/.hermes/state.db"
python3 "$S/hermes-init.py" --db "$DB" >/dev/null 2>&1
q() { python3 -c "import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone(); print('' if r is None or r[0] is None else r[0])" "$DB" "$1"; }
py() { S="$S" DB="$DB" P="$P" GQ="$GQ" python3 -c "
import os, sys, json, sqlite3
sys.path.insert(0, os.environ['S'])
S, DB, P, GQ = (os.environ[k] for k in ('S', 'DB', 'P', 'GQ'))
con = sqlite3.connect(DB)
$1"; }

MAIL="담당자 메일은 kim.test@example.com 입니다"

echo "== 1. 내보내기: 지금 규칙으로 가린 문장으로 판정하고 쓴다"
py "
from hermes_memory_events import record
from hermes_journal_schema import ensure_schema
ensure_schema(con)
record(con, {'memory_id':'m1','kind':'memory.added','agent_id':GQ,'universe_id':'u','ts':'2026-09-29T01:00:00Z','about':'gate/x','body':'$MAIL'})
con.execute(\"INSERT INTO journal_events (event_id,ts,kind,universe_id,task_id,actor,requested_by,evidence,decision,lesson) VALUES ('e1','2026-09-29T02:00:00Z','task.finished','u','t1','agent:gate-qa','human:alice','{}',NULL,'$MAIL')\")
con.execute(\"INSERT INTO session_summary (session_id,project_id,slots_json,updated_at,agent_id,person) VALUES ('s1','u',?,'2026-09-29 03:00:00',?, 'alice')\", (json.dumps({'decisions':['$MAIL']}, ensure_ascii=False), GQ))
con.commit()
" >/dev/null 2>&1
JUDGED="$(py "
import hermes_memory_file as memory, hermes_journal_file as journal, hermes_conversation_file as conv
from hermes_privacy_pending import mark
items = conv.judge_items(con, project=P) + memory.judge_items(con, project=P) + journal.judge_items(con, P)
for k, r, t in items:
    mark(con, k, r, t, 'clean')
con.commit()
print(len(items), all('kim.test@example.com' not in t for _, _, t in items), all('[REDACTED:EMAIL]' in t for _, _, t in items))
")"
assert "판정 대상 3문장(기억·이력·대화 요약)이 모두 가려져 있다" "3 True True" "$JUDGED"
py "
import hermes_memory_file as memory, hermes_journal_file as journal, hermes_conversation_file as conv
print(memory.export(con, P), journal.export(con, P), conv.export(con, P))
" >/dev/null 2>&1
FILES="$(find "$P/.hermes" -type f \( -name memory.jsonl -o -name journal.jsonl -o -name 's1.json' \))"
assert "세 파일이 만들어졌다" 3 "$(wc -l <<<"$FILES" | tr -d ' ')"
assert "파일에 원문 메일이 없다" 0 "$(cat $FILES | grep -c 'kim.test@example.com')"
assert "파일에 가린 표지가 있다" 3 "$(for f in $FILES; do grep -c 'REDACTED:EMAIL' "$f" | head -1; done | awk '{s+=($1>0)} END{print s}')"
GATE="$(py "
from hermes_privacy_pending import allowed
import glob
bodies = [json.loads(l)['body'] for l in open(glob.glob(P + '/.hermes/agents/*/memory.jsonl')[0])]
lessons = [json.loads(l)['lesson'] for l in open(P + '/.hermes/journal.jsonl')]
slots = [x for f in glob.glob(P + '/.hermes/agents/*/conversations/*/s1.json') for x in json.load(open(f))['slots']['decisions']]
print(all(allowed(con, t) for t in bodies + lessons + slots), allowed(con, '$MAIL'))
")"
assert "파일 속 문장은 모두 판정을 통과하고, 가리기 전 원문은 통과하지 못한다" "True False" "$GATE"

echo "== 3. 판정 표: 대기 문장만 원문을 갖는다"
py "
from hermes_privacy_pending import mark, decide, pending_rows, allowed, status_of, text_hash
def txt(t): return con.execute('select text from privacy_review where hash=?', (text_hash(t),)).fetchone()[0]
mark(con, 'summary', 'r1', '대기 문장 하나', 'pending')
print('pending-keeps-text', txt('대기 문장 하나') == '대기 문장 하나', [r[3] for r in pending_rows(con)] == ['대기 문장 하나'])
mark(con, 'summary', 'r1', '대기 문장 하나', 'clean')
print('re-clean-clears', txt('대기 문장 하나') == '', status_of(con, '대기 문장 하나'))
mark(con, 'summary', 'r2', '통과 문장', 'clean')
print('clean-empty', txt('통과 문장') == '', allowed(con, '통과 문장'))
mark(con, 'summary', 'r3', '둘 문장', 'pending'); decide(con, text_hash('둘 문장'), 'keep')
print('keep-empty', txt('둘 문장') == '', allowed(con, '둘 문장'))
mark(con, 'summary', 'r4', '지울 문장', 'pending'); decide(con, text_hash('지울 문장'), 'drop')
print('drop-empty', txt('지울 문장') == '', allowed(con, '지울 문장'))
mark(con, 'summary', 'r4', '지울 문장', 'clean')
print('human-not-overwritten', status_of(con, '지울 문장'))
con.commit()
" > "$T/s3.txt" 2>&1
assert "대기 문장은 원문을 가진다(사람에게 보이려고)" "pending-keeps-text True True" "$(grep '^pending-keeps-text' "$T/s3.txt")"
assert "대기 → 통과 재판정이면 옛 원문을 비운다" "re-clean-clears True clean" "$(grep '^re-clean-clears' "$T/s3.txt")"
assert "통과 문장은 원문이 없고 통과한다" "clean-empty True True" "$(grep '^clean-empty' "$T/s3.txt")"
assert "둠(keep) 결정 뒤 원문 없음·통과" "keep-empty True True" "$(grep '^keep-empty' "$T/s3.txt")"
assert "지움(drop) 결정 뒤 원문 없음·통과 못 함" "drop-empty True False" "$(grep '^drop-empty' "$T/s3.txt")"
assert "사람의 결정은 기계 판정이 덮지 못한다" "human-not-overwritten drop" "$(grep '^human-not-overwritten' "$T/s3.txt")"

echo "== 2. 게이트: 지금 규칙으로 다시 가리면 달라지는 스테이징 문장은 막는다"
GATE="$REPO_ROOT/assets/hooks/check-privacy.py"
mk_gate() {   # mk_gate <디렉터리> <scripts 경로>
  local d="$1"; mkdir -p "$d/.hermes/agents/$GQ"
  git -C "$d" init -q; git -C "$d" config user.name alice; git -C "$d" config user.email a@t
  ln -s "$2" "$d/scripts"
  python3 "$S/hermes-init.py" --db "$d/.hermes/state.db" >/dev/null 2>&1
}
mark_clean() {   # mark_clean <디렉터리> <문장…>
  local d="$1"; shift
  S="$S" DB="$d/.hermes/state.db" python3 -c "
import os, sys, sqlite3
sys.path.insert(0, os.environ['S'])
from hermes_privacy_pending import mark
c = sqlite3.connect(os.environ['DB'])
for t in sys.argv[1:]:
    mark(c, 'memory', 'm', t, 'clean')
c.commit()" "$@"
}
mem_line() { printf '{"memory_id":"%s","kind":"memory.added","agent_id":"%s","ts":"2026-09-29T00:00:00Z","about":"gate/x","body":"%s"}\n' "$1" "$GQ" "$2"; }
G="$T/gate"; mk_gate "$G" "$S"
MEM="$G/.hermes/agents/$GQ/memory.jsonl"
mem_line m1 "메일은 kim.test@example.com 입니다" > "$MEM"
mark_clean "$G" "메일은 kim.test@example.com 입니다"      # 옛 규칙 때 통과 판정을 받은 원문
git -C "$G" add "$MEM"
OUT="$(cd "$G" && python3 "$GATE" 2>&1)"; RC=$?
assert "판정은 통과했어도 다시 가리면 달라지면 막는다" 1 "$RC"
assert "안내에 고치는 명령이 있다" 1 "$(has "$OUT" "hermes-privacy-scrub.py files --apply")"
{ mem_line m1 "메일은 [REDACTED:EMAIL] 입니다"; mem_line m2 "배포는 금요일에 한다"; } > "$MEM"
mark_clean "$G" "메일은 [REDACTED:EMAIL] 입니다" "배포는 금요일에 한다"
git -C "$G" add "$MEM"
OUT="$(cd "$G" && python3 "$GATE" 2>&1)"; RC=$?
assert "가린 문장과 정상 문장은 통과한다(오탐 없음)" 0 "$RC"
O="$T/oldscripts"; mkdir -p "$O"; cp "$S"/*.py "$O"/; rm -f "$O/hermes_redact.py"
V="$T/oldproj"; mk_gate "$V" "$O"
mem_line m1 "배포는 금요일에 한다" > "$V/.hermes/agents/$GQ/memory.jsonl"; git -C "$V" add -A >/dev/null 2>&1
OUT="$(cd "$V" && python3 "$GATE" 2>&1)"; RC=$?
assert "필요한 모듈이 없으면(구버전 스크립트) 종료 3" 3 "$RC"
assert "구버전이라 재설치가 필요하다고 알린다" 1 "$(has "$OUT" "재설치")"

echo "== 4. 옛 것 정리: hermes-privacy-scrub.py db / files"
python3 - "$DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("INSERT OR REPLACE INTO privacy_review (hash, kind, ref, text, status) VALUES ('h-old1','summary','r','옛 통과 문장','clean')")
c.execute("INSERT OR REPLACE INTO privacy_review (hash, kind, ref, text, status) VALUES ('h-old2','summary','r','옛 대기 문장','pending')")
c.commit()
PY
NONEMPTY="SELECT COUNT(*) FROM privacy_review WHERE status != 'pending' AND text != ''"
PREV="$(python3 "$S/hermes-privacy-scrub.py" db --project "$P" 2>&1)"
assert "db 미리보기는 DB 를 바꾸지 않는다(원문이 남은 비대기 행 있음)" 1 "$([[ "$(q "$NONEMPTY")" -ge 1 ]] && echo 1 || echo 0)"
assert "db 미리보기가 대상 수를 보인다" 1 "$(has "$PREV" "원문이 남은")"
python3 "$S/hermes-privacy-scrub.py" db --project "$P" --apply >/dev/null 2>&1
assert "db 적용 뒤 비대기 행의 원문이 0" 0 "$(q "$NONEMPTY")"
assert "db 적용 뒤에도 대기 문장 원문은 남는다" "옛 대기 문장" "$(q "SELECT text FROM privacy_review WHERE hash='h-old2'")"
assert "db 적용 전에 DB 를 백업했다" 1 "$(ls "$DB".bak-* 2>/dev/null | wc -l | tr -d ' ')"

F="$T/files"; mkdir -p "$F/.hermes/skills" "$F/.hermes/agents/$GQ/conversations/alice"
git -C "$F" init -q; git -C "$F" config user.name alice; git -C "$F" config user.email a@t
ln -s "$S" "$F/scripts"
printf '# 스킬 A\n메일은 kim.test@example.com 입니다\n' > "$F/.hermes/skills/a.md"
printf '# 스킬 C\n정상 문장만 있다\n' > "$F/.hermes/skills/c.md"
git -C "$F" add .hermes/skills/a.md .hermes/skills/c.md; git -C "$F" commit -q -m init
printf '# 스킬 B\n메일은 kim.test@example.com 입니다\n' > "$F/.hermes/skills/b.md"          # 추적 안 되는 파일
{ mem_line m1 "메일은 kim.test@example.com 입니다"; mem_line m2 "배포는 금요일에 한다"; } > "$F/.hermes/agents/$GQ/memory.jsonl"
printf '{\n "slots": {\n  "decisions": [\n   "메일은 kim.test@example.com 입니다"\n  ]\n },\n "session_id": "s9"\n}\n' > "$F/.hermes/agents/$GQ/conversations/alice/s9.json"
SUM() { (cd "$F" && find .hermes -type f -not -path '*/.scrub-backup/*' | sort | xargs md5sum | md5sum); }
B4="$(SUM)"
PREV="$(python3 "$S/hermes-privacy-scrub.py" files --project "$F" 2>&1)"
assert "files 미리보기는 파일을 바꾸지 않는다" "$B4" "$(SUM)"
assert "files 미리보기: 달라질 파일 4개(스킬 a·b, 기억, 대화 요약)" 1 "$(has "$PREV" "달라지는 파일 4개")"
python3 "$S/hermes-privacy-scrub.py" files --project "$F" --apply >/dev/null 2>&1
assert "files 적용 뒤 원문 메일이 어디에도 없다" 0 "$(cd "$F" && grep -rl 'kim.test@example.com' .hermes --exclude-dir=.scrub-backup | wc -l | tr -d ' ')"
assert "기억 파일은 모든 줄이 JSON 으로 읽힌다" 2 "$(python3 -c "import json,sys; print(sum(1 for l in open(sys.argv[1]) if json.loads(l)))" "$F/.hermes/agents/$GQ/memory.jsonl")"
assert "바뀌지 않아야 할 줄은 그대로다" "$(mem_line m2 "배포는 금요일에 한다")" "$(sed -n 2p "$F/.hermes/agents/$GQ/memory.jsonl")"
assert "대화 요약 파일도 JSON 으로 읽히고 가려졌다" "[REDACTED:EMAIL]" "$(python3 -c "import json,sys,re; print(re.search(r'\[REDACTED:EMAIL\]', json.load(open(sys.argv[1]))['slots']['decisions'][0]).group(0))" "$F/.hermes/agents/$GQ/conversations/alice/s9.json")"
assert "정상 파일(c.md)은 손대지 않았다" "# 스킬 C
정상 문장만 있다" "$(cat "$F/.hermes/skills/c.md")"
assert "추적 안 되는 파일은 원본을 백업했다" 1 "$(find "$F/.hermes/.scrub-backup" -name b.md 2>/dev/null | wc -l | tr -d ' ')"
assert "커밋돼 변경 없는 파일은 git 이 백업이라 따로 백업하지 않는다" 0 "$(find "$F/.hermes/.scrub-backup" -name a.md 2>/dev/null | wc -l | tr -d ' ')"
assert "다시 돌리면 바뀔 파일이 0(멱등)" 1 "$(has "$(python3 "$S/hermes-privacy-scrub.py" files --project "$F" 2>&1)" "달라지는 파일 0개")"

assert "시험이 공장의 실제 판정 표를 건드리지 않았다" "$BEFORE" "$(fcount)"

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
