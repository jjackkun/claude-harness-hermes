#!/usr/bin/env bash
# 올리기 전 판정 강화 — A 단계 (계획 docs/exec-plans/active/2026-09-29-privacy-gate-hardening.md 목표 5~7).
#
#   1 list: 항목 상한 4 · 우선순위(문장 대기 → 성향 대기 → 표본) · 표본 1칸 예약 · 세션당 1회 · 0건이면 침묵
#   2 answer: 문장 keep|drop · 성향 approve|reject · 표본 ok|leak(leak 이면 drop 으로 바꾸고 파일을 알림) · later 는 기록 안 함
#   3 report: 표본 수 · 놓침 · 95% 상한(놓침 0건일 때 3/n) · 대기 문장의 사람 판정 · 같은 문장은 한 번만 센다
#   4 훅: git commit 감지 때 안내가 additionalContext 맨 위에 실린다(세션당 1회, 두 갈래 모두), 두 벌 동일
#
# 모델 호출 0. 실행: bash tests/hermes-ask-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
ASK="$S/hermes-ask.py"
GUARD="$REPO_ROOT/assets/hooks/claude-pretooluse-bash-guard.sh"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/.hermes"
unset HERMES_AGENT_ID HERMES_SUMMON_NONCE CLAUDE_PROJECT_DIR HERMES_DISABLED
FACTORY_DB="$REPO_ROOT/.hermes/state.db"
fsig() { [[ -f "$FACTORY_DB" ]] && python3 -c "
import sqlite3,sys
c=sqlite3.connect(sys.argv[1]); out=[]
for t in ('privacy_review','privacy_gold','ask_marker'):
    try: out.append(str(c.execute('select count(*) from '+t).fetchone()[0]))
    except Exception: out.append('-')
print(','.join(out))" "$FACTORY_DB" 2>/dev/null || echo -; }
BEFORE="$(fsig)"

GQ="01a0ae58-6aa6-7202-ae81-7d27af7b5617"
P="$T/proj"; mkdir -p "$P/.hermes/agents/$GQ" "$P/.claude"
git -C "$P" init -q; git -C "$P" config user.name alice; git -C "$P" config user.email a@t
ln -s "$S" "$P/scripts"
python3 "$S/hermes-init.py" --db "$P/.hermes/state.db" >/dev/null 2>&1
DB="$P/.hermes/state.db"; GDB="$HOME/.hermes/global.db"
MEM="$P/.hermes/agents/$GQ/memory.jsonl"
q() { python3 -c "import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone(); print('' if r is None or r[0] is None else r[0])" "$DB" "$1"; }
py() { S="$S" DB="$DB" GDB="$GDB" python3 -c "
import os, sys, sqlite3
sys.path.insert(0, os.environ['S'])
con = sqlite3.connect(os.environ['DB'])
$1"; }
hash_of() { S="$S" python3 -c "import os,sys; sys.path.insert(0, os.environ['S']); from hermes_privacy_pending import text_hash; print(text_hash(sys.argv[1]))" "$1"; }
ask() { (cd "$P" && python3 "$ASK" "$@" 2>&1); }
mem_line() { printf '{"memory_id":"%s","kind":"memory.added","agent_id":"%s","ts":"2026-09-29T00:00:00Z","about":"gate/x","body":"%s"}\n' "$1" "$GQ" "$2"; }
seed_pending() {   # seed_pending <개수> — 오래된 순으로 읽히도록 시각을 준다
  py "
from hermes_privacy_pending import mark
for i in range(int(sys.argv[1]) if len(sys.argv) > 1 else $1):
    mark(con, 'summary', 'r%d' % i, '대기 문장 %d' % i, 'pending')
    con.execute(\"UPDATE privacy_review SET ts=? WHERE text=?\", ('2026-09-2%d 00:00:00' % i, '대기 문장 %d' % i))
con.commit()"
}
stage_clean() {    # stage_clean <개수> — 통과 판정을 받은 기억 줄을 스테이징한다
  : > "$MEM"
  local i; for i in $(seq 1 "$1"); do mem_line "m$i" "통과 문장 $i" >> "$MEM"; done
  py "
from hermes_privacy_pending import mark
for i in range(1, $1 + 1):
    mark(con, 'memory', 'm%d' % i, '통과 문장 %d' % i, 'clean')
con.commit()"
  git -C "$P" add "$MEM"
}
seed_persona() {
  S="$S" GDB="$GDB" python3 -c "
import os, sys, sqlite3
from datetime import datetime, timezone
sys.path.insert(0, os.environ['S'])
from hermes_persona_store import ensure_schema, add_observation
c = sqlite3.connect(os.environ['GDB']); ensure_schema(c)
now = datetime.now(timezone.utc).isoformat()
for sid in ('a', 'b'):
    add_observation(c, {'session_id': sid, 'facet': 'workflow', 'key': 'test-x', 'statement': '시험 성향 문장', 'tier': 't1',
                        'quote': '인용', 'source_path': 'f', 'line': 1, 'observed_at': now})"
}
count_kind() { grep -c "^$2:" <<<"$1" || true; }

echo "== 1. list"
OUT="$(ask list --session s0)"
assert "대기·표본이 없으면 아무것도 출력하지 않는다" "" "$OUT"
assert "…그리고 물었다고 표시하지 않는다" 0 "$(q "SELECT COUNT(*) FROM ask_marker")"
seed_pending 5; stage_clean 5; seed_persona
OUT="$(ask list --session s1)"
assert "머리줄에 항목 4개" 1 "$(has "$OUT" "[ASK] 4")"
assert "문장 대기가 앞서고 표본 1칸이 예약된다(문장 3 · 표본 1)" "3 0 1" "$(count_kind "$OUT" p) $(count_kind "$OUT" s) $(count_kind "$OUT" g)"
assert "오래된 대기 문장이 먼저다" 1 "$(has "$OUT" "대기 문장 0")"
assert "사람에게 물을 방법 안내가 있다" 1 "$(has "$OUT" "hermes-ask.py answer")"
assert "같은 세션에서 또 부르면 침묵" "" "$(ask list --session s1)"
assert "새 세션에서는 다시 나온다(무시된 항목은 다음 세션에)" 1 "$(has "$(ask list --session s2)" "[ASK] 4")"
py "
con.execute(\"DELETE FROM privacy_review WHERE status='pending' AND text NOT LIKE '%0'\"); con.commit()"
OUT="$(ask list --session s3)"
assert "문장 대기 1 · 성향 1 · 표본이 남는 칸(2)" "1 1 2" "$(count_kind "$OUT" p) $(count_kind "$OUT" s) $(count_kind "$OUT" g)"
JSON="$(ask list --session s4 --json)"
assert "--json 은 항목 목록을 낸다" 4 "$(python3 -c "import json,sys; print(len(json.load(sys.stdin)))" <<<"$JSON")"
py "
import sqlite3
from hermes_privacy_gold import ensure_table
ensure_table(con)
for i in range(100):
    con.execute(\"INSERT OR IGNORE INTO privacy_gold (hash, verdict, source) VALUES (?, 'ok', 'staged')\", ('x%d' % i,))
con.commit()"
OUT="$(ask list --session s5)"
assert "표본 목표(100)에 이르면 표본을 더 묻지 않는다" "1 1 0" "$(count_kind "$OUT" p) $(count_kind "$OUT" s) $(count_kind "$OUT" g)"
py "con.execute(\"DELETE FROM privacy_gold\"); con.commit()"

echo "== 2. answer"
PID="$(ask list --session s6 --json | python3 -c "import json,sys; print([i['id'] for i in json.load(sys.stdin) if i['id'].startswith('p:')][0])")"
assert "문장 keep → 둠, 원문이 비워진다" "keep|" "$(ask answer "$PID" keep >/dev/null; q "SELECT status || '|' || text FROM privacy_review WHERE hash LIKE '${PID#p:}%'")"
assert "성향 approve → 승인 기록" "approved" "$(ask answer "s:workflow/test-x" approve >/dev/null; S="$S" GDB="$GDB" python3 -c "
import os, sys, sqlite3
sys.path.insert(0, os.environ['S'])
import hermes_persona_decisions as dec
print(dec.decisions(sqlite3.connect(os.environ['GDB'])).get('workflow/test-x'))")"
GID="$(ask list --session s7 --json | python3 -c "import json,sys; print([i['id'] for i in json.load(sys.stdin) if i['id'].startswith('g:')][0])")"
ask answer "$GID" ok >/dev/null
assert "표본 ok → 정답지에 ok 한 건" "ok 1" "$(q "SELECT verdict || ' ' || COUNT(*) FROM privacy_gold")"
GID2="$(ask list --session s8 --json | python3 -c "import json,sys; print([i['id'] for i in json.load(sys.stdin) if i['id'].startswith('g:')][0])")"
OUT="$(ask answer "$GID2" leak)"
assert "표본 leak → 정답지에 leak" 1 "$(q "SELECT COUNT(*) FROM privacy_gold WHERE verdict='leak'")"
assert "leak 문장은 지움(drop)으로 바뀐다" 1 "$(q "SELECT COUNT(*) FROM privacy_review WHERE status='drop' AND hash LIKE '${GID2#g:}%'")"
assert "어느 파일에 있는지 알려 준다" 1 "$(has "$OUT" "memory.jsonl")"
assert "게이트가 그 문장을 막는다(drop)" 1 "$(cd "$P" && python3 "$REPO_ROOT/assets/hooks/check-privacy.py" >/dev/null 2>&1; echo $?)"
BEFORE_N="$(q "SELECT COUNT(*) FROM privacy_gold")"
ask answer "$GID2" later >/dev/null
assert "later 는 아무것도 기록하지 않는다" "$BEFORE_N" "$(q "SELECT COUNT(*) FROM privacy_gold")"
assert "없는 항목 → 실패" 1 "$(ask answer "p:zzzzzzzz" keep >/dev/null; echo $?)"
assert "허용되지 않은 선택 → 실패" 1 "$(ask answer "$PID" approve >/dev/null; echo $?)"

echo "== 3. report"
py "
from hermes_privacy_gold import ensure_table
ensure_table(con)
con.execute('DELETE FROM privacy_gold')
for i in range(10):
    con.execute(\"INSERT OR IGNORE INTO privacy_gold (hash, verdict, source) VALUES (?, 'ok', 'staged')\", ('h%d' % i,))
    con.execute(\"INSERT OR IGNORE INTO privacy_gold (hash, verdict, source) VALUES (?, 'ok', 'staged')\", ('h%d' % i,))   # 같은 문장 두 번
con.commit()"
OUT="$(ask report)"
assert "같은 문장은 한 번만 세어 표본 10개" 1 "$(has "$OUT" "표본 10개")"
assert "놓침 0건이면 95% 상한 3/n = 30.0%" 1 "$(has "$OUT" "상한 30.0%")"
assert "스테이징된 문장에 한한 값임을 밝힌다" 1 "$(has "$OUT" "스테이징")"
py "con.execute(\"UPDATE privacy_gold SET verdict='leak' WHERE hash='h0'\"); con.commit()"
OUT="$(ask report)"
assert "놓침이 있으면 놓침 1건과 개선 계획 필요를 알린다" "1 1" "$(has "$OUT" "놓침 1건") $(has "$OUT" "개선")"
assert "대기 문장의 사람 판정(둠·지움)을 보인다" 1 "$(has "$OUT" "둠")"

echo "== 4. 훅: 커밋 안내에 실린다"
hook() {   # hook <세션> <명령> → additionalContext 문자열
  printf '{"tool_input":{"command":"%s"},"session_id":"%s"}' "$2" "$1" \
    | (cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$GUARD" 2>/dev/null) \
    | python3 -c "import json,sys; d=sys.stdin.read().strip(); print(json.loads(d)['hookSpecificOutput']['additionalContext'] if d else '')"
}
seed_pending 2
OUT="$(hook h1 'git commit -m x')"
assert "커밋 감지 때 안내가 실린다" 1 "$(has "$OUT" "[ASK]")"
assert "안내가 맨 앞에 있다" "[ASK]" "${OUT:0:5}"
assert "기존 리뷰 안내도 그대로 있다" 1 "$(has "$OUT" "[HARNESS]")"
assert "같은 세션에서 또 커밋해도 안내는 한 번뿐" 0 "$(has "$(hook h1 'git commit -m y')" "[ASK]")"
echo "리뷰 빚" > "$P/.claude/.review-dirty"
assert "리뷰 빚이 있는 갈래에도 실린다(새 세션)" 1 "$(has "$(hook h2 'git commit -m z')" "[ASK]")"
rm -f "$P/.claude/.review-dirty"
assert "커밋이 아닌 명령에는 안내가 없다" "" "$(hook h3 'ls -la')"
py "con.execute(\"UPDATE privacy_review SET status='clean' WHERE status='pending'\"); con.commit()"
git -C "$P" reset -q; : > "$MEM"
py "con.execute(\"DELETE FROM ask_marker\"); con.commit()"
assert "대기·표본이 없으면 안내가 실리지 않는다" 0 "$(has "$(hook h4 'git commit -m w')" "[ASK]")"
assert "훅 두 벌(assets · 공장 설치본)이 같다" 0 "$(diff -q "$GUARD" "$REPO_ROOT/scripts/hooks/claude-pretooluse-bash-guard.sh" >/dev/null 2>&1; echo $?)"

assert "시험이 공장의 실제 표를 건드리지 않았다" "$BEFORE" "$(fsig)"

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
