#!/usr/bin/env bash
# 명부·기억 파일 손편집 가드 검증 (계획 2026-09-20-identity-files-edit-guard 목표 1~3).
#
#   - 1절 도구: Edit·Write·MultiEdit 가 프로젝트 안 agents.json · agents/<id>/MEMORY.md 면 exit 2 + [identity-guard BLOCK] + 정식 명령 안내
#              SOUL.md · organization.yaml · 프로젝트 밖(픽스처) · 다른 파일 · 다른 도구는 통과. 상대 경로·심링크 우회도 막는다
#   - 2절 Bash: > >> tee sed -i cp/mv 목적지 rm truncate 가 대상을 향하면 차단. cat/grep/jq·정식 CLI·/tmp·변수 경로는 통과,
#              $CLAUDE_PROJECT_DIR 경로는 차단
#   - 3절 배선: hermes.conf 소스 + Edit|Write|MultiEdit · Bash 매처, gate-events 에 R-identity block 기록
#   - 자기 검사: 대상 정규식을 무력화하면 1절이 빨개진다
#
# 실행: bash tests/hermes-identity-guard-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-pretooluse-identity-guard.sh"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
[[ -x "$HOOK" ]] || { echo "FAIL: 훅이 없거나 실행 불가: $HOOK"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
P="$T/proj"; ID="01a0b728-2040-7e30-ab2d-cee957be526e"
mkdir -p "$P/.hermes/agents/$ID" "$P/scripts/hooks" "$T/outside/.hermes/agents/$ID"
cp "$REPO_ROOT/assets/hooks/gate_emit.sh" "$REPO_ROOT/assets/hooks/gate_event.py" "$P/scripts/hooks/" 2>/dev/null
cp "$HOOK" "$P/scripts/hooks/"
echo '{"agents": []}' > "$P/.hermes/agents.json"; echo "# m" > "$P/.hermes/agents/$ID/MEMORY.md"; echo "# s" > "$P/.hermes/agents/$ID/SOUL.md"
ln -s "$P/.hermes/agents.json" "$P/roster-link.json"

# run <tool> <key> <value> → 종료코드 (stderr 는 $T/err)
run() {
  python3 -c "
import json,sys
print(json.dumps({'hook_event_name':'PreToolUse','tool_name':sys.argv[1],'tool_input':{sys.argv[2]:sys.argv[3]}}))" "$1" "$2" "$3" \
    | CLAUDE_PROJECT_DIR="$P" bash "$P/scripts/hooks/claude-pretooluse-identity-guard.sh" >/dev/null 2>"$T/err"; echo $?
}

echo "== 1절 도구(Edit·Write·MultiEdit)"
assert "Edit agents.json 차단" 2 "$(run Edit file_path "$P/.hermes/agents.json")"
assert "차단 문구 접두어" 1 "$(grep -c '^\[identity-guard BLOCK\]' "$T/err")"
assert "정식 명령 안내(hire·teach·refresh-memory)" 3 "$(grep -cE 'hermes-agent.py (hire|teach|refresh-memory)' "$T/err")"
assert "Write agents.json 차단" 2 "$(run Write file_path "$P/.hermes/agents.json")"
assert "MultiEdit MEMORY.md 차단" 2 "$(run MultiEdit file_path "$P/.hermes/agents/$ID/MEMORY.md")"
assert "Edit MEMORY.md 차단" 2 "$(run Edit file_path "$P/.hermes/agents/$ID/MEMORY.md")"
assert "상대 경로도 차단" 2 "$(run Edit file_path ".hermes/agents.json")"
assert "심링크로 돌아가도 차단(realpath)" 2 "$(run Edit file_path "$P/roster-link.json")"
assert "SOUL.md 는 통과(사람 승인 편집)" 0 "$(run Edit file_path "$P/.hermes/agents/$ID/SOUL.md")"
assert "organization.yaml 통과" 0 "$(run Write file_path "$P/.hermes/organization.yaml")"
assert "프로젝트 밖 agents.json 통과(픽스처)" 0 "$(run Write file_path "$T/outside/.hermes/agents.json")"
assert "프로젝트 밖 MEMORY.md 통과" 0 "$(run Edit file_path "$T/outside/.hermes/agents/$ID/MEMORY.md")"
assert "무관한 파일 통과" 0 "$(run Edit file_path "$P/src/app.py")"
assert "이름만 비슷한 파일 통과(my-agents.json)" 0 "$(run Write file_path "$P/docs/my-agents.json")"
assert "Read 는 건드리지 않는다" 0 "$(run Read file_path "$P/.hermes/agents.json")"
assert "빈 입력 통과" 0 "$(printf '' | CLAUDE_PROJECT_DIR="$P" bash "$P/scripts/hooks/claude-pretooluse-identity-guard.sh" >/dev/null 2>&1; echo $?)"
assert "깨진 JSON 통과(세션을 세우지 않는다)" 0 "$(printf '{oops' | CLAUDE_PROJECT_DIR="$P" bash "$P/scripts/hooks/claude-pretooluse-identity-guard.sh" >/dev/null 2>&1; echo $?)"
# 자기 검사: 대상 정규식을 무력화하면 차단이 사라진다
sed 's/agents\\\.json|agents\/\[\^\/\\s\\x27\\"\]+\/MEMORY\\\.md/NEVER_MATCH/' "$HOOK" > "$T/broken.sh"
assert "자기 검사: 대상 정규식을 끄면 통과해 버린다" 0 "$(python3 -c "
import json;print(json.dumps({'tool_name':'Edit','tool_input':{'file_path':'$P/.hermes/agents.json'}}))" | CLAUDE_PROJECT_DIR="$P" bash "$T/broken.sh" >/dev/null 2>&1; echo $?)"

echo "== 2절 Bash 쓰기 연산"
M=".hermes/agents/$ID/MEMORY.md"
assert "echo >> MEMORY.md 차단" 2 "$(run Bash command "echo '- 한 줄' >> $M")"
assert "cat > agents.json 차단" 2 "$(run Bash command "cat > .hermes/agents.json <<EOF
{}
EOF")"
assert "tee -a 차단" 2 "$(run Bash command "echo x | tee -a $M")"
assert "sed -i 차단" 2 "$(run Bash command "sed -i 's/a/b/' .hermes/agents.json")"
assert "cp 목적지 차단" 2 "$(run Bash command "cp /tmp/new.json .hermes/agents.json")"
assert "mv 목적지 차단" 2 "$(run Bash command "mv roster.tmp .hermes/agents.json && echo ok")"
assert "rm 차단" 2 "$(run Bash command "rm -f .hermes/agents.json")"
assert "\$CLAUDE_PROJECT_DIR 경로 차단" 2 "$(run Bash command 'echo x >> "$CLAUDE_PROJECT_DIR/.hermes/agents.json"')"
assert "따옴표로 감싼 경로 차단" 2 "$(run Bash command "echo x >> \"$M\"")"
assert "cat 읽기 통과" 0 "$(run Bash command "cat .hermes/agents.json | head -5")"
assert "jq 읽기 통과" 0 "$(run Bash command "jq '.agents[].name' .hermes/agents.json")"
assert "cp 원본으로 쓰는 것은 통과(백업)" 0 "$(run Bash command "cp .hermes/agents.json /tmp/roster.bak")"
assert "정식 CLI 통과(teach)" 0 "$(run Bash command "python3 scripts/hermes-agent.py teach 게이트QA '한 줄' --about test/run-all")"
assert "정식 CLI 통과(hire)" 0 "$(run Bash command "python3 scripts/hermes-agent.py hire QA담당 --org QA,담당,공통")"
assert "프로젝트 밖 절대 경로 쓰기 통과" 0 "$(run Bash command "echo '{}' > /tmp/fx-outside/.hermes/agents.json")"
assert "프로젝트가 /tmp 아래여도 절대 경로 heredoc 추가는 차단(2026-09-20 우회 실측)" 2 "$(run Bash command "cat >> $P/$M << 'EOF'
- 한 줄
EOF")"
assert "프로젝트 안 절대 경로 agents.json 덮어쓰기 차단" 2 "$(run Bash command "echo '{}' > $P/.hermes/agents.json")"
assert "변수 경로 픽스처 통과(\$T)" 0 "$(run Bash command 'cat > "$T/proj/.hermes/agents.json" <<EOF
{}
EOF')"
assert "무관한 리다이렉트 통과" 0 "$(run Bash command "echo x > notes.md")"

