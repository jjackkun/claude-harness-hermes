#!/usr/bin/env bash
# SessionStart hook — Claude Code 세션 시작 시 1회 Serena 초기화 지시 주입.
#
# serena 프리셋 사용 시 등록됨 (presets/workflow/serena.conf).
# UserPromptSubmit 훅과 달리 세션당 단 1회만 실행된다.

# serena-ready flag 삭제 — 세션/compact 후 재초기화 강제
# 워크트리에서도 메인 루트 해시로 통일.
_RAW_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
_PROJ_DIR=$(echo "$_RAW_DIR" | sed 's|/.claude/worktrees/[^/]*$||')
PROJ_HASH=$(echo "$_PROJ_DIR" | md5sum | cut -c1-8)
rm -f "/tmp/serena-ready-${PROJ_HASH}"

cat <<EOF

--- [Serena 초기화 필요] ---
이 프로젝트는 Serena MCP 가 등록되어 있습니다.
세션 시작 또는 /compact 후 재개 시, 코드 작업 전에 반드시 아래 순서로 초기화하세요.
요약본을 받았더라도 초기화를 먼저 완료한 뒤 작업을 이어가세요:
  1. ToolSearch("select:mcp__plugin_serena_serena__initial_instructions") — 스키마 로드
  2. mcp__plugin_serena_serena__initial_instructions
  3. mcp__plugin_serena_serena__activate_project (현재 디렉터리)
  4. mcp__plugin_serena_serena__check_onboarding_performed → 미수행 시 onboarding
  5. Bash: touch /tmp/serena-ready-${PROJ_HASH}  ← PostToolUse 미발화 백업
이후 코드 탐색은 Grep/Read 대신 Serena 도구를 1순위로 사용합니다.
---
EOF

exit 0
