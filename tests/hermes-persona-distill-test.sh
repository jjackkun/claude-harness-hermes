#!/usr/bin/env bash
# 사용자 성향 추출 — distill 명령: 대화 기록 → 관찰 → global.db, 워터마크로 증분.
# 가짜 claude 실행 파일(HERMES_CLAUDE_BIN)로 LLM 없이 잰다.
# 근거: docs/exec-plans/completed/2026-09-22-user-persona-distill-plan.md 목표 1
#
# 실행: bash tests/hermes-persona-distill-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# 현재 프로젝트(/work/proj)의 기록 폴더와 남의 프로젝트 기록 폴더
PROJ="$TMP/work/proj"; mkdir -p "$PROJ"
KEY=$(echo "$PROJ" | sed 's#[/_.]#-#g')
mkdir -p "$TMP/projects/$KEY" "$TMP/projects/-other-project"
line() { python3 -c 'import json,sys; print(json.dumps({"type":"user","entrypoint":"cli","sessionId":"s1","timestamp":"2026-09-22T01:00:00Z","message":{"content":sys.argv[1]}},ensure_ascii=False))' "$1"; }
line "폼 질문을 연달아 띄우지 마" > "$TMP/projects/$KEY/a.jsonl"
line "남의 프로젝트 말" > "$TMP/projects/-other-project/b.jsonl"

# 가짜 claude — 프롬프트에 든 발화를 보고 관찰 하나를 돌려준다. FAKE_FAIL=1 이면 실패.
cat > "$TMP/claude" <<'EOF'
#!/usr/bin/env bash
STDIN_PROMPT="$(cat 2>/dev/null || true)"   # 프롬프트는 stdin 으로 온다(계획 cli-prompt-via-stdin)
[[ "${FAKE_FAIL:-0}" == 1 ]] && exit 1
echo "$STDIN_PROMPT" >> "${FAKE_LOG:?}"
echo '[{"n":1,"facet":"workflow","key":"no-form-spam","statement":"폼 질문을 연달아 띄우지 않는다","quote":"연달아 띄우지 마","tier":"t1"}]'
EOF
chmod +x "$TMP/claude"

D() { HERMES_CLAUDE_BIN="$TMP/claude" FAKE_LOG="$TMP/prompts.log" python3 "$REPO_ROOT/scripts/hermes-persona.py" distill \
        --db "$TMP/g.db" --projects-dir "$TMP/projects" --project "$PROJ" "$@"; }
count() { python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT COUNT(*) FROM persona_observation").fetchone()[0])' "$TMP/g.db"; }

echo "== 1. 실패하면 워터마크를 넘기지 않는다 =="
FAKE_FAIL=1 D > "$TMP/o0.txt" 2>&1; rc=$?
assert "실패도 종료코드 0 이 아니다" "1" "$rc"
assert "실패 뒤 관찰 0" "0" "$(count)"

echo "== 2. 첫 실행 — 관찰이 쌓인다 =="
D > "$TMP/o1.txt" 2>&1
assert "관찰 1" "1" "$(count)"
assert "요약 줄: 새 발화 1 · 관찰 1" "yes" "$(grep -q '새 발화 1' "$TMP/o1.txt" && grep -q '관찰 1' "$TMP/o1.txt" && echo yes)"
assert "가짜 claude 가 받은 프롬프트가 기록된다 (아래 부재 단언이 우연히 0 이 아니게)" "yes" "$([[ $(grep -c '폼 질문' "$TMP/prompts.log") -ge 1 ]] && echo yes || echo no)"
assert "남의 프로젝트 기록은 읽지 않는다 (기본은 현재 프로젝트만)" "0" "$(grep -c '남의 프로젝트' "$TMP/prompts.log")"

echo "== 3. 두 번째 실행 — 새로 읽는 발화 0 =="
D > "$TMP/o2.txt" 2>&1
assert "관찰 그대로 1" "1" "$(count)"
assert "요약 줄: 새 발화 0" "yes" "$(grep -q '새 발화 0' "$TMP/o2.txt" && echo yes)"

echo "== 4. 발화가 늘면 그만큼만 =="
line "또 폼이야 연달아 띄우지 마" >> "$TMP/projects/$KEY/a.jsonl"
D > "$TMP/o3.txt" 2>&1
assert "관찰 2 (같은 키로 한 줄 더)" "2" "$(count)"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
