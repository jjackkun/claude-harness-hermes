#!/usr/bin/env bash
# SOUL 승인 경로 검증 (계획 2026-09-20-soul-self-approval-gap 목표 1~3).
#
#   - 1절 의사 기록: 프롬프트에 "승인"·approve → approve=true, 부정형("승인하지 마"·don't approve)·무관한 말 → false,
#                   매 프롬프트 덮어씀, stdout 무출력, hermes 프로젝트가 아니면 파일을 만들지 않는다
#   - 2절 가드: 초안 표시 줄을 없애는 Edit·MultiEdit·Write · 초안 SOUL 로의 Bash 쓰기 · approve-soul 호출은
#              의사 없음 → 차단 / 의사 있음 → 통과 / 소환된 에이전트(HERMES_AGENT_ID) → 의사가 있어도 차단 / 60분 지난 의사 → 차단.
#              표시 줄을 남기는 편집 · 이미 승인된 SOUL 편집 · 프로젝트 밖 SOUL 은 통과
#   - 3절 명령: approve-soul 이 표시 줄만 지우고 이력에 decision(soul-approved) 을 남긴다 · 이미 승인 → 그대로 · 없는 이름 → exit 2
#   - 자기 검사: 승인 의사 확인을 무력화하면 2절의 차단이 사라진다
#
# 실행: bash tests/hermes-soul-approval-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$REPO_ROOT/assets/hooks/claude-pretooluse-identity-guard.sh"
INTENT="$REPO_ROOT/assets/hooks/claude-userpromptsubmit-soul-approval-intent.sh"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset HERMES_AGENT_ID
MARK='> 초안 — 기계가 조직 값에서 채웠다. 사람이 읽고 고친 뒤 이 줄을 지우면 승인이다(D-01).'

echo "== 0. 픽스처 — 실제 명령으로 입사시켜 초안 SOUL 을 만든다"
P="$T/proj"; mkdir -p "$P/.hermes"
cp "$REPO_ROOT/assets/templates/organization/product.yaml" "$P/.hermes/organization.yaml"
A() { python3 "$REPO_ROOT/scripts/hermes-agent.py" --project "$P" "$@"; }
A hire 게이트QA --org QA,담당,공통 > "$T/hire.out" 2>&1
SOUL="$(ls "$P"/.hermes/agents/*/SOUL.md | head -1)"
assert "입사 직후 SOUL 은 초안(표시 줄 있음)" 1 "$(grep -c '^> 초안 — 기계가' "$SOUL")"

prompt() { python3 -c "import json,sys; print(json.dumps({'hook_event_name':'UserPromptSubmit','prompt':sys.argv[1]}))" "$1" | CLAUDE_PROJECT_DIR="$P" bash "$INTENT"; }
intent() { python3 -c "import json; print(str(json.load(open('$P/.hermes/.soul-approval-intent'))['approve']).lower())" 2>/dev/null || echo none; }

echo "== 1절 승인 의사 기록"
OUT="$(prompt 'QA 한 명 뽑자')"; assert "무관한 말 → false" false "$(intent)"
assert "stdout 무출력(세션 문맥 오염 없음)" "" "$OUT"
prompt '게이트QA SOUL 승인해' >/dev/null; assert "'승인해' → true" true "$(intent)"
prompt '좋아 approve it' >/dev/null; assert "approve → true" true "$(intent)"
prompt 'SOUL 은 아직 승인하지 마' >/dev/null; assert "'승인하지 마' → false" false "$(intent)"
prompt "don't approve yet" >/dev/null; assert "don't approve → false" false "$(intent)"
prompt '승인 없이 진행해' >/dev/null; assert "'승인 없이' → false" false "$(intent)"
prompt '다음 작업 하자' >/dev/null; assert "다음 프롬프트가 의사를 덮어쓴다 → false" false "$(intent)"
mkdir -p "$T/plain"; python3 -c "import json; print(json.dumps({'prompt':'승인'}))" | CLAUDE_PROJECT_DIR="$T/plain" bash "$INTENT"
assert "hermes 프로젝트가 아니면 파일을 만들지 않는다" 0 "$([[ -e "$T/plain/.hermes/.soul-approval-intent" ]] && echo 1 || echo 0)"

