#!/usr/bin/env bash
# 할 일 없어진 DB 표 4개를 걷는다 (계획 docs/exec-plans/completed/2026-09-29-drop-dead-tables.md 목표 1~3).
#
#   1 새 DB 는 죽은 표(session_history·harness_rules·compaction_log·session_reuse)를 만들지 않는다
#   2 표가 없어도 회상(주입·질의)과 현황이 동작하고, 걷은 코드(hermes_reuse)를 아무도 부르지 않는다
#   3 hermes-db-prune.py: 미리보기 무변경 · 적용은 백업 뒤 표만 지우고 다른 표는 그대로 · 용량 감소 · 멱등 ·
#     전역 DB 는 harness_rules(옛 행)를 남긴다
#
# 모델 호출 0. 실행: bash tests/hermes-db-prune-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
PRUNE="$S/hermes-db-prune.py"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/.hermes"
unset CLAUDE_PROJECT_DIR HERMES_DISABLED HERMES_AGENT_ID
DEAD="session_history harness_rules compaction_log session_reuse"
FACTORY_DB="$REPO_ROOT/.hermes/state.db"
ftables() { [[ -f "$FACTORY_DB" ]] && python3 -c "
import sqlite3,sys
print(','.join(r[0] for r in sqlite3.connect(sys.argv[1]).execute(\"select name from sqlite_master where type='table' order by name\")))" "$FACTORY_DB" | md5sum || echo -; }
BEFORE="$(ftables)"
tables() { python3 -c "
import sqlite3,sys
print(' '.join(r[0] for r in sqlite3.connect(sys.argv[1]).execute(\"select name from sqlite_master where type='table' order by name\")))" "$1"; }
q() { python3 -c "import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone(); print('' if r is None or r[0] is None else r[0])" "$1" "$2"; }
present() { local t; t="$(tables "$1")"; for n in $DEAD; do [[ " $t " == *" $n "* ]] && printf '%s ' "$n"; done; echo; }

echo "== 1. 새 DB 는 죽은 표를 만들지 않는다"
P="$T/proj"; mkdir -p "$P/.hermes"; git -C "$P" init -q
python3 "$S/hermes-init.py" --db "$P/.hermes/state.db" >/dev/null 2>&1
assert "죽은 표 4개가 없다" "" "$(present "$P/.hermes/state.db" | sed 's/ *$//')"
TB="$(tables "$P/.hermes/state.db")"
assert "핵심 표(요약·스킬 색인·주입 원장·패턴)는 있다" "1 1 1 1" "$([[ " $TB " == *" session_summary "* ]] && echo 1) $([[ " $TB " == *" skill_index "* ]] && echo 1) $([[ " $TB " == *" skill_injection "* ]] && echo 1) $([[ " $TB " == *" pattern_count "* ]] && echo 1)"

echo "== 2. 표가 없어도 동작한다"
DB="$P/.hermes/state.db"
python3 - "$DB" <<'PY'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
c.execute("INSERT INTO session_summary (session_id, project_id, slots_json, updated_at) VALUES (?,?,?,datetime('now'))",
          ("prev-sess", "proj", json.dumps({"decisions": ["배포는 금요일에 한다"], "open": ["롤백 절차 정리"]}, ensure_ascii=False)))
c.commit()
PY
OUT="$(python3 "$S/hermes-recall.py" --inject --db "$DB" --project-id proj --session-id new-sess 2>&1)"
assert "회상 주입이 요약으로 동작한다" 1 "$(has "$OUT" "배포는 금요일에 한다")"
OUT="$(python3 "$S/hermes-recall.py" --query "배포" --db "$DB" 2>&1)"
assert "회상 질의가 요약으로 동작한다" 1 "$(has "$OUT" "prev-sess")"
assert "회상이 죽은 표를 되살리지 않는다" "" "$(present "$DB" | sed 's/ *$//')"
OUT="$(bash -c "source '$REPO_ROOT/lib/hermes_memory.sh'; hermes_status '$DB'" 2>&1)"; RC=$?
assert "셸 현황이 표 없이 성공한다" 0 "$RC"
assert "걷은 hermes_reuse 를 부르는 곳이 없다" 0 "$(grep -rl 'hermes_reuse' "$REPO_ROOT/scripts" "$REPO_ROOT/lib" "$REPO_ROOT/assets" --include=*.py --include=*.sh --include=*.md 2>/dev/null | grep -v '/__pycache__/' | wc -l | tr -d ' ')"
assert "현황 스킬이 프로젝트 DB 의 죽은 표를 읽지 않는다" 0 "$(grep -cE '^ +con\.execute\("SELECT COUNT\(\*\) FROM (harness_rules|session_history)"' "$REPO_ROOT/assets/skills/hermes-status/SKILL.md")"

echo "== 3. hermes-db-prune.py"
L="$T/legacy"; mkdir -p "$L/.hermes"
python3 "$S/hermes-init.py" --db "$L/.hermes/state.db" >/dev/null 2>&1
LDB="$L/.hermes/state.db"
python3 - "$LDB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE VIRTUAL TABLE session_history USING fts5(content, role, timestamp UNINDEXED, project_id UNINDEXED, session_id UNINDEXED)")
for i in range(400):
    c.execute("INSERT INTO session_history (content, role, session_id) VALUES (?, 'user', ?)", ("옛 원문 %d " % i + "낱말 " * 200, "s%d" % i))
c.execute("DELETE FROM session_history"); c.commit()          # 행은 0 이지만 색인 조각이 남는다
c.execute("CREATE TABLE harness_rules (rule_id INTEGER PRIMARY KEY, trigger_keywords TEXT NOT NULL, instruction TEXT NOT NULL)")
c.execute("CREATE TABLE compaction_log (id INTEGER PRIMARY KEY, note TEXT)")
c.execute("CREATE TABLE session_reuse (session_id TEXT PRIMARY KEY, last_reused_at TEXT, reuse_count INTEGER DEFAULT 0)")
c.execute("INSERT INTO session_reuse VALUES ('a', 'x', 1), ('b', 'x', 2), ('c', 'x', 3)")
c.execute("INSERT INTO session_summary (session_id, project_id, slots_json) VALUES ('keep-me', 'p', '{}')")
c.execute("CREATE TABLE IF NOT EXISTS privacy_review (hash TEXT PRIMARY KEY, kind TEXT NOT NULL, ref TEXT, text TEXT NOT NULL, status TEXT NOT NULL, ts TEXT)")
c.execute("INSERT INTO privacy_review VALUES ('h1', 'summary', '', '', 'clean', 'x')")
c.commit()
PY
SIZE0=$(stat -c %s "$LDB")
assert "전제: 옛 스키마 DB 에 죽은 표 4개가 있다" "harness_rules session_history compaction_log session_reuse" "$(present "$LDB" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ *$//' | awk '{print}' | python3 -c "import sys; print(' '.join(sorted(sys.stdin.read().split(), key=lambda x: ['harness_rules','session_history','compaction_log','session_reuse'].index(x))))")"
PREV="$(python3 "$PRUNE" --project "$L" 2>&1)"
assert "미리보기는 DB 를 바꾸지 않는다(표 4개 그대로)" 4 "$(present "$LDB" | wc -w | tr -d ' ')"
assert "미리보기가 session_reuse 의 행 수 3 을 보인다" 1 "$(has "$PREV" "session_reuse")"
python3 "$PRUNE" --project "$L" --apply >/dev/null 2>&1
assert "적용 뒤 죽은 표가 모두 사라진다" "" "$(present "$LDB" | sed 's/ *$//')"
assert "다른 표의 행은 그대로다(요약·판정)" "1 1" "$(q "$LDB" "SELECT COUNT(*) FROM session_summary WHERE session_id='keep-me'") $(q "$LDB" "SELECT COUNT(*) FROM privacy_review")"
assert "적용 전에 DB 를 백업했다" 1 "$(ls "$LDB".bak-* 2>/dev/null | wc -l | tr -d ' ')"
assert "DB 용량이 줄었다" 1 "$([[ $(stat -c %s "$LDB") -lt $SIZE0 ]] && echo 1 || echo 0)"
OUT="$(python3 "$PRUNE" --project "$L" --apply 2>&1)"; RC=$?
assert "다시 돌려도 안전하다(지울 표 없음, rc 0)" "0 1" "$RC $(has "$OUT" "지울 표가 없습니다")"

# 잠금: 다른 프로세스가 DB 를 쥐고 있으면 알리고 실패하며 아무것도 지우지 않는다
K="$T/locked"; mkdir -p "$K/.hermes"; python3 "$S/hermes-init.py" --db "$K/.hermes/state.db" >/dev/null 2>&1
python3 - "$K/.hermes/state.db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE compaction_log (id INTEGER PRIMARY KEY)"); c.commit()
PY
python3 - "$K/.hermes/state.db" "$T/lock.ready" <<'PY' &
import sqlite3, sys, time
c = sqlite3.connect(sys.argv[1], isolation_level=None, timeout=1); c.execute("BEGIN EXCLUSIVE")
open(sys.argv[2], "w").write("1"); time.sleep(6)
PY
LOCKER=$!
for _ in $(seq 1 50); do [[ -f "$T/lock.ready" ]] && break; sleep 0.1; done
OUT="$(HERMES_PRUNE_BUSY_MS=300 python3 "$PRUNE" --project "$K" --apply 2>&1)"; RC=$?
assert "잠겨 있으면 실패(rc 1)하고 이유를 알린다" "1 1" "$RC $(has "$OUT" "잠겨 있어")"
kill $LOCKER 2>/dev/null; wait $LOCKER 2>/dev/null
assert "잠겼던 DB 의 표는 그대로다" 1 "$([[ " $(tables "$K/.hermes/state.db") " == *" compaction_log "* ]] && echo 1 || echo 0)"

GDB="$HOME/.hermes/global.db"
python3 - "$GDB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE harness_rules (rule_id INTEGER PRIMARY KEY, trigger_keywords TEXT NOT NULL, instruction TEXT NOT NULL, source_session_id TEXT)")
for i in range(5):
    c.execute("INSERT INTO harness_rules (trigger_keywords, instruction, source_session_id) VALUES ('k', 'i', 's')")
c.execute("CREATE TABLE compaction_log (id INTEGER PRIMARY KEY)")
c.execute("CREATE TABLE session_reuse (session_id TEXT PRIMARY KEY, last_reused_at TEXT, reuse_count INTEGER DEFAULT 0)")
c.execute("CREATE TABLE persona_decision (label TEXT PRIMARY KEY, state TEXT)"); c.execute("INSERT INTO persona_decision VALUES ('a', 'approved')")
c.commit()
PY
python3 "$PRUNE" --global --apply >/dev/null 2>&1
assert "전역 DB: harness_rules(옛 행 5)는 남긴다" 5 "$(q "$GDB" "SELECT COUNT(*) FROM harness_rules")"
assert "전역 DB: 나머지 죽은 표는 지운다" "" "$(tables "$GDB" | tr ' ' '\n' | grep -E '^(compaction_log|session_reuse|session_history)$' | tr '\n' ' ' | sed 's/ *$//')"
assert "전역 DB: 성향 결정은 그대로다" 1 "$(q "$GDB" "SELECT COUNT(*) FROM persona_decision")"

assert "시험이 공장의 실제 DB 표를 건드리지 않았다" "$BEFORE" "$(ftables)"

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
