#!/usr/bin/env bash
# 설치 폐포 검증 — "복사 목록 누락" 을 실제 설치 결과로 잡는다.
#
# 2026-09-17 하루에 네 번 같은 누락이 났다: 새 모듈을 만들고 프리셋 복사 목록에 안 넣어
# 소우주에서 import 가 죽거나(hermes_journal_migrate · hermes_handoff_kind · hermes_mesh_gate),
# pre-commit 게이트만 가고 판정기(design_cover.py)가 안 갔다. 설치기 코드를 정규식으로 읽으면
# 다른 경로로 깔리는 파일(gate_emit.sh)을 오탐하므로, **깔아 보고** 결과를 잰다.
#
#   1. 임시 git 프로젝트에 harness+hermes 설치(레지스트리 미등록)
#   2. .git/hooks/pre-commit 이 $(dirname "$0")/X 로 참조하는 X 가 전부 .git/hooks 에 있다
#   3. scripts/*.py 의 로컬 import 가 전부 scripts/ 안에서 해결된다(AST, 조건부 import 포함)
#   4. .claude/settings.json 에 등록된 훅 경로가 전부 존재하고 실행 가능하다
#   5. 자기 검사: 목록에서 모듈 하나를 빼고 다시 재면 3 이 빨개진다
#
# 실행: bash tests/install-closure-test.sh

set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0   # 설치기의 외부 도구 다운로드는 테스트에서 끈다(네트워크 0) — tests/tool-installers-test.sh 가 따로 실측
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/fakehome"; mkdir -p "$HOME"
P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q; git -C "$P" config user.name tester; git -C "$P" config user.email t@t

echo "[1] 설치"
HERMES_NO_REGISTER=1 bash "$REPO_ROOT/project-claude.sh" "$P" harness hermes > "$T/install.log" 2>&1
assert "설치 종료 코드 0" "0" "$?"
assert "실 레지스트리 오염 없음" "0" "$(grep -c "$T" "$REPO_ROOT/.installed-projects" 2>/dev/null || true)"

echo "[2] pre-commit 이 참조하는 판정기가 .git/hooks 에 있다"
PC="$P/.git/hooks/pre-commit"
REFS="$(grep -oE '\$\(dirname "\$0"\)/[A-Za-z0-9_.-]+' "$PC" | sed 's|.*/||' | sort -u)"
MISSING_REFS=""; for r in $REFS; do [[ -f "$P/.git/hooks/$r" ]] || MISSING_REFS="$MISSING_REFS $r"; done
assert "참조 파일 수 ≥ 5(검사가 실제로 뭔가를 봤다)" "1" "$(( $(echo "$REFS" | grep -c .) >= 5 ))"
assert "참조하지만 없는 판정기 0건" "" "$MISSING_REFS"
[[ -n "$MISSING_REFS" ]] && echo "      → lib/harness_installers.sh 의 _install_git_hook 목록에 추가: $MISSING_REFS"

echo "[3] scripts/*.py 의 로컬 import 가 전부 해결된다"
closure() { # closure <scripts_dir> → 해결 안 되는 "파일: 모듈" 을 한 줄씩
python3 - "$1" <<'PY'
import ast, glob, os, sys
d = sys.argv[1]
files = sorted(glob.glob(os.path.join(d, "*.py")))
local = {os.path.basename(f)[:-3] for f in files}
# 공장 scripts/ 에 있는 이름만 "로컬" 로 본다 — 표준 라이브러리·외부 패키지는 대상이 아니다
factory_local = {os.path.basename(f)[:-3] for f in glob.glob(os.path.join(os.environ["FACTORY"], "scripts", "*.py"))}
for f in files:
    try:
        tree = ast.parse(open(f, encoding="utf-8").read())
    except SyntaxError as exc:
        print(f"{os.path.basename(f)}: SyntaxError {exc}"); continue
    for n in ast.walk(tree):
        mods = []
        if isinstance(n, ast.Import):
            mods = [a.name.split(".")[0] for a in n.names]
        elif isinstance(n, ast.ImportFrom) and n.module and n.level == 0:
            mods = [n.module.split(".")[0]]
        for m in mods:
            if m in factory_local and m not in local:
                print(f"{os.path.basename(f)}: {m}")
PY
}
UNRESOLVED="$(FACTORY="$REPO_ROOT" closure "$P/scripts")"
assert "설치된 스크립트 수 ≥ 60" "1" "$(( $(ls "$P"/scripts/*.py | wc -l) >= 60 ))"
assert "해결 안 되는 로컬 import 0건" "" "$UNRESOLVED"
[[ -n "$UNRESOLVED" ]] && printf '%s\n' "$UNRESOLVED" | sed 's/^/      → presets\/workflow\/hermes.conf 복사 목록에 추가: /'

echo "[4] settings.json 의 훅 경로가 전부 존재·실행 가능"
HOOK_PATHS="$(python3 -c "
import json,sys,re
s=json.load(open(sys.argv[1]))
out=set()
def walk(x):
    if isinstance(x,dict):
        for k,v in x.items():
            if k=='command' and isinstance(v,str):
                for m in re.findall(r'\\\$\{CLAUDE_PROJECT_DIR\}/(scripts/hooks/[A-Za-z0-9_.-]+)', v): out.add(m)
            walk(v)
    elif isinstance(x,list):
        for i in x: walk(i)
walk(s); print('\n'.join(sorted(out)))" "$P/.claude/settings.json")"
BAD_HOOKS=""; for h in $HOOK_PATHS; do [[ -x "$P/$h" ]] || BAD_HOOKS="$BAD_HOOKS $h"; done
assert "등록 훅 수 ≥ 10" "1" "$(( $(echo "$HOOK_PATHS" | grep -c .) >= 10 ))"
assert "등록됐지만 없거나 실행 불가한 훅 0건" "" "$BAD_HOOKS"

echo "[5] 자기 검사 — 모듈 하나를 빼면 [3] 이 빨개진다"
mv "$P/scripts/hermes_journal_migrate.py" "$T/hidden.py"
assert "hermes_journal_migrate 제거 → 미해결 import 검출" "1" "$(FACTORY="$REPO_ROOT" closure "$P/scripts" | grep -c 'hermes_journal_migrate$')"
mv "$T/hidden.py" "$P/scripts/hermes_journal_migrate.py"

echo
echo "install-closure: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
