#!/usr/bin/env bash
# PostToolUse hook — check_onboarding_performed 완료 시 serena-ready flag 생성.
# matcher: mcp__plugin_serena_serena__check_onboarding_performed
#
# serena 프리셋 사용 시 등록됨 (presets/workflow/serena.conf).

_RAW_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
# 워크트리에서도 메인 루트 해시로 통일.
_PROJ_DIR=$(echo "$_RAW_DIR" | sed 's|/.claude/worktrees/[^/]*$||')
PROJ_HASH=$(echo "$_PROJ_DIR" | md5sum | cut -c1-8)
touch "/tmp/serena-ready-${PROJ_HASH}"
exit 0
