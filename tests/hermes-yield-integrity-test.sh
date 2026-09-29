#!/usr/bin/env bash
# 스킬 주입 기록을 믿을 수 있게 (계획 docs/exec-plans/completed/2026-09-29-skill-yield-integrity.md 목표 1~5).
#
#   1 내부 호출 차단: HERMES_DISABLED=1 이면 주입 훅이 출력도 원장 기록도 하지 않는다 · 없으면 주입한다
#   4 카운터 단일화: used_count = 원장 행 수 (색인 밖 주입 포함)
#   5 옛 잡음 정리: 미리보기는 DB 무변경 · 진입 sdk-cli 세션만 · 기록 없는 세션·판정 끝남 행은 안 지움 · apply 는 백업 뒤
#
# 모델 호출 0. 실행: bash tests/hermes-yield-integrity-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
HOOK="$REPO_ROOT/assets/hooks/claude-userpromptsubmit-reminders.sh"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset HERMES_DISABLED
# ⚠️ 부모 세션이 CLAUDE_PROJECT_DIR 를 가지고 있으면 훅이 그 저장소(공장)로 이동해 실제 DB 에 기록한다(2026-09-29 실측: 시험이
#    공장 원장에 3행을 남겼다). 훅마다 임시 프로젝트를 가리키도록 강제하고, 시험 끝에 공장 DB 가 그대로인지 확인한다.
unset CLAUDE_PROJECT_DIR
FACTORY_DB="$REPO_ROOT/.hermes/state.db"
fcount() { [[ -f "$FACTORY_DB" ]] && python3 -c "import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute('select count(*) from skill_injection').fetchone()[0])" "$FACTORY_DB" 2>/dev/null || echo -; }
BEFORE="$(fcount)"

P="$T/proj"; mkdir -p "$P/.claude/skills/deploy-check" "$P/.hermes"
git -C "$P" init -q
python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1
DB="$P/.hermes/state.db"
cat > "$P/.claude/skills/deploy-check/SKILL.md" <<'EOF'
---
name: deploy-check
description: 스테이징 배포 점검 절차
---
# 스테이징 배포 점검
스테이징 배포 전에 점검 절차를 순서대로 확인한다.
EOF
python3 "$S/hermes-index-skills.py" --db "$DB" --project "$P" >/dev/null 2>&1
q() { python3 -c "import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone(); print('' if r is None or r[0] is None else r[0])" "$DB" "$1"; }
run_hook() {   # run_hook <session> [환경변수...] → 훅 출력
  local sid="$1"; shift
  (cd "$P" && printf '{"prompt":"스테이징 배포 점검 절차를 알려 줘","session_id":"%s"}' "$sid" | env CLAUDE_PROJECT_DIR="$P" "$@" bash "$HOOK" 2>/dev/null)
}

