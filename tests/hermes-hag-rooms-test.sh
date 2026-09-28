#!/usr/bin/env bash
# `@hag` 방 UI 검증 (계획 docs/exec-plans/active/2026-09-28-hag-rooms-ui.md 목표 1~6).
#
#   - 상태: 세션별 켜짐/꺼짐 · 세션 id 꼴이 아니면 거부(경로 탈출 방지)
#   - 방 목록: `claude agents --json` 중 이 프로젝트(루트와 같거나 아래) + 방 주인 기록이 있는 세션만 · 형제 폴더·메인 세션 제외
#   - 명령(훅이 막음 = exit 2): @hag-on/off · @hag-add(고른 줄·이름·맨몸) · @hag-rm(고른 줄·맨몸)
#       · 방 열기 인자(--bg --agent <slug> --name <이름>방) · cwd=프로젝트 루트 · 자식에 HERMES_*·CLAUDE_ENV_FILE 없음
#       · 같은 에이전트 방이 있으면 안 연다(이름이 달라도) · 닫기는 stop(지우기 없음)
#   - 제안 목록: hag 에 명령 줄 · hag-add 에 방 없는 사람만 · hag-rm 에 열린 방
#   - 상태줄: 켜짐이면 "방: …" 줄, 꺼짐이면 없음 · 목록 실패 → "방: 목록을 못 읽었습니다"
#   - 자기 검사: 환경변수 허용목록을 끄면 HERMES_* 가 자식에 샌다(시험이 잡는다)
#
# 실행: bash tests/hermes-hag-rooms-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_ROOT/scripts"
HOOK="$REPO_ROOT/assets/hooks/claude-userpromptsubmit-hag.sh"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset HERMES_AGENT_ID HERMES_SUMMON_NONCE

echo "== 0. 픽스처 — 명부 둘 · 이력 DB · 가짜 claude"
P="$T/proj"; mkdir -p "$P/.hermes" "$P/src"
ln -s "$S" "$P/scripts"
cat > "$P/.hermes/agents.json" <<'EOF'
{"agents": [
  {"agent_id": "01a0ad8a-e5ff-7026-bedf-0bbf3df3d334", "name": "main", "status": "active", "org": {}},
  {"agent_id": "01a0ae58-6aa6-7202-ae81-7d27af7b5617", "name": "게이트QA", "slug": "gate-qa", "status": "probation",
   "org": {"discipline": "QA", "rank": "담당", "unit": "공통"}},
  {"agent_id": "01a0b728-2040-7e30-ab2d-cee957be526e", "name": "백로그 관리자", "slug": "backlog-manager", "status": "probation",
   "org": {"discipline": "기획", "rank": "리드", "unit": "공통"}}
]}
EOF
J() { env -u HERMES_AGENT_ID python3 "$S/hermes-journal.py" --project "$P" emit --json "$1" >/dev/null 2>&1; }
SA="aaaa1111-0000-0000-0000-000000000001"; SB="bbbb2222-0000-0000-0000-000000000002"
J "{\"kind\":\"task.assigned\",\"session_id\":\"$SA\",\"actor\":\"agent:gate-qa\",\"decision\":\"match=owner slug=gate-qa agent=01a0ae58-6aa6-7202-ae81-7d27af7b5617\",\"evidence\":{\"template\":\"gate-qa\"}}"
assert "전제: 이력 DB" 1 "$([[ -f "$P/.hermes/state.db" ]] && echo 1 || echo 0)"

FAKE="$T/fake"; mkdir -p "$FAKE"
cat > "$FAKE/claude" <<'EOF'
#!/usr/bin/env bash
d="$(dirname "$0")"
{ echo "ARGS $*"; echo "CWD $PWD"; env | grep -E '^(HERMES_|CLAUDE_ENV_FILE)' | sed 's/^/ENV /'; } >> "$d/log"
[[ -f "$d/fail" ]] && { echo "boom" >&2; exit 1; }
case "$1" in
  agents) cat "$d/agents.json" ;;
  --bg)   echo "backgrounded · cccc3333 · $6" ;;
  stop)   echo "stopped $2" ;;
esac
EOF
chmod +x "$FAKE/claude"
cat > "$FAKE/agents.json" <<EOF
[{"id":"aaaa1111","sessionId":"$SA","name":"테스트방","status":"idle","state":"idle","cwd":"$P","kind":"bg"},
 {"id":"dddd4444","sessionId":"dddd4444-0000-0000-0000-000000000004","name":"메인","status":"busy","state":"busy","cwd":"$P","kind":"bg"},
 {"id":"eeee5555","sessionId":"eeee5555-0000-0000-0000-000000000005","name":"남의","status":"idle","state":"idle","cwd":"$P-other","kind":"bg"}]
EOF
export HERMES_CLAUDE_BIN="$FAKE/claude"
: > "$FAKE/log"

