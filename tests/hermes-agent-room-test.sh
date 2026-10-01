#!/usr/bin/env bash
# 전체 명부·"이 방" 구성원 보기 검증 (계획 docs/exec-plans/active/2026-09-28-agent-room-view.md).
#
#   1. roster (목표 1) — 이름·@호출명·상태·조직·최근 불린 때, 은퇴자는 맨 아래
#   2. room  (목표 2) — 한 세션만: 명부 에이전트(이름·횟수·마지막) · 명부 밖(종류·횟수) · 내부 보조(claude) 건수, --line 한 줄
#   3. 스킬  (목표 3) — /hermes-roster · /hermes-room 설치, 사람만 부름, !`…` 주입 결과 = 명령 출력
#
# 실행: bash tests/hermes-agent-room-test.sh

set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0   # 설치기의 외부 도구 다운로드는 끈다(네트워크 0)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/fakehome"; mkdir -p "$HOME"
export TZ=UTC   # 표시는 현지 시각 — 시험은 UTC 로 고정해 시각 단언이 기계마다 흔들리지 않게

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q; git -C "$P" config user.name tester
bash "$REPO_ROOT/project-claude.sh" "$P" harness hermes >"$TMP/install.log" 2>&1
cp "$REPO_ROOT/assets/templates/organization/product.yaml" "$P/.hermes/organization.yaml"
A() { env -u HERMES_AGENT_ID python3 "$P/scripts/hermes-agent.py" --project "$P" "$@"; }
aid() { python3 -c "import json,sys;print([a['agent_id'] for a in json.load(open(sys.argv[1]))['agents'] if a['name']==sys.argv[2]][0])" "$P/.hermes/agents.json" "$1"; }
ev() { env -u HERMES_AGENT_ID python3 "$P/scripts/hermes-journal.py" --project "$P" emit --json "$1" >/dev/null 2>&1; }
fin() {  # fin <session> <actor-id> <template> <ts>
  ev "{\"kind\":\"task.finished\",\"task_id\":\"t-$RANDOM$RANDOM\",\"actor\":\"agent:$2\",\"session_id\":\"$1\",\"claimed\":\"success\",\"evidence\":{\"template\":\"$3\"},\"ts\":\"$4\"}"; }

A hire 백로그담당 --org 기획,담당,공통 --slug backlog-lead >/dev/null 2>&1
A hire 조용한담당 --org 기획,담당,공통 >/dev/null 2>&1
A hire 떠난담당 --org 기획,담당,공통 --slug gone-lead >/dev/null 2>&1
A retire 떠난담당 >/dev/null 2>&1
BL="$(aid 백로그담당)"; GL="$(aid 떠난담당)"
assert "전제: 이력 DB" 1 "$([[ -f "$P/.hermes/state.db" ]] && echo 1 || echo 0)"

S1="11111111-aaaa-bbbb-cccc-000000000001"; S2="22222222-aaaa-bbbb-cccc-000000000002"
fin "$S1" "$BL" backlog-lead 2026-09-28T01:00:00Z
fin "$S1" "$BL" backlog-lead 2026-09-28T02:30:00Z
fin "$S1" sub-cr-1 code-reviewer 2026-09-28T01:10:00Z
fin "$S1" sub-cg-1 claude-code-guide 2026-09-28T01:20:00Z
for i in 1 2 3; do fin "$S1" "sub-in-$i" claude 2026-09-28T01:3$i:00Z; done
fin "$S2" "$BL" backlog-lead 2026-09-28T05:00:00Z          # 다른 방 — 방 보기에서는 안 센다, 최근 불린 때에는 든다
fin "$S2" "$GL" gone-lead 2026-09-27T09:00:00Z

echo "== 1. roster (목표 1) =="
A roster >"$TMP/roster" 2>&1; assert "roster rc 0" 0 "$?"
row() { grep -F "$1" "$TMP/roster" | head -1; }
assert "백로그담당 줄에 @호출명" 1 "$(row 백로그담당 | grep -c '@agent-backlog-lead')"
assert "백로그담당 최근 불린 때 = 모든 방 중 최댓값(05:00)" 1 "$(row 백로그담당 | grep -c '2026-09-28 05:00')"
assert "slug 없는 재직자는 호출명 -" 1 "$(row 조용한담당 | grep -cE '[[:space:]]-[[:space:]]')"
assert "한 번도 안 불린 에이전트는 최근 불린 때 -" 1 "$(row 조용한담당 | grep -cE '[[:space:]]-$')"
assert "은퇴자는 맨 아래" 떠난담당 "$(grep -vE '^\s*$|^이름|^─|^\(|^방 열기|^  ' "$TMP/roster" | tail -1 | awk '{print $1}')"
# 목표 4 (hermes-chat): 표 아래에 방 여는 명령 — 호출명(slug)이 있는 재직자마다 한 줄, 은퇴자·호출명 없는 사람은 없다
assert "재직자(호출명 있음)마다 방 여는 명령" "claude --agent backlog-lead --name 백로그담당방" \
  "$(grep -oE 'claude --agent backlog-lead --name [^ ]+' "$TMP/roster")"
assert "  은퇴자 방 여는 명령은 없다" 0 "$(grep -c 'claude --agent gone-lead' "$TMP/roster")"
assert "  호출명 없는 재직자도 없다" 0 "$(grep -c '조용한담당방' "$TMP/roster")"
assert "  이름을 몰라도 hermes-chat 안내" 1 "$(grep -c 'hermes-chat' "$TMP/roster")"
assert "  방 여는 명령은 표 아래(표 행보다 뒤)" 1 "$(awk '/^백로그담당/{r=NR} /claude --agent backlog-lead/{c=NR} END{print (r>0 && c>r)?1:0}' "$TMP/roster")"
assert "main 은 명부 보기에서 빠진다(사람이 아닌 세션 주체)" 0 "$(grep -cE '^main[[:space:]]' "$TMP/roster")"

