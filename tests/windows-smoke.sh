#!/usr/bin/env bash
# Windows 타깃 통합 스모크 테스트.
# /mnt/c/tmp/ 하위에 프로젝트를 생성하여 실제 Windows 경로 대상으로 설치를 검증.
# 실행: bash tests/windows-smoke.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

FAKEHOME_TMP=$(mktemp -d)
export HOME="$FAKEHOME_TMP/fakehome"  # 실 ~/.claude/projects 절대 격리 (install_memory_symlink)
mkdir -p "$HOME"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected='$expected' actual='$actual')"; FAIL=$((FAIL+1))
  fi
}

# WSL2 + /mnt/c 마운트 필요
if [[ "$(uname -r 2>/dev/null)" != *microsoft* ]] || [[ ! -d /mnt/c ]]; then
  echo "SKIP: WSL2 + /mnt/c 마운트 필요"
  exit 0
fi

WIN_PROJECT="/mnt/c/tmp/ai-dev-windows-smoke-$$"
LINUX_PROJECT=""
mkdir -p "$WIN_PROJECT"

# 테스트 설치가 .installed-projects 레지스트리를 오염시키지 않도록 끝에서 원복
REGISTRY="$REPO_ROOT/.installed-projects"
cleanup() {
  if [[ -f "$REGISTRY" ]]; then
    grep -vxF "$WIN_PROJECT" "$REGISTRY" \
      | { [[ -n "$LINUX_PROJECT" ]] && grep -vxF "$LINUX_PROJECT" || cat; } \
      > "$REGISTRY.tmp$$" || true
    mv "$REGISTRY.tmp$$" "$REGISTRY"
  fi
  rm -rf "$WIN_PROJECT" ${LINUX_PROJECT:+"$LINUX_PROJECT"} "$FAKEHOME_TMP"
}
trap cleanup EXIT
git -C "$WIN_PROJECT" init -q

echo "== Windows 타깃 project-claude.sh harness 실행 =="
bash "$REPO_ROOT/project-claude.sh" "$WIN_PROJECT" harness 2>&1 | grep -E "^\[|^$" | head -20
echo ""

# hooks 는 settings 분리 구조에서 .claude/settings.json (committed) 으로 이동했다.
SETTINGS="$WIN_PROJECT/.claude/settings.json"
CLAUDE_DIR="$WIN_PROJECT/.claude"

echo "== 1. symlink 없음 (cp 사용) =="
for subdir in skills agents rules; do
  target="$CLAUDE_DIR/$subdir"
  [[ -d "$target" ]] || continue
  for entry in "$target"/*; do
    [[ -e "$entry" ]] || continue
    if [[ -L "$entry" ]]; then
      assert "symlink 없음: $subdir/$(basename "$entry")" "cp" "symlink"
    else
      assert "cp 사용: $subdir/$(basename "$entry")" "1" "1"
    fi
  done
done

echo ""
echo "== 2. hook 명령에 wsl bash 포함 =="
if [[ -f "$SETTINGS" ]]; then
  WSL_COUNT=$(grep -c '"wsl bash' "$SETTINGS" || true)
  assert "wsl bash hook 1개 이상" "1" "$([[ ${WSL_COUNT:-0} -ge 1 ]] && echo 1 || echo 0)"

  DOLLAR_COUNT=$(grep -c 'CLAUDE_PROJECT_DIR' "$SETTINGS" || true)
  assert "CLAUDE_PROJECT_DIR 미치환 없음" "0" "${DOLLAR_COUNT:-0}"
else
  assert "settings.json 존재" "1" "0"
fi

echo ""
echo "== 3. hook 스크립트 복사 확인 =="
HOOKS_DIR="$WIN_PROJECT/scripts/hooks"
if [[ -d "$HOOKS_DIR" ]]; then
  HOOK_COUNT=$(find "$HOOKS_DIR" -name "*.sh" | wc -l)
  assert "hook 스크립트 1개 이상 복사" "1" "$([[ $HOOK_COUNT -ge 1 ]] && echo 1 || echo 0)"
else
  assert "scripts/hooks 디렉터리 존재" "1" "0"
fi

echo ""
echo "== 4. CLAUDE.md 생성 확인 =="
assert "CLAUDE.md 존재" "1" "$([[ -f "$WIN_PROJECT/CLAUDE.md" ]] && echo 1 || echo 0)"

echo ""
echo "== 5. Ubuntu 타깃 symlink 정상 확인 (회귀 없음) =="
LINUX_PROJECT="$(mktemp -d)"   # cleanup trap 이 레지스트리 원복 + 삭제를 담당
git -C "$LINUX_PROJECT" init -q
bash "$REPO_ROOT/project-claude.sh" "$LINUX_PROJECT" harness >/dev/null 2>&1

for subdir in skills agents rules; do
  target="$LINUX_PROJECT/.claude/$subdir"
  [[ -d "$target" ]] || continue
  for entry in "$target"/*; do
    [[ -e "$entry" ]] || continue
    if [[ -L "$entry" ]]; then
      assert "Ubuntu symlink 유지: $subdir/$(basename "$entry")" "1" "1"
      break  # 하나만 확인
    fi
  done
done

rm -rf "$LINUX_PROJECT"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
