#!/usr/bin/env bash
# 저장 경계 마스킹 회귀 테스트 — 정답지(.env) 조회가 환경변수에 기대지 않는다.
#
# 배경: redact(text, project_dir) 는 project_dir 생략 시 CLAUDE_PROJECT_DIR → cwd 로
#   폴백한다. 그 경로에 .env 가 없으면 값 대조가 통째로 빠지고 형태 규칙만 남는다.
#   2026-08-10 설계가 입증했듯 형태 규칙은 사용자가 실제로 치는 형태를 놓친다.
#   훅 밖(cron·서버·워크트리)에서 도는 경계가 특히 위험하다.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PROJ="$TMP/proj"; ELSEWHERE="$TMP/elsewhere"
mkdir -p "$PROJ" "$ELSEWHERE"
python3 "$SCRIPTS/hermes-init.py" --both "$PROJ" >/dev/null 2>&1
DB="$PROJ/.hermes/state.db"

# 정답지 — 형태 규칙이 못 잡는 형태의 값(딱지 없이 본문에 섞임)
printf 'E2E_ADMIN_PASSWORD=Qx7vRn2Lp9Ttz\n' > "$PROJ/.env"

# T1 헬퍼 — db_path 에서 프로젝트 루트를 되짚는 공용 함수가 있다
helper() {
PYTHONPATH="$SCRIPTS${PYTHONPATH:+:$PYTHONPATH}" python3 - "$DB" "$PROJ" <<'PY'
import sys
from hermes_redact import project_dir_for_db
assert project_dir_for_db(sys.argv[1]) == sys.argv[2], project_dir_for_db(sys.argv[1])
print("OK")
PY
}
if helper 2>/dev/null | grep -q OK; then ok "T1 project_dir_for_db 헬퍼가 프로젝트 루트를 되짚는다"
else nope "T1 project_dir_for_db 헬퍼가 프로젝트 루트를 되짚는다"; fi

# T2 적재 경계 — CLAUDE_PROJECT_DIR 이 딴 곳이어도 정답지 값이 마스킹된다
store() {
cd "$ELSEWHERE" || return 1
CLAUDE_PROJECT_DIR="$ELSEWHERE" PYTHONPATH="$SCRIPTS${PYTHONPATH:+:$PYTHONPATH}" python3 - "$DB" <<'PY'
import sqlite3, sys
from hermes_save_session_storage import save_session
msgs = [{"role": "user", "content": "운영 계정 정보 공유합니다 Qx7vRn2Lp9Ttz 로 로그인하세요"}]
save_session(sys.argv[1], msgs, "proj", "sessA")
con = sqlite3.connect(sys.argv[1])
row = con.execute("SELECT content FROM session_history WHERE session_id='sessA'").fetchone()
print("LEAK" if row and "Qx7vRn2Lp9Ttz" in row[0] else "CLEAN")
PY
}
if [[ "$(store 2>/dev/null | tail -1)" == "CLEAN" ]]; then
  ok "T2 적재 경계가 환경변수와 무관하게 정답지로 마스킹한다"
else nope "T2 적재 경계가 환경변수와 무관하게 정답지로 마스킹한다"; fi

# T3 요약 경계 — 요약도 DB 에 저장되고 서버로 나간다
summ() {
cd "$ELSEWHERE" || return 1
CLAUDE_PROJECT_DIR="$ELSEWHERE" PYTHONPATH="$SCRIPTS${PYTHONPATH:+:$PYTHONPATH}" python3 - "$DB" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("s", __import__("os").environ["SUMM"])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
from hermes_redact import project_dir_for_db
out = m.messages_to_text([{"role": "user", "content": "비번 Qx7vRn2Lp9Ttz 입니다"}],
                         project_dir_for_db(sys.argv[1]))
print("LEAK" if "Qx7vRn2Lp9Ttz" in out else "CLEAN")
PY
}
if [[ "$(SUMM="$SCRIPTS/hermes-summarize.py" summ 2>/dev/null | tail -1)" == "CLEAN" ]]; then
  ok "T3 요약 경계가 정답지로 마스킹한다"
else nope "T3 요약 경계가 정답지로 마스킹한다"; fi

# T4 B신호 경계 — 같은 session_history 테이블에 쓰므로 같은 관문을 통과해야 한다
sig() {
cd "$ELSEWHERE" || return 1
CLAUDE_PROJECT_DIR="$ELSEWHERE" PYTHONPATH="$SCRIPTS${PYTHONPATH:+:$PYTHONPATH}" python3 - "$DB" <<'PYX'
import sqlite3, sys
from hermes_save_session_signals import record_signal_context
record_signal_context(sys.argv[1], [("adminpw", "운영 비번 Qx7vRn2Lp9Ttz 확인")], "proj", "sessB")
con = sqlite3.connect(sys.argv[1])
row = con.execute("SELECT content FROM session_history WHERE session_id='sessB'").fetchone()
print("LEAK" if row and "Qx7vRn2Lp9Ttz" in row[0] else "CLEAN")
PYX
}
if [[ "$(sig 2>/dev/null | tail -1)" == "CLEAN" ]]; then
  ok "T4 B신호 경계가 정답지로 마스킹한다"
else nope "T4 B신호 경계가 정답지로 마스킹한다"; fi

echo
echo "  PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
