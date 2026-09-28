#!/usr/bin/env bash
# hermes-chat 검증 (계획 docs/exec-plans/active/2026-09-28-hermes-chat.md 목표 1 · 3 · 7).
#
#   - 목표 1: `claude --agent <slug>` 세션 — HERMES_AGENT_ID 없이 입력 agent_type 으로 SOUL·기억이 들어간다
#             startup·resume·compact 모두 · 명부 밖 slug·은퇴자·내장(Explore) → 무출력 · 환경변수(소환)가 우선
#   - 목표 7: hermes-chat — 명부를 번호로 보이고 고르면 `claude --agent <slug> --name <이름>방`
#             이름 일부로 바로 · 은퇴자·slug 없는 사람(main) 안 보임 · 하위 폴더에서도 프로젝트를 찾음 ·
#             hermes 아님·명부 0명·틀린 번호 → 안내 후 exit 1
#   - 자기 검사: 훅의 agent_type 경로를 끄면 목표 1 이 빨개진다
#
#   - 목표 3: 방이 열리면 이력에 주인 한 줄(task.assigned match=owner, actor agent:<slug> — C-28), 세션당 한 번 ·
#             상태줄·/hermes-room 에 "주인: …" · 주인은 손님 횟수에 안 듦 · gap-check 이 닫지 않음
#
# 실행: bash tests/hermes-chat-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-sessionstart-agent-soul.sh"
CHAT="$REPO_ROOT/scripts/hermes-chat"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset HERMES_AGENT_ID

P="$T/proj"; mkdir -p "$P/.hermes/agents" "$P/src/deep"
ln -s "$REPO_ROOT/scripts" "$P/scripts"
ID_MAIN="01a0ad8a-e5ff-7026-bedf-0bbf3df3d334"
ID_QA="01a0ae58-6aa6-7202-ae81-7d27af7b5617"
ID_BL="01a0b728-2040-7e30-ab2d-cee957be526e"
ID_OLD="01a0ae58-6a84-75bd-8bfa-9c85c2ce2be4"
cat > "$P/.hermes/agents.json" <<EOF
{"agents": [
  {"agent_id": "$ID_MAIN", "name": "main", "status": "active", "org": {}},
  {"agent_id": "$ID_QA",  "name": "게이트QA", "slug": "gate-qa", "status": "probation",
   "org": {"discipline": "QA", "rank": "담당", "unit": "공통"}},
  {"agent_id": "$ID_BL",  "name": "백로그 관리자", "slug": "backlog-manager", "status": "probation",
   "org": {"discipline": "기획", "rank": "리드", "unit": "공통"}},
  {"agent_id": "$ID_OLD", "name": "옛담당", "slug": "old-hand", "status": "retired",
   "org": {"discipline": "QA", "rank": "담당", "unit": "공통"}}
]}
EOF
for id in "$ID_QA" "$ID_BL" "$ID_OLD"; do
  mkdir -p "$P/.hermes/agents/$id"
  printf '# 정체성 %s\n\n## 역할\n백로그를 정리하고 우선순위를 매긴다.\n' "$id" > "$P/.hermes/agents/$id/SOUL.md"
  printf '# 기억\n\n- 2026-09-28 백로그 12건 분류\n' > "$P/.hermes/agents/$id/MEMORY.md"
done

soul() {  # soul <source> <agent_type> [HERMES_AGENT_ID] → stdout
  local js; js="$(python3 -c "import json,sys; print(json.dumps({'session_id':'t','source':sys.argv[1],'agent_type':sys.argv[2]} if sys.argv[2] else {'session_id':'t','source':sys.argv[1]}))" "$1" "$2")"
  if [[ -n "${3:-}" ]]; then printf '%s' "$js" | HERMES_AGENT_ID="$3" HERMES_PROJECT_DIR="$P" bash "$HOOK" 2>/dev/null
  else printf '%s' "$js" | env -u HERMES_AGENT_ID HERMES_PROJECT_DIR="$P" bash "$HOOK" 2>/dev/null; fi
}
head1() { printf '%s\n' "$1" | head -1 | sed 's/).*/)/'; }   # 머리줄의 이름·id 까지만

