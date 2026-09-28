#!/usr/bin/env bash
# 상태줄 감싸개 검증 (계획 docs/exec-plans/active/2026-09-28-agent-room-view.md 목표 6).
#
#   설치기가 전역 statusLine 을 헤르메스 감싸개(~/.claude/hermes-statusline.sh)로 바꾸고 원래 명령은 .orig 에 둔다.
#   감싸개는 원래 상태줄을 그대로 찍고, 헤르메스 프로젝트면 방 줄을 한 줄 더한다. 사용자 스크립트는 고치지 않는다
#   (단, 2026-09-28 이 컴퓨터에 손으로 붙인 11줄은 걷어낸다 — 두 번 찍히지 않게).
#   A. 상태줄 스크립트 + 손 11줄   B. 상태줄 없음   C. 끄기 스위치   D. 사용자 refreshInterval 존중   E. 설치기 연결
#
# 실행: bash tests/hermes-statusline-test.sh

set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/fakehome"; mkdir -p "$HOME"; export TZ=UTC
unset CLAUDE_CONFIG_DIR HERMES_STATUSLINE

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
SETUP="$REPO_ROOT/scripts/hermes_statusline_setup.py"
setup() { CLAUDE_CONFIG_DIR="$1" python3 "$SETUP" "${@:2}"; }
sj() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(json.dumps(d.get('statusLine'),ensure_ascii=False,sort_keys=True))" "$1/settings.json"; }
key() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print((d.get('statusLine') or {}).get(sys.argv[2],'(없음)'))" "$1/settings.json" "$2"; }

# 헤르메스가 깔린 프로젝트(방 줄이 나올 곳)
P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q; git -C "$P" config user.name tester
bash "$REPO_ROOT/project-claude.sh" "$P" harness hermes >"$TMP/install.log" 2>&1
J() { printf '{"session_id":"%s","model":{"display_name":"M"},"workspace":{"project_dir":"%s"}}' "$2" "$1"; }

echo "== A. 상태줄 스크립트 + 이 컴퓨터의 손 11줄 =="
C="$TMP/cfgA"; mkdir -p "$C"
cat >"$C/statusline.sh" <<'EOF'
#!/usr/bin/env bash
input=$(cat)
project_dir=$(echo "$input" | python3 -c 'import json,sys;print(json.load(sys.stdin)["workspace"]["project_dir"])')
printf "ORIG | %s" "${project_dir##*/}"
EOF
cp "$C/statusline.sh" "$TMP/statusline.clean"
cat >>"$C/statusline.sh" <<'EOF'

# 헤르메스 방 구성원(둘째 줄) — 이 방(세션)에서 불린 에이전트. 헤르메스가 깔린 프로젝트에서만, 실패하면 아무것도 안 찍는다.
if command -v jq >/dev/null 2>&1; then
    session_id=$(echo "$input" | jq -r '.session_id // empty')
