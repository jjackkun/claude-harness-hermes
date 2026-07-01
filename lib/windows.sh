#!/usr/bin/env bash
# dev-setting/lib/windows.sh
# Windows/WSL2 감지 헬퍼 + hook 명령 래핑.
# common.sh 가 제일 먼저 source 하므로 다른 모든 모듈에서 사용 가능.
#
# Sourced, not executed directly.

# is_windows_path <path>
# /mnt/<drive-letter>/ 로 시작하는 WSL2 Windows 마운트 경로인지 확인.
is_windows_path() {
  [[ "${1:-}" =~ ^/mnt/[a-z]/ ]]
}

# is_wsl
# WSL2(또는 WSL1) 환경 여부를 커널 릴리즈 문자열로 판별.
is_wsl() {
  [[ "$(uname -r 2>/dev/null)" == *microsoft* ]]
}

# wrap_hooks_for_windows <project_path>
# POST_EDIT_HOOKS, USER_PROMPT_SUBMIT_HOOKS, PRE_TOOL_USE_HOOKS, POST_TOOL_USE_HOOKS,
# STOP_HOOKS, SESSION_START_HOOKS 배열의
# hook 명령을 Windows Claude Code Desktop 에서 실행 가능한 형태로 제자리 변환:
#   ${CLAUDE_PROJECT_DIR}/scripts/hooks/hook.sh
#   → wsl bash "/mnt/c/.../scripts/hooks/hook.sh"
# Windows 경로가 아니면 no-op.
wrap_hooks_for_windows() {
  local project_path="$1"
  is_windows_path "$project_path" || return 0

  _wrap_one_array() {
    local arr_name="$1"
    local -a out=()
    local -n _arr="$arr_name"
    local entry cmd matcher
    for entry in "${_arr[@]:-}"; do
      [[ -z "$entry" ]] && continue
      if [[ "$entry" == *::* ]]; then
        # PreToolUse 형식: "matcher::command"
        matcher="${entry%%::*}"
        cmd="${entry#*::}"
        cmd="${cmd//\$\{CLAUDE_PROJECT_DIR\}/$project_path}"
        out+=("${matcher}::wsl bash \"${cmd}\"")
      else
        cmd="${entry//\$\{CLAUDE_PROJECT_DIR\}/$project_path}"
        out+=("wsl bash \"${cmd}\"")
      fi
    done
    _arr=("${out[@]:-}")
  }

  _wrap_one_array POST_EDIT_HOOKS
  _wrap_one_array USER_PROMPT_SUBMIT_HOOKS
  _wrap_one_array PRE_TOOL_USE_HOOKS
  _wrap_one_array POST_TOOL_USE_HOOKS
  _wrap_one_array STOP_HOOKS
  _wrap_one_array SESSION_START_HOOKS
}
