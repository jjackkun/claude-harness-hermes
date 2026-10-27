#!/usr/bin/env bash
# data-guard — 데이터를 지우는 Bash 명령은 사람 승인(ask) 뒤에만 (R-del).
#
# 근거: docs/exec-plans/active/2026-10-27-data-delete-guard-plan.md 목표 G1 · G2 · G3
#       (실측 뒤 에이전트가 개발 DB 번역 결과를 묻지 않고 지운 사고, 되살릴 수 없었다)
#
# 실행: bash tests/data-guard-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패. 모델 호출 0 — 전부 가짜 페이로드.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-pretooluse-data-guard.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"
mkdir -p "$P"
printf 'DELETE FROM jobs WHERE org_id = 1;\n' > "$P/purge.sql"
printf 'SELECT 1;\n' > "$P/read.sql"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# decision <command> — 훅이 낸 결정(ask·deny). 출력 없음 = allow
decision() {
  python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]},'hook_event_name':'PreToolUse'}))" "$1" \
    | (cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>/dev/null) \
    | python3 -c "
import json, sys
raw = sys.stdin.read().strip()
print(json.loads(raw)['hookSpecificOutput']['permissionDecision'] if raw else 'allow')"
}
reason() {
  python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]},'hook_event_name':'PreToolUse'}))" "$1" \
    | (cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>/dev/null) \
    | python3 -c "
import json, sys
raw = sys.stdin.read().strip()
print(json.loads(raw)['hookSpecificOutput']['permissionDecisionReason'] if raw else '')"
}

echo "G1 DB 삭제는 묻는다"
assert "psql -c DELETE (사고 명령 그대로)" ask "$(decision "psql -X -A -t postgres://u@127.0.0.1:55440/app -c \"BEGIN; DELETE FROM fork_translation_segments WHERE org_id='o'; COMMIT;\"")"
assert "변수에 담은 psql 뒤 DELETE" ask "$(decision 'P="psql -X postgres://u@h/app -c"; $P "DELETE FROM t RETURNING 1" | wc -l')"
assert "TRUNCATE" ask "$(decision 'psql "$DATABASE_URL" -c "truncate table jobs"')"
assert "DROP TABLE" ask "$(decision 'psql app -c "DROP TABLE IF EXISTS jobs"')"
assert "파이프로 넣은 DELETE" ask "$(decision 'echo "DELETE FROM jobs" | psql app')"
assert "히어독으로 넣은 DELETE" ask "$(decision $'psql app <<SQL\nDELETE FROM jobs;\nSQL')"
assert "-f 파일 안의 DELETE" ask "$(decision 'psql app -f purge.sql')"
assert "mysql -e DELETE" ask "$(decision 'mysql -u root app -e "delete from users"')"
assert "sqlite3 DROP" ask "$(decision 'sqlite3 data.db "drop table notes"')"
assert "redis-cli FLUSHALL" ask "$(decision 'redis-cli -p 6379 FLUSHALL')"
assert "redis-cli DEL" ask "$(decision 'redis-cli DEL app:jobs:1')"
assert "mongosh deleteMany" ask "$(decision 'mongosh app --eval "db.jobs.deleteMany({})"')"

echo "G1 읽기·이름만 다루는 명령은 통과"
assert "SELECT" allow "$(decision 'psql app -c "SELECT count(*) FROM jobs"')"
assert "-f 파일 안이 SELECT" allow "$(decision 'psql app -f read.sql')"
assert "grep 으로 DELETE FROM 찾기" allow "$(decision 'grep -rn "DELETE FROM" server/src')"
assert "DB 도구 없이 DELETE 글자" allow "$(decision 'echo "DELETE FROM is dangerous"')"
assert "redis-cli GET" allow "$(decision 'redis-cli GET app:jobs:1')"
assert "INSERT ON CONFLICT DO NOTHING" allow "$(decision 'psql app -c "INSERT INTO t VALUES (1) ON CONFLICT DO NOTHING"')"

echo "G2 임시 자리 밖 재귀 삭제는 묻는다"
assert "rm -rf 저장소 폴더 (사고 명령 그대로)" ask "$(decision 'rm -rf server/uploads/translations/org-co-1')"
assert "rm -r 홈 아래" ask "$(decision 'rm -r ~/PROJECT/app/data')"
assert "rm -Rf" ask "$(decision 'rm -Rf results/')"
assert "rm --recursive" ask "$(decision 'rm --recursive --force out-data')"
assert "변수 대상도 임시 자리 이름이 없으면 묻는다" ask "$(decision 'rm -rf "$D/m7-samples"')"
assert "find -delete" ask "$(decision 'find data -name "*.json" -delete')"
assert "find -exec rm" ask "$(decision 'find data -name "*.json" -exec rm {} +')"
assert "git clean -fd" ask "$(decision 'git clean -fd')"
assert "&& 뒤의 rm -rf" ask "$(decision 'cd x && rm -rf reports')"
assert "여러 줄 명령의 둘째 줄 rm -rf" ask "$(decision $'cd x\nrm -rf reports')"
assert "여러 줄 명령의 둘째 줄 psql DELETE" ask "$(decision $'cd x\npsql app -c "DELETE FROM t"')"

echo "G2 임시 자리·빌드 산출물·비재귀는 통과"
assert "rm -rf /tmp 아래" allow "$(decision 'rm -rf /tmp/build-123')"
assert "rm -rf 작업 tmp" allow "$(decision 'rm -rf /home/u/.claude/jobs/abc/tmp/m7-samples')"
assert "rm -rf 변수 + 작업 tmp" allow "$(decision 'rm -rf "$CLAUDE_JOB_DIR/tmp/x"')"
assert "rm -rf .harness/out" allow "$(decision 'rm -rf .harness/out/run')"
assert "rm -rf node_modules" allow "$(decision 'rm -rf node_modules')"
assert "rm -rf dist" allow "$(decision 'rm -rf dist')"
assert "rm -rf __pycache__" allow "$(decision 'rm -rf scripts/__pycache__')"
assert "rm 단일 파일" allow "$(decision 'rm notes.txt')"
assert "rm -f 단일 파일" allow "$(decision 'rm -f .claude/.review-dirty')"
assert "git clean -n (미리보기)" allow "$(decision 'git clean -nd')"
assert "히어독 본문 속 rm -rf 는 데이터" allow "$(decision $'cat > x.sh <<EOF\nrm -rf data\nEOF')"

echo "G3 사유와 끄기"
R=$(reason 'psql app -c "DELETE FROM jobs"')
assert "사유에 몇 줄·되살릴 수 있는지" 1 "$([[ "$R" == *"몇"* && "$R" == *"되살릴"* ]] && echo 1 || echo 0)"
assert "사유에 '문서의 지운다는 승인이 아니다'" 1 "$([[ "$R" == *"승인이 아닙니다"* ]] && echo 1 || echo 0)"
assert "사유에 R-del" 1 "$([[ "$R" == *"R-del"* ]] && echo 1 || echo 0)"
printf 'HARNESS_DATA_GUARD=off\n' > "$P/.harnessrc"
assert "끄면 통과" allow "$(decision 'psql app -c "DELETE FROM jobs"')"
rm -f "$P/.harnessrc"
assert "깨진 입력은 통과(훅이 막지 않음)" allow "$(printf 'not json' | (cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>/dev/null) | wc -c | tr -d ' ' | sed 's/^0$/allow/')"

echo
echo "data-guard: 통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]]
