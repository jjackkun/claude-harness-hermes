#!/usr/bin/env bash
# 회상 표시가 진짜 세션 ID 로만 쌓이게 (계획 docs/exec-plans/completed/2026-09-29-recall-marker-integrity.md 목표 1~3).
#
#   1 여러 줄 프롬프트에서도 recall_marker 에 진짜 세션 ID 한 행만 생긴다
#   2 같은 세션에서 여러 줄 프롬프트를 또 보내도 회상은 한 번만 나간다
#   3 가짜 세션 ID 행 정리: 미리보기는 DB 무변경 · apply 는 UUID 가 아닌 행만 지움 · 백업 생성
#
# 모델 호출 0. 실행: bash tests/hermes-recall-marker-integrity-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
HOOK="$REPO_ROOT/assets/hooks/claude-userpromptsubmit-mistake-detect.sh"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset HERMES_DISABLED CLAUDE_PROJECT_DIR
# 부모 세션의 CLAUDE_PROJECT_DIR 가 있으면 훅이 공장 DB 에 쓴다 — 훅마다 임시 프로젝트를 가리키고, 끝에 공장 DB 무변경을 확인한다.
FACTORY_DB="$REPO_ROOT/.hermes/state.db"
fcount() { [[ -f "$FACTORY_DB" ]] && python3 -c "import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute('select count(*) from recall_marker').fetchone()[0])" "$FACTORY_DB" 2>/dev/null || echo -; }
BEFORE="$(fcount)"

P="$T/proj"; mkdir -p "$P/.hermes"
git -C "$P" init -q
python3 "$S/hermes-init.py" --project "$P" >/dev/null 2>&1
DB="$P/.hermes/state.db"
q() { python3 -c "import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone(); print('' if r is None or r[0] is None else r[0])" "$DB" "$1"; }
python3 - "$DB" <<'PY'
import json, sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("INSERT INTO session_summary (session_id, project_id, slots_json, updated_at) VALUES (?,?,?,datetime('now'))",
          ("prev-session", "proj", json.dumps({"decisions": ["결정A"], "open": ["과제B"]}, ensure_ascii=False)))
c.commit()
PY
SID="11111111-2222-3333-4444-555555555555"
payload() { python3 -c "import json,sys; print(json.dumps({'prompt': sys.argv[1], 'session_id': sys.argv[2]}))" "$1" "$2"; }
run_hook() { (cd "$P" && payload "$1" "$2" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>/dev/null); }

echo "== 1. 여러 줄 프롬프트에서도 진짜 세션 ID 가 표시된다"
OUT="$(run_hook $'첫 줄입니다\n둘째 줄 질문입니다' "$SID")"
assert "회상이 주입된다" 1 "$(has "$OUT" "[헤르메스 회상]")"
assert "표시는 한 행" 1 "$(q "SELECT COUNT(*) FROM recall_marker")"
assert "그 행이 진짜 세션 ID" "$SID" "$(q "SELECT session_id FROM recall_marker LIMIT 1")"

echo "== 2. 같은 세션에서 또 보내도 회상은 한 번만"
OUT="$(run_hook $'다시 첫 줄\n다시 둘째 줄\n셋째 줄' "$SID")"
assert "두 번째는 회상 없음" 0 "$(has "$OUT" "[헤르메스 회상]")"
assert "표시는 여전히 한 행" 1 "$(q "SELECT COUNT(*) FROM recall_marker")"

echo "== 3. 가짜 세션 ID 행 정리"
python3 - "$DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
for fake in ('  "defaultMode": "bypassPermissions"', "/home/x/proj/.hermes/history", "둘째 줄 질문입니다"):
    c.execute("INSERT INTO recall_marker (session_id, injected_at) VALUES (?, datetime('now'))", (fake,))
c.commit()
PY
python3 "$S/hermes-recall-repair.py" --db "$DB" >/dev/null 2>&1
assert "미리보기는 DB 를 바꾸지 않는다(표시 4행)" 4 "$(q "SELECT COUNT(*) FROM recall_marker")"
python3 "$S/hermes-recall-repair.py" --db "$DB" --apply >/dev/null 2>&1
assert "가짜 표시 3행이 지워지고 진짜 1행이 남는다" "$SID" "$(q "SELECT group_concat(session_id) FROM recall_marker")"
assert "백업 파일이 생겼다" 1 "$(ls "$DB".bak-* 2>/dev/null | wc -l | tr -d ' ')"
python3 "$S/hermes-recall-repair.py" --db "$DB" --apply >/dev/null 2>&1
assert "다시 돌려도 진짜 행은 그대로" 1 "$(q "SELECT COUNT(*) FROM recall_marker")"

assert "시험이 공장의 실제 회상 표시를 건드리지 않았다" "$BEFORE" "$(fcount)"

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