echo "== 1. 상태"
st() { local fn="$1"; shift; PYTHONPATH="$S" python3 -c "import sys; from hermes_hag_state import $fn; print($fn(*sys.argv[1:]))" "$@" 2>&1 | tail -1; }
SES="11111111-aaaa-bbbb-cccc-000000000001"
assert "처음엔 꺼짐" False "$(st is_on "$P" "$SES")"
PYTHONPATH="$S" python3 -c "from hermes_hag_state import set_on; set_on('$P','$SES',True)"
assert "켜면 켜짐" True "$(st is_on "$P" "$SES")"
assert "다른 세션은 꺼짐" False "$(st is_on "$P" "22222222-aaaa-bbbb-cccc-000000000002")"
assert "세션 id 꼴 아니면 거부" 1 "$(PYTHONPATH="$S" python3 -c "from hermes_hag_state import set_on; set_on('$P','../x',True)" >/dev/null 2>&1 && echo 0 || echo 1)"

echo "== 2. 방 목록"
R="$(PYTHONPATH="$S" python3 -c "
from hermes_hag_rooms import list_rooms
for r in list_rooms('$P'): print(r['id'], r['slug'], r['status'])")"
assert "방 주인 기록 있는 이 프로젝트 세션만" "aaaa1111 gate-qa idle" "$R"

echo "== 3. 명령 (훅, exit 2)"
send() {  # send <prompt> → OUT(stderr) RC
  local js; js="$(python3 -c "import json,sys; print(json.dumps({'session_id':'$SES','prompt':sys.argv[1]}))" "$1")"
  OUT="$(printf '%s' "$js" | CLAUDE_PROJECT_DIR="$P" HERMES_AGENT_ID="01a0ad8a-e5ff-7026-bedf-0bbf3df3d334" HERMES_SUMMON_NONCE="n-1" CLAUDE_ENV_FILE="$T/envfile" bash "$HOOK" 2>&1 >/dev/null)"; RC=$?
}
send '@hag-off'; assert "@hag-off → 막음(2)" 2 "$RC"; assert "  꺼짐" False "$(st is_on "$P" "$SES")"
send '@hag-on';  assert "@hag-on → 막음(2)" 2 "$RC"; assert "  켜짐" True "$(st is_on "$P" "$SES")"
assert "  안내 한 줄" 1 "$(grep -c . <<<"$OUT")"
: > "$FAKE/log"
send '@"백로그 관리자 · 기획/리드/공통 · hag-add:backlog-manager"'
assert "고른 줄로 초대 → 막음" 2 "$RC"
assert "  --bg 인자" 1 "$(grep -c '^ARGS --bg --agent backlog-manager --name 백로그관리자방$' "$FAKE/log")"
assert "  모든 claude 호출의 cwd = 프로젝트 루트" "$(grep -c '^CWD ' "$FAKE/log")" "$(grep -c "^CWD $P$" "$FAKE/log")"
assert "  자식에 HERMES_*·CLAUDE_ENV_FILE 없음" 0 "$(grep -c '^ENV ' "$FAKE/log")"
: > "$FAKE/log"
send '@hag-add 게이트'
assert "이미 방 있는 에이전트 → 안 연다" 0 "$(grep -c '^ARGS --bg' "$FAKE/log")"
assert "  이미 있음 안내" 1 "$(has "$OUT" '이미')"
send '@hag-add'
assert "맨몸 @hag-add → 막고 초대할 사람 안내" 1 "$(has "$OUT" '백로그 관리자')"
assert "  방 있는 사람은 목록에 없음" 0 "$(has "$OUT" '게이트QA')"
: > "$FAKE/log"
send '@"게이트QA방 · 대기 · hag-rm:aaaa1111"'
assert "고른 줄로 닫기 → stop" 1 "$(grep -c '^ARGS stop aaaa1111$' "$FAKE/log")"
assert "  지우기(rm) 없음" 0 "$(grep -c '^ARGS rm' "$FAKE/log")"
send '@hag-rm'
assert "맨몸 @hag-rm → 열린 방 안내" 1 "$(has "$OUT" '게이트QA')"
send '평범한 말'; assert "평범한 말 → 통과(0)" 0 "$RC"
# 리뷰 HIGH — 문장 속 언급은 명령이 아니다(맨 앞에 있을 때만)
send '그냥 @hag-off 치면 꺼지는 거 맞죠? 물어보는 겁니다'
assert "문장 속 @hag-off → 통과(0)" 0 "$RC"; assert "  상태 그대로(켜짐)" True "$(st is_on "$P" "$SES")"
: > "$FAKE/log"
send '이렇게 @hag-add 백로그 하면 돼?'
assert "문장 속 @hag-add → 통과" 0 "$RC"; assert "  방 안 연다" 0 "$(grep -c '^ARGS --bg' "$FAKE/log")"
send '@hag-add 백로그 좀 불러줘'
assert "@hag-add + 여러 단어 → 통과(논의로 봄)" 0 "$RC"; assert "  방 안 연다" 0 "$(grep -c '^ARGS --bg' "$FAKE/log")"
send '@hag-on 켜 줘'
assert "@hag-on + 말 → 통과" 0 "$RC"
send '`@hag-on` 은 뭐야'; assert "백틱 안 명령 → 통과" 0 "$RC"; assert "  상태 그대로(켜짐)" True "$(st is_on "$P" "$SES")"

