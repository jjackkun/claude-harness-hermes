#!/usr/bin/env bash
# 프로젝트 몫 외부 에셋 장부 — 계획 docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G3
#
#   - hermes 프리셋 설치는 .claude/.upstream.json 에 **깐 항목만** 쓴다
#   - 프리셋을 바꿔 재설치하면 장부도 바뀐다
#   - 깐 외부 에셋이 없으면(hermes 없음) 파일이 없다
#   - 장부는 git 에 무시되지 않고(공장 없는 clone 이 읽는다) 설치 영수증에 오른다
#   - 언인스톨이 지운다
#
# 격리: 저장소를 임시 사본에 복사하고 HOME 을 바꿔 실행한다(preset-lock-tracked-test 와 같은 방식).
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0 HERMES_NO_REGISTER=1
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); export HOME="$TMP/fakehome"; mkdir -p "$HOME"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

SANDBOX="$TMP/harness"; mkdir -p "$SANDBOX"
tar -c --exclude=.git -C "$REPO_ROOT" . | tar -x -C "$SANDBOX"
rm -f "$SANDBOX/.installed-projects" "$SANDBOX/.installed-projects.codex"

P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q; git -C "$P" config user.name t; git -C "$P" config user.email t@t
L="$P/.claude/.upstream.json"
install() { bash "$SANDBOX/project-claude.sh" "$P" "$@" >"$TMP/install.log" 2>&1; }
names() { python3 -c "import json,sys; print(' '.join(sorted(i['kind']+'/'+i['name'] for i in json.load(open(sys.argv[1]))['items'])))" "$L"; }
has() { [[ " $(names) " == *" $1 "* ]] && echo 1 || echo 0; }

echo "== hermes + mcp: 깐 외부 에셋만 장부에 =="
install harness hermes mcp skill-dev
assert "설치 rc 0" 0 "$?"
assert "장부 파일이 생겼다" 1 "$([[ -f "$L" ]] && echo 1 || echo 0)"
assert "mcp-builder(깔림)가 장부에 있다" 1 "$(has skills/mcp-builder)"
assert "skill-creator(깔림)가 장부에 있다" 1 "$(has skills/skill-creator)"
assert "impeccable(안 깔림)은 장부에 없다" 0 "$(has skills/impeccable)"
installed_bad=$(python3 - "$L" "$P/.claude" <<'PY'
import json, os, sys
items = json.load(open(sys.argv[1]))['items']
bad = [i['name'] for i in items
       if not os.path.exists(os.path.join(sys.argv[2], i['kind'], i['name'] + ('.md' if i['kind'] == 'agents' else '')))]
print(len(bad))
PY
)
assert "장부의 항목은 모두 실제로 깔린 것" 0 "$installed_bad"
assert "공장 커밋을 적는다" 1 "$(python3 -c "import json,sys; print(1 if json.load(open(sys.argv[1])).get('factory_commit') else 0)" "$L")"
assert "확인 프로그램이 프로젝트에 복사됐다(G4)" 1 "$([[ -f "$P/scripts/upstream-check.py" ]] && echo 1 || echo 0)"
assert "시작 훅 파일이 깔렸다(G5)" 1 "$([[ -x "$P/scripts/hooks/claude-sessionstart-upstream.sh" ]] && echo 1 || echo 0)"
assert "settings.json SessionStart 에 훅이 등록됐다(G5)" 1 "$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
cmds=[h.get('command','') for g in d.get('hooks',{}).get('SessionStart',[]) for h in g.get('hooks',[])]
print(1 if any('claude-sessionstart-upstream.sh' in c for c in cmds) else 0)" "$P/.claude/settings.json")"

echo "== 프리셋을 빼면 장부도 바뀐다 =="
install harness hermes
assert "재설치 rc 0" 0 "$?"
assert "mcp-builder 가 장부에서 빠졌다" 0 "$(has skills/mcp-builder)"

echo "== git·영수증 =="
judge() { python3 "$REPO_ROOT/scripts/git_ignore_judge.py" --repo "$P" "$1" >/dev/null 2>&1; echo $?; }
assert "장부가 git 에 무시되지 않는다(1=무시 아님)" 1 "$(judge .claude/.upstream.json)"
assert "설치 영수증에 장부가 있다" 1 "$(grep -c '^\.claude/\.upstream\.json$' "$P/.claude/.last-install.txt")"

echo "== hermes 가 없으면 장부가 없다 =="
P2="$TMP/proj2"; mkdir -p "$P2"; git -C "$P2" init -q
bash "$SANDBOX/project-claude.sh" "$P2" harness mcp >"$TMP/install2.log" 2>&1
assert "hermes 없는 설치 rc 0" 0 "$?"
assert "장부 파일 없음" 0 "$([[ -f "$P2/.claude/.upstream.json" ]] && echo 1 || echo 0)"

echo "== 언인스톨이 지운다 =="
printf 'y\nn\n' | bash "$SANDBOX/uninstall.sh" "$P" >"$TMP/uninstall.log" 2>&1
assert "언인스톨 뒤 장부 없음" 0 "$([[ -f "$L" ]] && echo 1 || echo 0)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
