#!/usr/bin/env bash
# shift+enter 개행 설치(lib/newline_key*) 시험 — 실물 설정은 건드리지 않고 임시 폴더에서만 돈다.
# 실행: bash tests/newline-key-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEV_SETTING_DIR="$REPO_ROOT"
export ASSETS_DIR="$REPO_ROOT/assets"
export TEMPLATES_DIR="$REPO_ROOT/templates"
source "$REPO_ROOT/lib/common.sh"

CLAUDE_PY="$REPO_ROOT/lib/newline_key_claude.py"
WT_PY="$REPO_ROOT/lib/newline_key_wt.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected='$expected' actual='$actual')"; FAIL=$((FAIL+1))
  fi
}
# jq_py <file> <파이썬 식 (d = 읽은 JSON)>
jq_py() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); print(eval(sys.argv[2]))' "$1" "$2" 2>&1; }
sum_of() { sha256sum "$1" | cut -d' ' -f1; }
backups() { find "$(dirname "$1")" -name "$(basename "$1").bak-newline-key-*" | wc -l | tr -d ' '; }
CHAT='[b["bindings"] for b in d["bindings"] if b["context"]=="Chat"][0]'

echo "== keybindings.json =="
C="$TMP/c1"; mkdir -p "$C"
assert "없으면 만든다" "created" "$(python3 "$CLAUDE_PY" "$C" | cut -d: -f1)"
assert "shift+enter 가 개행이다" "chat:newline" "$(jq_py "$C/keybindings.json" "$CHAT['shift+enter']")"
assert "\$schema 를 넣는다" "True" "$(jq_py "$C/keybindings.json" "'\$schema' in d")"
before="$(sum_of "$C/keybindings.json")"
assert "다시 돌리면 그대로 둔다" "kept" "$(python3 "$CLAUDE_PY" "$C" | cut -d: -f1)"
assert "다시 돌려도 파일이 같다" "$before" "$(sum_of "$C/keybindings.json")"

C="$TMP/c2"; mkdir -p "$C"
echo '{"bindings":[{"context":"Global","bindings":{"ctrl+k ctrl+t":"app:toggleTodos"}},{"context":"Chat","bindings":{"ctrl+e":"chat:externalEditor"}}]}' > "$C/keybindings.json"
assert "있는 파일에는 더한다" "added" "$(python3 "$CLAUDE_PY" "$C" | cut -d: -f1)"
assert "기존 Chat 키가 남는다" "chat:externalEditor" "$(jq_py "$C/keybindings.json" "$CHAT['ctrl+e']")"
assert "기존 Global 블록이 남는다" "2" "$(jq_py "$C/keybindings.json" "len(d['bindings'])")"
assert "더한 값이 개행이다" "chat:newline" "$(jq_py "$C/keybindings.json" "$CHAT['shift+enter']")"

C="$TMP/c3"; mkdir -p "$C"
echo '{"bindings":[{"context":"Chat","bindings":{"Shift+Enter":null}}]}' > "$C/keybindings.json"
before="$(sum_of "$C/keybindings.json")"
assert "사용자가 정한 shift+enter 는 안 건드린다" "kept" "$(python3 "$CLAUDE_PY" "$C" | cut -d: -f1)"
assert "그 파일이 그대로다" "$before" "$(sum_of "$C/keybindings.json")"

C="$TMP/c4"; mkdir -p "$C"; echo '{ 깨진 json' > "$C/keybindings.json"
before="$(sum_of "$C/keybindings.json")"
assert "못 읽는 파일은 건너뛴다" "skipped" "$(python3 "$CLAUDE_PY" "$C" | cut -d: -f1)"
assert "못 읽는 파일을 덮지 않는다" "$before" "$(sum_of "$C/keybindings.json")"

