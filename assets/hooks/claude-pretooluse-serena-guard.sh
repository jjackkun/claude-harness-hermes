#!/usr/bin/env bash
# PreToolUse hook — Serena 미초기화 시 Edit/Write/MultiEdit 차단 (exit 2).
# matcher: Edit|Write|MultiEdit
#
# serena 프리셋 사용 시 등록됨 (presets/workflow/serena.conf).

_RAW_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
# 워크트리(.claude/worktrees/<branch>) 에서 동작해도 메인 프로젝트 루트 해시로 통일.
_PROJ_DIR=$(echo "$_RAW_DIR" | sed 's|/.claude/worktrees/[^/]*$||')
PROJ_HASH=$(echo "$_PROJ_DIR" | md5sum | cut -c1-8)
FLAG="/tmp/serena-ready-${PROJ_HASH}"

# .hermes/ 경로는 코드가 아닌 마크다운/DB — Serena 체크 불필요
_HOOK_INPUT=$(cat)
_FILE_PATH=$(printf '%s' "$_HOOK_INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); \
   print(d.get('tool_input',{}).get('file_path', \
         d.get('tool_input',{}).get('new_path','')))" 2>/dev/null || true)
if [[ "$_FILE_PATH" == */.hermes/* ]] || [[ "$_FILE_PATH" == .hermes/* ]]; then
  exit 0
fi

if [ ! -f "$FLAG" ]; then
  echo "[BLOCKED] Serena 미초기화 — Edit/Write 차단됨." >&2
  echo "먼저 아래 순서로 Serena를 초기화하세요:" >&2
  echo "  1. ToolSearch(\"select:mcp__plugin_serena_serena__initial_instructions\")" >&2
  echo "  2. mcp__plugin_serena_serena__initial_instructions" >&2
  echo "  3. mcp__plugin_serena_serena__activate_project (현재 디렉터리)" >&2
  echo "  4. mcp__plugin_serena_serena__check_onboarding_performed" >&2
  exit 2
fi
exit 0
