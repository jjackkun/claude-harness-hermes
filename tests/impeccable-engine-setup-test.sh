#!/usr/bin/env bash
# impeccable 엔진을 프로젝트 안에, 원격 통계는 끈 채로 — 계획 docs/exec-plans/active/2026-11-15-impeccable-4-upgrade.md G6
#
#   - svelte 프리셋 설치는 settings.json env 에 IMPECCABLE_HOME=.impeccable 을 넣는다
#   - .impeccable/config.json 에 "telemetry": false (다른 칸은 지킨다)
#   - .impeccable/bin/ 은 git 에 무시되고, config.json 은 무시되지 않는다
#   - 런처가 그 설정으로 엔진을 받으려 하면 프로젝트 안 .impeccable/bin/ 을 쓰고 ~/.impeccable 은 건드리지 않는다
#     (가짜 주소로 받기를 실패시켜 위치만 본다 — 엔진은 실행하지 않는다)
#   - impeccable 을 안 까는 설치는 아무것도 쓰지 않는다
#
# 격리: 저장소 임시 사본 + HOME 변경.
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0 HERMES_NO_REGISTER=1
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); export HOME="$TMP/fakehome"; mkdir -p "$HOME"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

SANDBOX="$TMP/harness"; mkdir -p "$SANDBOX"
tar -c --exclude=.git -C "$REPO_ROOT" . | tar -x -C "$SANDBOX"
rm -f "$SANDBOX/.installed-projects" "$SANDBOX/.installed-projects.codex"
judge() { python3 "$REPO_ROOT/scripts/git_ignore_judge.py" --repo "$1" "$2" >/dev/null 2>&1; echo $?; }

P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q
mkdir -p "$P/.impeccable"; echo '{"telemetry": true, "keep": "me"}' > "$P/.impeccable/config.json"
bash "$SANDBOX/project-claude.sh" "$P" harness svelte >"$TMP/install.log" 2>&1
assert "설치 rc 0" 0 "$?"

echo "== 엔진 위치 설정 =="
assert "settings.json env IMPECCABLE_HOME=.impeccable" ".impeccable" \
  "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('env',{}).get('IMPECCABLE_HOME',''))" "$P/.claude/settings.json")"

echo "== 원격 통계 끄기 =="
assert "telemetry false" "False" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['telemetry'])" "$P/.impeccable/config.json")"
assert "다른 칸은 지킨다" "me" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('keep'))" "$P/.impeccable/config.json")"

echo "== git =="
mkdir -p "$P/.impeccable/bin/0.1.24"; touch "$P/.impeccable/bin/0.1.24/impeccable"
assert "엔진 폴더는 무시된다(0=무시)" 0 "$(judge "$P" .impeccable/bin/0.1.24/impeccable)"
assert "config.json 은 무시되지 않는다(1=무시 아님)" 1 "$(judge "$P" .impeccable/config.json)"
rm -rf "$P/.impeccable/bin"

echo "== 런처는 프로젝트 안에 받으려 한다 =="
(cd "$P" && IMPECCABLE_HOME=.impeccable IMPECCABLE_DOWNLOAD_BASE="http://127.0.0.1:9/none" \
  timeout 60 sh .claude/skills/impeccable/scripts/impeccable --version >"$TMP/launch.log" 2>&1)
assert "프로젝트 .impeccable/bin/<버전>/ 이 생겼다" 1 "$([[ -d "$P/.impeccable/bin/$(cat "$P/.claude/skills/impeccable/scripts/VERSION")" ]] && echo 1 || echo 0)"
assert "~/.impeccable 은 없다" 0 "$([[ -e "$HOME/.impeccable" ]] && echo 1 || echo 0)"

echo "== impeccable 을 안 까는 설치 =="
P2="$TMP/proj2"; mkdir -p "$P2"; git -C "$P2" init -q
bash "$SANDBOX/project-claude.sh" "$P2" harness >"$TMP/install2.log" 2>&1
assert "rc 0" 0 "$?"
assert ".impeccable 없음" 0 "$([[ -e "$P2/.impeccable" ]] && echo 1 || echo 0)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