echo "== 목표 1 — --agent 세션에 SOUL·기억"
O="$(soul startup backlog-manager)"
assert "startup: 머리줄이 백로그 관리자" "[헤르메스 출근] 백로그 관리자 (agent:$ID_BL)" "$(head1 "$O")"
assert "  SOUL 본문" 1 "$(grep -c '우선순위를 매긴다' <<<"$O")"
assert "  MEMORY 본문" 1 "$(grep -c '백로그 12건 분류' <<<"$O")"
assert "resume 에도 들어간다" "[헤르메스 출근] 백로그 관리자 (agent:$ID_BL)" "$(head1 "$(soul resume backlog-manager)")"
assert "compact 에도 들어간다" "[헤르메스 출근] 게이트QA (agent:$ID_QA)" "$(head1 "$(soul compact gate-qa)")"
assert "명부 밖 slug(code-reviewer) → 0 B" 0 "$(soul startup code-reviewer | wc -c | tr -d ' ')"
assert "내장 Explore → 0 B" 0 "$(soul startup Explore | wc -c | tr -d ' ')"
assert "은퇴자 → 0 B" 0 "$(soul startup old-hand | wc -c | tr -d ' ')"
assert "agent_type 없는 보통 세션 → 0 B" 0 "$(soul startup '' | wc -c | tr -d ' ')"
assert "HERMES_AGENT_ID(소환)가 agent_type 보다 우선" "[헤르메스 출근] 게이트QA (agent:$ID_QA)" "$(head1 "$(soul startup backlog-manager "$ID_QA")")"

echo "== 목표 7 — hermes-chat 고르기"
chat() {  # chat <stdin> <cwd> [args…] → stdout+stderr, rc 는 $RC
  local input="$1" cwd="$2"; shift 2
  OUT="$(cd "$cwd" && printf '%s\n' "$input" | bash "$CHAT" --dry-run "$@" 2>&1)"; RC=$?
}
chat "2" "$P"
assert "번호 목록에 게이트QA" 1 "$(grep -c '1) 게이트QA' <<<"$OUT")"
assert "번호 목록에 백로그 관리자" 1 "$(grep -c '2) 백로그 관리자' <<<"$OUT")"
assert "분야/직급/조직 표기" 1 "$(grep -c '기획/리드/공통' <<<"$OUT")"
assert "은퇴자 안 보임" 0 "$(grep -c '옛담당' <<<"$OUT")"
assert "main(slug 없음) 안 보임" 0 "$(grep -c ') main' <<<"$OUT")"
assert "2 → 백로그 관리자 방 명령" 1 "$(grep -cx 'claude --agent backlog-manager --name 백로그관리자방' <<<"$OUT")"
assert "돌아오기 안내" 1 "$(grep -c 'claude --resume 백로그관리자방' <<<"$OUT")"
assert "  rc 0" 0 "$RC"
chat "" "$P" 게이트
assert "이름 일부로 바로(번호 없이)" 1 "$(grep -cx 'claude --agent gate-qa --name 게이트QA방' <<<"$OUT")"
assert "  목록을 띄우지 않음" 0 "$(grep -c '번호:' <<<"$OUT")"
chat "1" "$P/src/deep"
assert "하위 폴더에서도 프로젝트를 찾음" 1 "$(grep -cx 'claude --agent gate-qa --name 게이트QA방' <<<"$OUT")"
chat "9" "$P"; assert "틀린 번호 → exit 1" 1 "$RC"
assert "  명령을 내지 않음" 0 "$(grep -c '^claude --agent' <<<"$OUT")"
chat "" "$P"; assert "빈 입력 → exit 1" 1 "$RC"
mkdir -p "$T/plain"; chat "1" "$T/plain"; assert "hermes 프로젝트 아님 → exit 1" 1 "$RC"
assert "  안내문" 1 "$(grep -c '헤르메스 프로젝트' <<<"$OUT")"
E="$T/empty"; mkdir -p "$E/.hermes"; ln -s "$REPO_ROOT/scripts" "$E/scripts"
printf '{"agents":[{"agent_id":"%s","name":"main","status":"active","org":{}}]}' "$ID_MAIN" > "$E/.hermes/agents.json"
chat "1" "$E"; assert "명부 0명 → exit 1" 1 "$RC"
assert "  입사 안내" 1 "$(grep -c 'hire' <<<"$OUT")"

