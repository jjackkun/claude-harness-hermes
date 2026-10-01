#!/usr/bin/env bash
# 헤르메스 프리셋의 허용 목록 — 읽기 전용 명령 recall 하나만 미리 허용한다
# (계획 docs/exec-plans/completed/2026-10-01-recall-permission.md 목표 1 · 2).
#
# 실제 세션 실측에서 auto mode 가 아닌 사용자는 에이전트가 기억을 찾을 때마다 승인 질문을 받는다는 것이 드러났다.
# recall 은 읽기 전용(mode=ro)이라 허용해도 안전하다. 다른 hermes-agent.py 하위 명령(teach · note · pin · retire …)은
# 쓰기라 승인 질문이 안전장치다 — 열지 않는다.
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; export HOME="$TMP/home"; mkdir -p "$HOME"
REGISTRY="$REPO_ROOT/.installed-projects"
cleanup() {
  if [[ -f "$REGISTRY" ]]; then
    grep -vxF -e "$TMP/h" -e "$TMP/n" "$REGISTRY" > "$REGISTRY.tmp$$" || true
    mv "$REGISTRY.tmp$$" "$REGISTRY"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
RULE='Bash(python3 scripts/hermes-agent.py recall:*)'

install() { # install <경로> <프리셋…>
  local p="$1"; shift; mkdir -p "$p"; git -C "$p" init -q
  bash "$REPO_ROOT/project-claude.sh" "$p" "$@" >"$TMP/install.log" 2>&1
}
allow_of() { python3 -c "
import json,sys; d=json.load(open(sys.argv[1]))
print('\n'.join(d.get('permissions',{}).get('allow',[])))" "$1/.claude/settings.json" 2>/dev/null; }

echo "== 1. 권한 파일 (목표 2)"
HJSON="$REPO_ROOT/assets/permissions/hermes.json"
assert "assets/permissions/hermes.json 이 있다" 1 "$([[ -f "$HJSON" ]] && echo 1 || echo 0)"
assert "  allow 는 정확히 recall 한 줄" "$RULE" "$(python3 -c "
import json,sys; print('|'.join(json.load(open(sys.argv[1]))['permissions']['allow']))" "$HJSON" 2>/dev/null)"

echo "== 2. 설치 (목표 1)"
install "$TMP/h" harness hermes
assert "harness hermes 설치 → 허용 목록에 recall 규칙 1개" 1 "$(allow_of "$TMP/h" | grep -cxF "$RULE")"
assert "  그 밖의 hermes-agent.py 규칙은 없다(teach·retire 등을 열지 않는다)" 0 "$(allow_of "$TMP/h" | grep -F 'hermes-agent.py' | grep -vxF "$RULE" | wc -l)"
assert "  python3 전체·scripts 전체를 여는 규칙도 이 프리셋이 더하지 않는다" 0 "$(allow_of "$TMP/h" | grep -cE '^Bash\(python3?:\*\)$|^Bash\(python3 scripts/\*')"
install "$TMP/n" harness
assert "harness 만 설치 → recall 규칙 없음(헤르메스가 없는 프로젝트에는 안 간다)" 0 "$(allow_of "$TMP/n" | grep -cxF "$RULE")"
assert "  하지만 기존 허용(ls)은 그대로" 1 "$(allow_of "$TMP/n" | grep -cxF 'Bash(ls:*)')"

echo; echo "통과 $PASS · 실패 $FAIL"
[[ "$FAIL" -eq 0 ]]