echo "== 4. 제안 목록"
sug() { python3 -c "import json,sys; print(json.dumps({'query':sys.argv[1],'cwd':'$P'}))" "$1" | python3 "$S/hermes_file_suggest.py" 2>/dev/null; }
O="$(sug hag)"
assert "@hag 에 켜기 명령" 1 "$(has "$O" 'hag-on')"
assert "@hag 에 초대 명령" 1 "$(has "$O" 'hag-add')"
assert "@hag 에 명부도" 1 "$(has "$O" 'hag:gate-qa')"
O="$(sug hag-add)"
assert "@hag-add → 방 없는 사람만" "백로그 관리자 · 기획/리드/공통 · hag-add:backlog-manager" "$O"
O="$(sug hag-rm)"
assert "@hag-rm → 열린 방" 1 "$(has "$O" 'hag-rm:aaaa1111')"
assert "줄마다 첫 글자가 다르다(@hag)" "$(sug hag | grep -c .)" "$(sug hag | cut -c1-3 | sort -u | grep -c .)"

echo "== 5. 상태줄"
line() { env -u HERMES_AGENT_ID python3 "$S/hermes-agent.py" --project "$P" room --session "$1" --line 2>/dev/null; }
PYTHONPATH="$S" python3 -c "from hermes_hag_rooms import refresh_cache; refresh_cache('$P')"
assert "켜짐 → 방 줄" 1 "$(line "$SES" | grep -c '^방: 게이트QA 대기 · ← 로 이동$')"
assert "꺼진 세션 → 방 줄 없음" 0 "$(line "22222222-aaaa-bbbb-cccc-000000000002" | grep -c '^방:')"
touch "$FAKE/fail"; PYTHONPATH="$S" python3 -c "from hermes_hag_rooms import refresh_cache; refresh_cache('$P')" 2>/dev/null; rm -f "$FAKE/fail"
assert "목록 실패 → 못 읽음 줄" 1 "$(line "$SES" | grep -c '^방: 목록을 못 읽었습니다$')"

echo "== 6. 리뷰 반영 — 갱신 겹침 막기 · 방 id 형식"
: > "$FAKE/log"; python3 - "$P" <<'PY'
import json, os, sys, time
p = sys.argv[1]; c = os.path.join(p, ".hermes", "hag", "rooms.json")
d = json.load(open(c)); d["ts"] = time.time() - 60; json.dump(d, open(c, "w"))     # 캐시를 오래된 것으로
open(os.path.join(p, ".hermes", "hag", "rooms.refreshing"), "w").close()            # 갱신이 이미 도는 중
PY
line "$SES" >/dev/null; sleep 1
assert "갱신 중이면 새 갱신을 안 던진다" 0 "$(grep -c '^ARGS agents' "$FAKE/log")"
rm -f "$P/.hermes/hag/rooms.refreshing"; line "$SES" >/dev/null; sleep 2
assert "갱신 중 표시가 없으면 한 번 던진다" 1 "$(grep -c '^ARGS agents' "$FAKE/log")"
assert "갱신이 끝나면 표시를 지운다" 0 "$([[ -e "$P/.hermes/hag/rooms.refreshing" ]] && echo 1 || echo 0)"
: > "$FAKE/log"
assert "방 id 가 '-' 로 시작하면 stop 안 부름" 1 "$(PYTHONPATH="$S" python3 -c "
from hermes_hag_rooms import stop_room, RoomsError
try: stop_room('$P', '--all'); print(0)
except RoomsError: print(1)")"
assert "  claude 호출 없음" 0 "$(grep -c '^ARGS stop' "$FAKE/log")"

echo "== 자기 검사 — 허용목록을 끄면 HERMES_* 가 샌다"
M="$T/mut"; mkdir -p "$M"; for f in "$S"/*.py; do ln -s "$f" "$M/"; done
rm "$M/hermes_hag_rooms.py"; sed 's/env=_child_env()/env=dict(os.environ)/' "$S/hermes_hag_rooms.py" > "$M/hermes_hag_rooms.py"
: > "$FAKE/log"
HERMES_AGENT_ID=x-leak PYTHONPATH="$M" python3 -c "
from hermes_hag_rooms import open_room; open_room('$P', {'slug':'backlog-manager','name':'백로그 관리자'})" >/dev/null 2>&1
assert "변이 → 자식에 HERMES_AGENT_ID 가 샌다" 1 "$(grep -c '^ENV HERMES_AGENT_ID=x-leak' "$FAKE/log")"

echo ""; echo "결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