echo ""
echo "== 2. room (목표 2) =="
A room --session "$S1" >"$TMP/room" 2>&1; assert "room rc 0" 0 "$?"
assert "명부 에이전트: 백로그담당 2회, 마지막 02:30" 1 "$(grep -F 백로그담당 "$TMP/room" | grep -c '2회.*02:30')"
assert "다른 방의 05:00 은 안 센다" 0 "$(grep -c '05:00' "$TMP/room")"
assert "다른 방의 떠난담당은 없다" 0 "$(grep -c 떠난담당 "$TMP/room")"
assert "명부 밖: code-reviewer 1" 1 "$(grep -cE 'code-reviewer[^0-9]+1' "$TMP/room")"
assert "명부 밖: claude-code-guide 1" 1 "$(grep -cE 'claude-code-guide[^0-9]+1' "$TMP/room")"
assert "내부 보조는 이름 없이 건수(3)" 1 "$(grep -cE '보조 호출[^0-9]+3' "$TMP/room")"
assert "상세 보기 첫 줄: 지금 일하는 중 없음" 1 "$(grep -c '^지금 일하는 중: 없음' "$TMP/room")"
assert "--line: 지금·이 방에서 불림만(도구·보조는 상세 보기로)" "지금: 없음 · 이 방에서 불림: 백로그담당 2회" "$(A room --session "$S1" --line)"
assert "--line 명부 에이전트 없는 방" "지금: 없음 · 이 방에서 불린 명부 에이전트 없음" "$(A room --session nobody-session --line)"
# @ 호출이 시작만 되고 아직 안 끝났다 = 지금 일하는 중 (task.assigned decision 에 명부 id — SubagentStart 이력 훅 모양)
ev "{\"kind\":\"task.assigned\",\"task_id\":\"sub-run-1\",\"actor\":\"agent:main\",\"session_id\":\"$S1\",\"decision\":\"match=mention slug=backlog-lead agent=$BL\",\"evidence\":{\"template\":\"backlog-lead\"},\"ts\":\"2026-09-28T03:00:00Z\"}"
ev "{\"kind\":\"task.assigned\",\"task_id\":\"sub-done-1\",\"actor\":\"agent:main\",\"session_id\":\"$S1\",\"decision\":\"match=mention slug=backlog-lead agent=$BL\",\"evidence\":{\"template\":\"backlog-lead\"},\"ts\":\"2026-09-28T02:29:00Z\"}"
ev "{\"kind\":\"task.finished\",\"task_id\":\"sub-done-1\",\"actor\":\"agent:$BL\",\"session_id\":\"$S1\",\"claimed\":\"success\",\"evidence\":{\"template\":\"backlog-lead\"},\"ts\":\"2026-09-28T02:31:00Z\"}"
assert "시작만 있는 @ 호출 → 지금 일하는 중, 끝난 것은 셈만" "지금: 백로그담당 일하는 중 · 이 방에서 불림: 백로그담당 4회" "$(A room --session "$S1" --line)"
assert "상세 보기에도 일하는 중" 1 "$(A room --session "$S1" | grep -c '^지금 일하는 중: 백로그담당')"
assert "다른 방에서는 일하는 중이 안 보인다" "지금: 없음 · 이 방에서 불림: 백로그담당 1회, 떠난담당 1회" "$(A room --session "$S2" --line)"
A room >/dev/null 2>&1; assert "세션 없이 부르면 rc 0(안내만)" 0 "$?"
mv "$P/.hermes/state.db" "$TMP/state.db.hold"
assert "DB 없음 --line → 빈 방 한 줄" "지금: 없음 · 이 방에서 불린 명부 에이전트 없음" "$(A room --session "$S1" --line)"
mv "$TMP/state.db.hold" "$P/.hermes/state.db"

echo ""
echo "== 3. 슬래시 명령 스킬 (목표 3) — 설치본 스킬의 !\`…\` 줄을 Claude Code 처럼 치환해 돌린다 =="
bang() {  # bang <skill> — 첫 !`…` 줄의 명령을 치환 후 실행
  local line; line="$(grep -m1 '^!`' "$P/.claude/skills/$1/SKILL.md")"; line="${line#!\`}"; line="${line%\`}"
  line="${line//\$\{CLAUDE_PROJECT_DIR\}/$P}"; line="${line//\$\{CLAUDE_SESSION_ID\}/$S1}"
  env -u HERMES_AGENT_ID bash -c "$line"; }
for sk in hermes-roster hermes-room; do
  assert "설치본에 $sk 스킬" 1 "$([[ -f "$P/.claude/skills/$sk/SKILL.md" ]] && echo 1 || echo 0)"
  assert "$sk 는 사람만 부른다(disable-model-invocation: true)" 1 "$(grep -c '^disable-model-invocation: true$' "$P/.claude/skills/$sk/SKILL.md")"
done
assert "/hermes-roster 주입 결과 = roster 명령 출력" "$(A roster | md5sum)" "$(bang hermes-roster | md5sum)"
assert "/hermes-room 주입 결과 = room --session 출력" "$(A room --session "$S1" | md5sum)" "$(bang hermes-room | md5sum)"
assert "/hermes-room 주입 결과에 이 방의 명부 에이전트" 1 "$(bang hermes-room | grep -q 백로그담당 && echo 1 || echo 0)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