# guard <tool> <json tool_input> → 종료코드
guard() { python3 -c "import json,sys; print(json.dumps({'tool_name':sys.argv[1],'tool_input':json.loads(sys.argv[2])}))" "$1" "$2" | CLAUDE_PROJECT_DIR="$P" bash "${GUARD_BIN:-$GUARD}" >/dev/null 2>"$T/err"; echo $?; }
J() { python3 -c "import json,sys; print(json.dumps(dict(zip(sys.argv[1::2], sys.argv[2::2]))))" "$@"; }
EDIT_RM="$(J file_path "$SOUL" old_string "$MARK" new_string "")"
EDIT_KEEP="$(J file_path "$SOUL" old_string "## 역할" new_string "## 역할 (다듬음)")"
WRITE_RM="$(J file_path "$SOUL" content "# 게이트QA\n\n## 역할\nQA.\n")"
WRITE_KEEP="$(J file_path "$SOUL" content "# 게이트QA\n\n$MARK\n\n## 역할\nQA.\n")"
MULTI_RM="$(python3 -c "import json,sys; print(json.dumps({'file_path':sys.argv[1],'edits':[{'old_string':'## 역할','new_string':'## 역할'},{'old_string':sys.argv[2],'new_string':''}]}))" "$SOUL" "$MARK")"

echo "== 2절 가드 — 승인 의사 없음"
prompt '입사 절차 알아서 마무리해줘' >/dev/null
assert "Edit 로 표시 줄 삭제 → 차단" 2 "$(guard Edit "$EDIT_RM")"
assert "차단 문구(SOUL 승인은 사람의 몫)" 1 "$(grep -c '^\[identity-guard BLOCK\] SOUL 승인은 사람의 몫' "$T/err")"
assert "안내에 approve-soul 과 '승인' 이라는 말" 2 "$(grep -cE 'approve-soul|"승인"' "$T/err")"
assert "MultiEdit 로 삭제 → 차단" 2 "$(guard MultiEdit "$MULTI_RM")"
assert "Write 로 표시 줄 없는 본문 덮어쓰기 → 차단" 2 "$(guard Write "$WRITE_RM")"
assert "Bash sed -i 로 초안 SOUL 쓰기 → 차단" 2 "$(guard Bash "$(J command "sed -i '/초안/d' $SOUL")")"
assert "Bash approve-soul 호출 → 차단" 2 "$(guard Bash "$(J command "python3 scripts/hermes-agent.py approve-soul 게이트QA")")"
assert "경로·환경변수가 앞에 붙은 approve-soul 호출도 차단" 2 "$(guard Bash "$(J command "cd /x && FOO=1 python3 /abs/scripts/hermes-agent.py --project . approve-soul 게이트QA")")"
HD_CMD="$(python3 -c "import json; print(json.dumps({'command': 'git commit -q -F - <<\x27MSG\x27\nfeat: python3 scripts/hermes-agent.py approve-soul <name> 추가\nMSG\ngit push'}))")"
assert "커밋 메시지 heredoc 본문의 명령 이름은 명령이 아니다 → 통과" 0 "$(guard Bash "$HD_CMD")"
assert "따옴표 안의 명령 이름 → 통과" 0 "$(guard Bash "$(J command "git commit -m 'scripts/hermes-agent.py approve-soul 명령 추가'")")"
assert "grep 으로 명령 이름을 찾는 것 → 통과" 0 "$(guard Bash "$(J command "grep -n approve-soul scripts/hermes-agent.py")")"
assert "표시 줄을 남기는 Edit 는 통과" 0 "$(guard Edit "$EDIT_KEEP")"
assert "표시 줄을 남기는 Write 는 통과" 0 "$(guard Write "$WRITE_KEEP")"
assert "SOUL 읽기(cat) 통과" 0 "$(guard Bash "$(J command "cat $SOUL")")"
mkdir -p "$T/outside/.hermes/agents/x"; printf '%s\n' "$MARK" > "$T/outside/.hermes/agents/x/SOUL.md"
assert "프로젝트 밖 SOUL 은 통과" 0 "$(guard Edit "$(J file_path "$T/outside/.hermes/agents/x/SOUL.md" old_string "$MARK" new_string "")")"
assert "차단이 gate-events 에 남는다(R-identity)" 1 "$([[ -f "$P/.harness/gate-events.jsonl" ]] && grep -c 'R-identity' "$P/.harness/gate-events.jsonl" | awk '{print ($1>=1)?1:0}' || echo skip-no-emitter)" 2>/dev/null || true

