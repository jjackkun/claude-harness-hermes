#!/usr/bin/env bash
# Windows 경로 감지 헬퍼 단위 테스트
# 실행: bash tests/windows-helpers-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# lib/common.sh 에서 ASSETS_DIR 를 사용하는 함수들이 있으므로 미리 설정
export DEV_SETTING_DIR="$REPO_ROOT"
export ASSETS_DIR="$REPO_ROOT/assets"
export TEMPLATES_DIR="$REPO_ROOT/templates"
source "$REPO_ROOT/lib/common.sh"

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected='$expected' actual='$actual')"; FAIL=$((FAIL+1))
  fi
}

echo "== is_windows_path =="
assert "Windows C 드라이브"  "1" "$(is_windows_path /mnt/c/Users/foo && echo 1 || echo 0)"
assert "Windows D 드라이브"  "1" "$(is_windows_path /mnt/d/Projects  && echo 1 || echo 0)"
assert "Linux 홈"            "0" "$(is_windows_path /home/user   && echo 1 || echo 0)"
assert "빈 문자열"            "0" "$(is_windows_path ''               && echo 1 || echo 0)"
assert "/mnt/ 만"            "0" "$(is_windows_path /mnt/            && echo 1 || echo 0)"

echo ""
echo "== is_wsl =="
if [[ "$(uname -r 2>/dev/null)" == *microsoft* ]]; then
  assert "WSL 환경 탐지" "1" "$(is_wsl && echo 1 || echo 0)"
else
  assert "non-WSL 환경 탐지" "0" "$(is_wsl && echo 1 || echo 0)"
fi

echo ""
echo "== detect_claude_config_dir (Windows ~/.claude) =="
# Windows Claude Code Desktop 은 AppData/Roaming 이 아닌 ~/.claude 를 사용.
# WSL2 마운트 경로 /mnt/c/Users/<user> 에 .claude 디렉터리가 있어야 탐지됨.
if is_wsl && [[ -d /mnt/c/Users ]]; then
  WIN_USER=$(ls /mnt/c/Users | grep -Ev '^(All Users|Default|Default User|Public|desktop\.ini)$' | head -1)
  WIN_HOME="/mnt/c/Users/${WIN_USER}"
  WIN_CLAUDE="${WIN_HOME}/.claude"
  if [[ -d "$WIN_CLAUDE" ]]; then
    RESULT=$(detect_claude_config_dir "$WIN_HOME")
    assert "Windows ~/.claude 탐지" "$WIN_CLAUDE" "$RESULT"
  else
    echo "  - /mnt/c/Users/${WIN_USER}/.claude 없음 — SKIP"
    PASS=$((PASS+1))
  fi
else
  echo "  - WSL2 마운트 없음 — SKIP"
  PASS=$((PASS+1))
fi

echo ""
echo "== install_skills Windows path (cp, not symlink) =="
# /mnt/c/ 로 시작하는 실제 Windows 마운트 경로 사용
TMP_WIN="/mnt/c/tmp/ai-dev-test-$$"
mkdir -p "$TMP_WIN/.claude/skills"

_ORIG_ASSETS="$ASSETS_DIR"
_TMP_ASSETS="$(mktemp -d)"
export ASSETS_DIR="$_TMP_ASSETS"
mkdir -p "$ASSETS_DIR/skills/test-skill"
touch "$ASSETS_DIR/skills/test-skill/SKILL.md"

SKILLS=(test-skill)
install_skills "$TMP_WIN/.claude"

if [[ -d "$TMP_WIN/.claude/skills/test-skill" && ! -L "$TMP_WIN/.claude/skills/test-skill" ]]; then
  assert "Windows: cp 사용 (symlink 없음)" "1" "1"
else
  assert "Windows: cp 사용 (symlink 없음)" "cp" "symlink"
fi
export ASSETS_DIR="$_ORIG_ASSETS"
rm -rf "$TMP_WIN" "$_TMP_ASSETS"

echo ""
echo "== install_agents Windows path (cp, not symlink) =="
TMP_WIN2="/mnt/c/tmp/ai-dev-test2-$$"
mkdir -p "$TMP_WIN2/.claude/agents"

_TMP_ASSETS2="$(mktemp -d)"
export ASSETS_DIR="$_TMP_ASSETS2"
mkdir -p "$ASSETS_DIR/agents"
echo "# test" > "$ASSETS_DIR/agents/test-agent.md"

AGENTS=(test-agent)
install_agents "$TMP_WIN2/.claude"

if [[ -f "$TMP_WIN2/.claude/agents/test-agent.md" && ! -L "$TMP_WIN2/.claude/agents/test-agent.md" ]]; then
  assert "Windows: agent cp 사용 (symlink 없음)" "1" "1"
else
  assert "Windows: agent cp 사용 (symlink 없음)" "cp" "symlink"
fi
export ASSETS_DIR="$_ORIG_ASSETS"
rm -rf "$TMP_WIN2" "$_TMP_ASSETS2"

echo ""
echo "== wrap_hooks_for_windows =="
POST_EDIT_HOOKS=('${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-posttooluse-size-warn.sh')
USER_PROMPT_SUBMIT_HOOKS=('${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-userpromptsubmit-reminders.sh')
PRE_TOOL_USE_HOOKS=('Bash::${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-pretooluse-bash-guard.sh')
STOP_HOOKS=('${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-stop-perm-prompt-fatigue.sh')

wrap_hooks_for_windows "/mnt/c/Users/jjack/Projects/foo"

assert "PostEdit hook 래핑" \
  'wsl bash "/mnt/c/Users/jjack/Projects/foo/scripts/hooks/claude-posttooluse-size-warn.sh"' \
  "${POST_EDIT_HOOKS[0]}"
assert "UserPromptSubmit hook 래핑" \
  'wsl bash "/mnt/c/Users/jjack/Projects/foo/scripts/hooks/claude-userpromptsubmit-reminders.sh"' \
  "${USER_PROMPT_SUBMIT_HOOKS[0]}"
assert "PreToolUse matcher 보존" \
  'Bash::wsl bash "/mnt/c/Users/jjack/Projects/foo/scripts/hooks/claude-pretooluse-bash-guard.sh"' \
  "${PRE_TOOL_USE_HOOKS[0]}"
assert "Stop hook 래핑" \
  'wsl bash "/mnt/c/Users/jjack/Projects/foo/scripts/hooks/claude-stop-perm-prompt-fatigue.sh"' \
  "${STOP_HOOKS[0]}"

# Linux 경로에서는 no-op 확인
POST_EDIT_HOOKS=('${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-posttooluse-size-warn.sh')
wrap_hooks_for_windows "/home/user/PROJECT/foo"
assert "Linux 경로: no-op" \
  '${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-posttooluse-size-warn.sh' \
  "${POST_EDIT_HOOKS[0]}"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