echo "== 1. 내부 호출에는 스킬을 주입하지 않는다"
OUT="$(run_hook s-internal HERMES_DISABLED=1)"
assert "HERMES_DISABLED=1 → 주입 본문 없음" 0 "$(has "$OUT" "[헤르메스 규칙")"
assert "HERMES_DISABLED=1 → 원장 기록 없음" 0 "$(q "SELECT COUNT(*) FROM skill_injection WHERE session_id='s-internal'")"
assert "HERMES_DISABLED=1 → 하네스 리마인더는 그대로" 1 "$(has "$OUT" "Harness Reminders")"
OUT="$(run_hook s-human X=1)"
assert "플래그 없음 → 스킬이 주입된다" 1 "$(has "$OUT" "[헤르메스 규칙")"
assert "플래그 없음 → 원장에 기록된다" 1 "$([[ "$(q "SELECT COUNT(*) FROM skill_injection WHERE session_id='s-human'")" -ge 1 ]] && echo 1 || echo 0)"

echo "== 4. 주입 수 카운터 = 원장 행 수"
# 카운터가 이미 원장보다 뒤처진 상태(옛 기록 2행이 카운터에 안 잡힘)에서 시작해도 새 주입 뒤엔 같아져야 한다
python3 - "$DB" "$P/.claude/skills/deploy-check/SKILL.md" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
for sid in ("old-1", "old-2"):
    c.execute("INSERT INTO skill_injection (session_id, skill_path, source) VALUES (?,?,'prompt')", (sid, sys.argv[2]))
c.commit()
PY
for n in 1 2 3; do run_hook "s-count-$n" X=1 >/dev/null; done
LEDGER="$(q "SELECT COUNT(*) FROM skill_injection WHERE skill_path LIKE '%deploy-check%'")"
USED="$(q "SELECT used_count FROM skill_index WHERE skill_path LIKE '%deploy-check%'")"
assert "used_count 가 원장의 그 스킬 행 수와 같다" "$LEDGER" "$USED"
assert "원장 행이 실제로 쌓였다(6행 이상: s-human 1 + 옛 2 + 세션 3)" 1 "$([[ "$LEDGER" -ge 6 ]] && echo 1 || echo 0)"

echo "== 5. 옛 잡음 정리"
PR="$T/projects/-x"; mkdir -p "$PR"
mk_tr() { printf '{"type":"mode","sessionId":"%s"}\n{"type":"user","entrypoint":"%s","sessionId":"%s"}\n' "$1" "$2" "$1" > "$PR/$1.jsonl"; }
mk_tr sdk-a sdk-cli; mk_tr sdk-judged sdk-cli; mk_tr human-a cli    # missing-a 는 기록 파일이 없다
SK="$P/.claude/skills/deploy-check/SKILL.md"
python3 - "$DB" "$SK" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
for sid, corr in [("sdk-a", 0), ("sdk-judged", 1), ("human-a", 0), ("missing-a", 0)]:
    c.execute("INSERT INTO skill_injection (session_id, skill_path, source, correlated) VALUES (?,?,?,?)", (sid, sys.argv[2], "prompt", corr))
c.commit()
PY
python3 - "$DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("INSERT OR REPLACE INTO skill_index (skill_path, keywords, used_count) VALUES ('untouched-skill', 'x,y', 7)")   # 원장 행이 없는 옛 카운트
c.commit()
PY
BEFORE_ROWS="$(q "SELECT COUNT(*) FROM skill_injection")"
python3 "$S/hermes-yield-repair.py" --db "$DB" --projects-dir "$T/projects" >/dev/null
assert "미리보기는 DB 를 바꾸지 않는다" "$BEFORE_ROWS" "$(q "SELECT COUNT(*) FROM skill_injection")"
python3 "$S/hermes-yield-repair.py" --db "$DB" --projects-dir "$T/projects" --apply >/dev/null
assert "진입 sdk-cli 이고 판정 전인 행만 지웠다" 0 "$(q "SELECT COUNT(*) FROM skill_injection WHERE session_id='sdk-a'")"
assert "판정 끝난 sdk-cli 행은 남았다" 1 "$(q "SELECT COUNT(*) FROM skill_injection WHERE session_id='sdk-judged'")"
assert "사람 세션 행은 남았다" 1 "$(q "SELECT COUNT(*) FROM skill_injection WHERE session_id='human-a'")"
assert "기록 없는 세션 행은 남았다" 1 "$(q "SELECT COUNT(*) FROM skill_injection WHERE session_id='missing-a'")"
assert "백업 파일이 생겼다" 1 "$(ls "$DB".bak-* 2>/dev/null | wc -l | tr -d ' ')"
assert "영향 없는 스킬의 옛 카운트는 0 으로 안 지워진다" 7 "$(q "SELECT used_count FROM skill_index WHERE skill_path='untouched-skill'")"
assert "apply 뒤 used_count = 원장 행 수" "$(q "SELECT COUNT(*) FROM skill_injection WHERE skill_path LIKE '%deploy-check%'")" "$(q "SELECT used_count FROM skill_index WHERE skill_path LIKE '%deploy-check%'")"

echo "== 2. 재판정 도구: 진짜 짝이 가짜 짝보다 도움률이 높다"
R="$T/replay"; mkdir -p "$R/projects/-x"
python3 - "$R" <<'PY'
import json, sqlite3, sys, os
root = sys.argv[1]
topics = {"aaaa0001": ("deploy,staging", "deploy staging check"), "bbbb0002": ("billing,invoice", "billing invoice export"),
          "cccc0003": ("login,oauth", "login oauth token"), "dddd0004": ("search,index", "search index rebuild")}
db = sqlite3.connect(os.path.join(root, "state.db"))
db.execute("CREATE TABLE skill_index (skill_path TEXT PRIMARY KEY, keywords TEXT)")
db.execute("CREATE TABLE skill_injection (id INTEGER PRIMARY KEY, session_id TEXT, skill_path TEXT, correlated INTEGER DEFAULT 0, source TEXT)")
def transcript(sid, entry, cmd):
    lines = [{"type": "user", "entrypoint": entry, "sessionId": sid}]
    if cmd:
        lines.append({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": cmd}}]}})
    with open(os.path.join(root, "projects", "-x", sid + ".jsonl"), "w") as fh:
        fh.write("\n".join(json.dumps(x) for x in lines) + "\n")
for sid, (kw, cmd) in topics.items():
    db.execute("INSERT INTO skill_index VALUES (?,?)", ("skill-" + sid, kw))
    db.execute("INSERT INTO skill_injection (session_id, skill_path) VALUES (?,?)", (sid, "skill-" + sid))
    transcript(sid, "cli", cmd)
for sid, entry, cmd in (("eeee0005", "cli", ""), ("ffff0006", "sdk-cli", "deploy staging check")):   # 도구 안 쓴 세션 · 내부 호출 세션은 잰 표본에서 빠진다
    db.execute("INSERT INTO skill_injection (session_id, skill_path) VALUES (?,?)", (sid, "skill-aaaa0001"))
    transcript(sid, entry, cmd)
db.commit()
PY
REPLAY="$(python3 "$S/hermes_yield_replay.py" --db "$R/state.db" --projects-dir "$R/projects")"
assert "사람 세션 4개 · 짝 4개만 쟀다(도구 없음·내부 호출 제외)" 1 "$(has "$REPLAY" "사람 세션 4개 · (스킬,세션) 짝 4개")"
CELL="$(grep '^현재' <<<"$REPLAY" | awk -F'|' '{print $3}' | sed 's/^ *전체: *//; s/(n=.*//' | tr -d ' ')"
assert "진짜 도움률이 가짜보다 0.5 넘게 높다(인공 자료 진짜 1.00 · 가짜 0.00)" 1 "$(python3 -c "
r, f, _ = '$CELL'.split('/'); print(1 if float(r) - float(f) > 0.5 else 0)")"
assert "재판정 도구는 DB 를 바꾸지 않는다" 4 "$(python3 -c "import sqlite3; print(sqlite3.connect('$R/state.db').execute(\"SELECT COUNT(*) FROM skill_index\").fetchone()[0])")"

assert "시험이 공장의 실제 원장을 건드리지 않았다" "$BEFORE" "$(fcount)"

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