echo "== 3절 배선·관측"
CONF="$REPO_ROOT/presets/workflow/hermes.conf"
assert "hermes.conf 소스 등록" 1 "$(grep -c 'HARNESS_HOOK_SOURCES+=(claude-pretooluse-identity-guard.sh)' "$CONF")"
assert "Edit|Write|MultiEdit 매처" 1 "$(grep -c "PRE_TOOL_USE_HOOKS+=('Edit|Write|MultiEdit::.*identity-guard" "$CONF")"
assert "Bash 매처" 1 "$(grep -c "PRE_TOOL_USE_HOOKS+=('Bash::.*identity-guard" "$CONF")"
assert "차단이 gate-events 에 R-identity block 으로 남는다" 1 "$([[ "$(grep -c '"rule": "R-identity", "verdict": "block"' "$P/.harness/gate-events.jsonl" 2>/dev/null)" -ge 1 ]] && echo 1 || echo 0)"
assert "통과 판정은 기록하지 않는다(분모 오염 방지)" 0 "$(grep -c '"verdict": "pass"' "$P/.harness/gate-events.jsonl" 2>/dev/null; true)"
assert "스킬 문서에 가드 한 줄" 1 "$([[ "$(grep -c 'identity-guard' "$REPO_ROOT/assets/skills/hermes-agent/SKILL.md")" -ge 1 ]] && echo 1 || echo 0)"

echo; echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