echo "== 2절 가드 — 승인 의사 있음 / 소환 / 만료"
prompt '읽어봤어. 게이트QA SOUL 승인해' >/dev/null
assert "의사 있음: Edit 삭제 통과(스킬 0-4 의 정상 경로)" 0 "$(guard Edit "$EDIT_RM")"
assert "의사 있음: approve-soul 호출 통과" 0 "$(guard Bash "$(J command "python3 scripts/hermes-agent.py approve-soul 게이트QA")")"
assert "소환된 에이전트는 의사가 있어도 차단" 2 "$(HERMES_AGENT_ID=01a0b728-2040-7e30-ab2d-cee957be526e guard Bash "$(J command "python3 scripts/hermes-agent.py approve-soul 게이트QA")")"
assert "소환 차단 문구" 1 "$(grep -c '소환된 에이전트는 SOUL 을 승인할 수 없습니다' "$T/err")"
python3 -c "import json,time; json.dump({'ts': int(time.time())-4000, 'approve': True}, open('$P/.hermes/.soul-approval-intent','w'))"
assert "60분 지난 의사 → 차단" 2 "$(guard Edit "$EDIT_RM")"
rm -f "$P/.hermes/.soul-approval-intent"
assert "의사 파일 없음 → 차단" 2 "$(guard Edit "$EDIT_RM")"
# 자기 검사 — 승인 의사 확인을 무력화하면 차단이 사라진다
sed 's/^def approval_ok():/def approval_ok():\n    return True/' "$GUARD" > "$T/guard-broken.sh"
assert "자기 검사: 의사 확인을 끄면 통과해 버린다" 0 "$(GUARD_BIN="$T/guard-broken.sh" guard Edit "$EDIT_RM")"

echo "== 3절 approve-soul 명령"
H_BEFORE="$(grep -v '^> 초안 — 기계가' "$SOUL" | md5sum | cut -c1-32)"
A approve-soul 게이트QA > "$T/ap.out" 2>&1; RC=$?
assert "approve-soul rc 0" 0 "$RC"
assert "표시 줄이 사라짐" 0 "$(grep -c '초안 — 기계가' "$SOUL")"
assert "표시 줄 말고는 바뀐 것이 없다" "$H_BEFORE" "$(md5sum < "$SOUL" | cut -c1-32)" 2>/dev/null || true
assert "이력에 decision soul-approved (actor human)" 1 "$(python3 -c "
import sqlite3; con=sqlite3.connect('$P/.hermes/state.db')
print(con.execute(\"SELECT COUNT(*) FROM journal_events WHERE kind='decision' AND decision LIKE 'soul-approved%' AND actor LIKE 'human:%'\").fetchone()[0])" 2>/dev/null || echo 0)"
A approve-soul 게이트QA > "$T/ap2.out" 2>&1; RC=$?
assert "이미 승인 → rc 0 · 그대로" "0 1" "$RC $(grep -c '이미 승인' "$T/ap2.out")"
A approve-soul 없는사람 > /dev/null 2>&1; assert "없는 이름 → exit 2" 2 "$?"
assert "승인 뒤 soul-draft 는 다시 채우지 않는다" 1 "$(A soul-draft 게이트QA 2>&1 | grep -c '사람이 승인한 것')"
prompt '다음' >/dev/null
assert "승인된 SOUL 의 편집은 의사 없이도 통과(표시 줄이 없으므로)" 0 "$(guard Edit "$(J file_path "$SOUL" old_string "## 역할" new_string "## 역할 ")")"

echo "== 4절 배선"
CONF="$REPO_ROOT/presets/workflow/hermes.conf"
assert "hermes.conf 에 의사 훅 소스 등록" 1 "$(grep -c 'HARNESS_HOOK_SOURCES+=(claude-userpromptsubmit-soul-approval-intent.sh)' "$CONF")"
assert "디스패처 이름 규칙(claude-userpromptsubmit-*.sh)에 맞는다" 1 "$([[ "$(basename "$INTENT")" == claude-userpromptsubmit-*.sh ]] && echo 1 || echo 0)"
assert "스킬 문서 0-4 에 approve-soul" 1 "$([[ "$(grep -c 'approve-soul' "$REPO_ROOT/assets/skills/hermes-agent/SKILL.md")" -ge 1 ]] && echo 1 || echo 0)"

echo; echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