echo "== 목표 3 — 방 주인이 이력·상태줄에 보인다"
OWNER="$REPO_ROOT/assets/hooks/claude-sessionstart-room-owner.sh"
J() { env -u HERMES_AGENT_ID python3 "$REPO_ROOT/scripts/hermes-journal.py" --project "$P" "$@"; }
J emit --json '{"kind":"decision","intent":"픽스처 — 이력 DB 만들기"}' >/dev/null 2>&1
own() {  # own <session> <source> <agent_type> [HERMES_AGENT_ID]
  local js; js="$(python3 -c "import json,sys; print(json.dumps({'session_id':sys.argv[1],'source':sys.argv[2],'agent_type':sys.argv[3]}))" "$1" "$2" "$3")"
  if [[ -n "${4:-}" ]]; then printf '%s' "$js" | HERMES_AGENT_ID="$4" CLAUDE_PROJECT_DIR="$P" bash "$OWNER" >/dev/null 2>&1
  else printf '%s' "$js" | env -u HERMES_AGENT_ID CLAUDE_PROJECT_DIR="$P" bash "$OWNER" >/dev/null 2>&1; fi
}
q() { python3 -c "import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone()[0])" "$P/.hermes/state.db" "$1"; }
S1="11111111-aaaa-bbbb-cccc-000000000001"
own "$S1" startup backlog-manager
assert "주인 한 줄(task.assigned match=owner)" 1 "$(q "SELECT COUNT(*) FROM journal_events WHERE session_id='$S1' AND decision LIKE 'match=owner %'")"
assert "  actor 는 agent:<slug> (C-28)" "agent:backlog-manager" "$(q "SELECT actor FROM journal_events WHERE session_id='$S1' AND decision LIKE 'match=owner %'")"
assert "  decision 에 명부 id" 1 "$(q "SELECT COUNT(*) FROM journal_events WHERE session_id='$S1' AND decision LIKE '%agent=$ID_BL%'")"
own "$S1" resume backlog-manager; own "$S1" compact backlog-manager
assert "resume·compact 에 겹쳐 적지 않음" 1 "$(q "SELECT COUNT(*) FROM journal_events WHERE session_id='$S1' AND decision LIKE 'match=owner %'")"
own "S-x" startup code-reviewer; own "S-y" startup old-hand; own "S-z" startup backlog-manager "$ID_QA"
assert "명부 밖·은퇴자·소환 세션은 적지 않음" 0 "$(q "SELECT COUNT(*) FROM journal_events WHERE session_id IN ('S-x','S-y','S-z')")"
assert "끝나지 않은 일로 닫히지 않음(gap-check)" 0 "$(J gap-check --all 2>/dev/null)"
L="$(env -u HERMES_AGENT_ID python3 "$REPO_ROOT/scripts/hermes-agent.py" --project "$P" room --session "$S1" --line 2>&1)"
assert "상태줄: 주인이 앞에" 1 "$(grep -c '^주인: 백로그 관리자 · 지금: 없음' <<<"$L")"
assert "  주인은 손님으로 세지 않음" 1 "$(grep -c '이 방에서 불린 명부 에이전트 없음' <<<"$L")"
J emit --json "{\"kind\":\"task.finished\",\"task_id\":\"t-guest\",\"actor\":\"agent:$ID_QA\",\"session_id\":\"$S1\",\"claimed\":\"success\",\"evidence\":{\"template\":\"gate-qa\"}}" >/dev/null 2>&1
L="$(env -u HERMES_AGENT_ID python3 "$REPO_ROOT/scripts/hermes-agent.py" --project "$P" room --session "$S1" --line 2>&1)"
assert "주인 + 손님 1명" 1 "$(grep -c '^주인: 백로그 관리자 · 지금: 없음 · 이 방에서 불림: 게이트QA 1회$' <<<"$L")"
F="$(env -u HERMES_AGENT_ID python3 "$REPO_ROOT/scripts/hermes-agent.py" --project "$P" room --session "$S1" 2>&1)"
assert "/hermes-room 상세에 방 주인" 1 "$(grep -c '^방 주인: 백로그 관리자' <<<"$F")"
L="$(env -u HERMES_AGENT_ID python3 "$REPO_ROOT/scripts/hermes-agent.py" --project "$P" room --session "S-none" --line 2>&1)"
assert "주인 없는 보통 방은 예전 그대로" 1 "$(grep -c '^지금: 없음 · 이 방에서 불린 명부 에이전트 없음$' <<<"$L")"

echo "== 자기 검사 — agent_type 경로를 끄면 목표 1 이 빨개진다"
M="$T/mut.sh"; sed 's/agent_type/agent_type_OFF/g' "$HOOK" > "$M"
O="$(printf '{"source":"startup","agent_type":"backlog-manager"}' | env -u HERMES_AGENT_ID HERMES_PROJECT_DIR="$P" bash "$M" 2>/dev/null)"
assert "변이 훅은 아무것도 넣지 않는다" 0 "$(printf '%s' "$O" | wc -c | tr -d ' ')"

echo ""; echo "결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