else
    session_id=$(echo "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
if [ -n "$project_dir" ] && [ -n "$session_id" ] && [ -f "$project_dir/scripts/hermes-agent.py" ] && [ -f "$project_dir/.hermes/agents.json" ]; then
    room=$(timeout 1 python3 "$project_dir/scripts/hermes-agent.py" --project "$project_dir" room --session "$session_id" --line 2>/dev/null)
    [ -n "$room" ] && printf "\n%s" "$room"
fi
EOF
printf '{"model":"opus","statusLine":{"type":"command","command":"bash %s/statusline.sh"},"env":{"A":"1"}}\n' "$C" >"$C/settings.json"
setup "$C" >"$TMP/sA1" 2>&1; assert "설치 rc 0" 0 "$?"
assert "statusLine 명령이 감싸개로" "bash \"$C/hermes-statusline.sh\"" "$(key "$C" command)"
assert "원래 명령은 .orig 에" "bash $C/statusline.sh" "$(cat "$C/hermes-statusline.orig")"
assert "refreshInterval 없으면 4" 4 "$(key "$C" refreshInterval)"
assert "다른 설정 칸 보존(model·env)" "opus 1" "$(python3 -c "import json;d=json.load(open('$C/settings.json'));print(d['model'],d['env']['A'])")"
assert "처음 고칠 때 settings 백업" 1 "$([[ -f "$C/settings.json.bak-hermes" ]] && echo 1 || echo 0)"
assert "손 11줄은 걷어내 원래 스크립트로" 0 "$(diff -q "$TMP/statusline.clean" "$C/statusline.sh" >/dev/null; echo $?)"
assert "감싸개 실행 가능" 1 "$([[ -f "$C/hermes-statusline.sh" ]] && echo 1 || echo 0)"
OUT="$(J "$P" s-1 | bash "$C/hermes-statusline.sh")"
assert "헤르메스 프로젝트: 원래 줄 + 방 줄" "ORIG | proj
지금: 없음 · 이 방에서 불린 명부 에이전트 없음" "$OUT"
assert "헤르메스 없는 폴더: 원래 줄만" "ORIG | tmp" "$(J /tmp s-1 | bash "$C/hermes-statusline.sh")"
cp "$C/settings.json" "$TMP/sA.after1"
setup "$C" >"$TMP/sA2" 2>&1
assert "두 번째 설치는 settings 무변경(멱등)" 0 "$(cmp -s "$TMP/sA.after1" "$C/settings.json"; echo $?)"
assert "두 번째 설치 뒤에도 .orig 는 원래 명령(감싸개로 덮이지 않음)" "bash $C/statusline.sh" "$(cat "$C/hermes-statusline.orig")"

echo ""
echo "== B. 상태줄 없음 =="
C="$TMP/cfgB"; mkdir -p "$C"
setup "$C" >/dev/null 2>&1; assert "settings.json 없던 곳도 rc 0" 0 "$?"
assert "statusLine 새로 = 감싸개" "bash \"$C/hermes-statusline.sh\"" "$(key "$C" command)"
assert "원래 명령 없음(.orig 비어 있음)" "" "$(cat "$C/hermes-statusline.orig" 2>/dev/null)"
assert "방 줄만 찍는다" "지금: 없음 · 이 방에서 불린 명부 에이전트 없음" "$(J "$P" s-1 | bash "$C/hermes-statusline.sh")"
assert "헤르메스 없는 폴더: 아무것도 안 찍는다" "" "$(J /tmp s-1 | bash "$C/hermes-statusline.sh")"

echo ""
echo "== C. 끄기 스위치 =="
C="$TMP/cfgC"; mkdir -p "$C"; printf '{"statusLine":{"type":"command","command":"echo hi"}}\n' >"$C/settings.json"; cp "$C/settings.json" "$TMP/sC"
HERMES_STATUSLINE=0 setup "$C" >"$TMP/sC.out" 2>&1; assert "끄기 rc 0" 0 "$?"
assert "끄면 settings 무변경" 0 "$(cmp -s "$TMP/sC" "$C/settings.json"; echo $?)"
assert "끄면 감싸개도 안 둔다" 0 "$([[ -f "$C/hermes-statusline.sh" ]] && echo 1 || echo 0)"

echo ""
echo "== D. 사용자 값 존중 · 한 줄 명령 =="
C="$TMP/cfgD"; mkdir -p "$C"; printf '{"statusLine":{"type":"command","command":"echo hi","refreshInterval":10}}\n' >"$C/settings.json"
setup "$C" >/dev/null 2>&1
assert "사용자가 정한 refreshInterval 은 그대로" 10 "$(key "$C" refreshInterval)"
assert "파일 아닌 한 줄 명령도 감싼다" "hi
지금: 없음 · 이 방에서 불린 명부 에이전트 없음" "$(J "$P" s-1 | bash "$C/hermes-statusline.sh")"

echo ""
echo "== E. 설치기 연결 — 맨 위 설치가 가짜 HOME 의 전역 설정에 감싸개를 뒀다 =="
assert "HOME/.claude/settings.json statusLine = 감싸개" "bash \"$HOME/.claude/hermes-statusline.sh\"" "$(key "$HOME/.claude" command)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