echo ""
echo "== Windows Terminal settings.json =="
W="$TMP/w1/settings.json"; mkdir -p "$(dirname "$W")"
echo '{"actions":[{"command":"find","id":"User.find"}],"keybindings":[{"id":"User.find","keys":"ctrl+shift+f"}],"profiles":{"defaults":{}}}' > "$W"
orig="$(sum_of "$W")"
assert "dry-run 은 알리기만 한다" "would-add" "$(python3 "$WT_PY" --dry-run "$W" | cut -d: -f1)"
assert "dry-run 은 파일을 안 바꾼다" "$orig" "$(sum_of "$W")"
assert "dry-run 은 백업도 안 만든다" "0" "$(backups "$W")"
assert "새 형식에 더한다" "added" "$(python3 "$WT_PY" "$W" | cut -d: -f1)"
assert "키 연결의 id 가 액션에 있다" "True" "$(jq_py "$W" "[k['id'] for k in d['keybindings'] if k['keys']=='shift+enter'][0] in [a['id'] for a in d['actions']]")"
assert "보내는 바이트가 ESC CR 이다" "1b0d" "$(jq_py "$W" "[a for a in d['actions'] if isinstance(a['command'],dict)][0]['command']['input'].encode().hex()")"
assert "기존 키 연결이 남는다" "ctrl+shift+f" "$(jq_py "$W" "d['keybindings'][0]['keys']")"
assert "다른 설정이 남는다" "True" "$(jq_py "$W" "'profiles' in d")"
assert "백업이 하나 생긴다" "1" "$(backups "$W")"
assert "백업은 고치기 전 그대로다" "$orig" "$(sum_of "$(find "$(dirname "$W")" -name '*.bak-newline-key-*')")"
before="$(sum_of "$W")"
assert "다시 돌리면 그대로 둔다" "kept" "$(python3 "$WT_PY" "$W" | cut -d: -f1)"
assert "다시 돌려도 파일이 같다" "$before" "$(sum_of "$W")"
assert "다시 돌려도 백업이 안 는다" "1" "$(backups "$W")"

W="$TMP/w2/settings.json"; mkdir -p "$(dirname "$W")"
echo '{"actions":[{"command":"paste","keys":"ctrl+v"}]}' > "$W"
assert "옛 형식에 더한다" "added" "$(python3 "$WT_PY" "$W" | cut -d: -f1)"
assert "옛 형식은 액션에 keys 를 적는다" "1b0d" "$(jq_py "$W" "[a for a in d['actions'] if a.get('keys')=='shift+enter'][0]['command']['input'].encode().hex()")"
assert "옛 형식에 keybindings 를 만들지 않는다" "False" "$(jq_py "$W" "'keybindings' in d")"

W="$TMP/w3/settings.json"; mkdir -p "$(dirname "$W")"
echo '{"actions":[{"command":"paste","keys":["Shift+Enter"]}]}' > "$W"
before="$(sum_of "$W")"
assert "사용자가 정한 shift+enter 는 안 건드린다" "kept" "$(python3 "$WT_PY" "$W" | cut -d: -f1)"
assert "그 파일이 그대로다" "$before" "$(sum_of "$W")"
assert "안 건드리면 백업도 없다" "0" "$(backups "$W")"

W="$TMP/w4/settings.json"; mkdir -p "$(dirname "$W")"
printf '{\n  // 주석이 있는 설정\n  "actions": []\n}\n' > "$W"
before="$(sum_of "$W")"
assert "주석 있는 파일은 건너뛴다" "skipped" "$(python3 "$WT_PY" "$W" | cut -d: -f1)"
assert "주석 있는 파일을 덮지 않는다" "$before" "$(sum_of "$W")"

echo ""
echo "== 설치 함수 =="
U="$TMP/Users"; PK="$U/kim/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
UN="$U/kim/AppData/Local/Microsoft/Windows Terminal"; mkdir -p "$PK" "$UN" "$TMP/c5"
echo '{"actions":[],"keybindings":[]}' > "$PK/settings.json"; echo '{"actions":[]}' > "$UN/settings.json"
assert "설치판·비설치판 설정을 둘 다 찾는다" "2" "$(DS_WINDOWS_USERS_DIR="$U" find_windows_terminal_settings | wc -l | tr -d ' ')"
assert "Windows 가 없으면 아무것도 안 찾는다" "0" "$(DS_WINDOWS_USERS_DIR="$TMP/없는곳" find_windows_terminal_settings | wc -l | tr -d ' ')"
DS_WINDOWS_USERS_DIR="$U" install_newline_key "$TMP/c5" >/dev/null 2>&1
assert "설치 함수가 keybindings.json 을 만든다" "chat:newline" "$(jq_py "$TMP/c5/keybindings.json" "$CHAT['shift+enter']")"
assert "설치 함수가 설치판을 고친다" "1" "$(jq_py "$PK/settings.json" "len(d['keybindings'])")"
assert "설치 함수가 공백 든 경로도 고친다" "1" "$(jq_py "$UN/settings.json" "len(d['actions'])")"
assert "public-claude.sh 가 설치 함수를 부른다" "1" "$(grep -c '^install_newline_key "\$CLAUDE_DIR"' "$REPO_ROOT/public-claude.sh")"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
