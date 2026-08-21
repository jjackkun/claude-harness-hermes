#!/usr/bin/env bash
# dev-setting/lib/permission_inventory.sh
# Responsibility: "하네스가 배포한 permissions.allow 항목" 목록을 단일 소스로 제공한다.
#
# lib/hook_inventory.sh 와 같은 역할을 권한에 대해 한다. 설치 경로가 프로젝트의
# settings.json allow 항목을 두 부류로 가르는 근거가 된다.
#   - 하네스 소유 : 프리셋에서 빠지면 걷어내야 함
#   - 사용자 소유 : 프리셋과 무관하므로 항상 보존
#
# 적용 대상은 settings.json 뿐이다. settings.local.json 은 Claude Code 의
# "don't ask again" 승인이 쌓이는 자리라 하네스가 권한을 건드리지 않는다
# (lib/generate_settings.py 참조). 그래서 회수가 사용자 승인을 지울 수 없다.
#
# 근거: docs/superpowers/specs/2026-08-21-preset-retirement-ownership-design.md

# 더 이상 배포하지 않는 프리셋이 넣었던 allow 항목.
# 소유 판별은 presets/**/*.conf 소싱에 의존하므로, .conf 를 지우는 순간
# "하네스 소유"로 인식되지 않아 기존 프로젝트에서 제거할 수 없게 된다.
# 배포 중단하는 프리셋의 allow 항목은 .conf 를 지우기 전에 반드시 여기 등재한다.
#
# 2026-08-21 serena — presets/workflow/serena.conf (ee86a0a 에서 삭제). 등재 없이
# 지워져 6개 프로젝트에 권한 28건이 고립됐다. 이 목록의 첫 표본이자 재발 방지 근거.
RETIRED_PERMISSION_ALLOW=(
  mcp__plugin_serena_serena__activate_project
  mcp__plugin_serena_serena__check_onboarding_performed
  mcp__plugin_serena_serena__create_text_file
  mcp__plugin_serena_serena__delete_memory
  mcp__plugin_serena_serena__edit_memory
  mcp__plugin_serena_serena__find_declaration
  mcp__plugin_serena_serena__find_file
  mcp__plugin_serena_serena__find_implementations
  mcp__plugin_serena_serena__find_referencing_symbols
  mcp__plugin_serena_serena__find_symbol
  mcp__plugin_serena_serena__get_current_config
  mcp__plugin_serena_serena__get_diagnostics_for_file
  mcp__plugin_serena_serena__get_symbols_overview
  mcp__plugin_serena_serena__initial_instructions
  mcp__plugin_serena_serena__insert_after_symbol
  mcp__plugin_serena_serena__insert_before_symbol
  mcp__plugin_serena_serena__list_dir
  mcp__plugin_serena_serena__list_memories
  mcp__plugin_serena_serena__onboarding
  mcp__plugin_serena_serena__read_file
  mcp__plugin_serena_serena__read_memory
  mcp__plugin_serena_serena__rename_memory
  mcp__plugin_serena_serena__rename_symbol
  mcp__plugin_serena_serena__replace_content
  mcp__plugin_serena_serena__replace_symbol_body
  mcp__plugin_serena_serena__safe_delete_symbol
  mcp__plugin_serena_serena__search_for_pattern
  mcp__plugin_serena_serena__write_memory
)

# harness_permission_inventory
# 하네스 소유 allow 항목 전체를 개행 구분으로 출력.
#   (1) 모든 프리셋이 제공하는 항목의 합집합  (2) 은퇴 등재분
# (1) 은 서브셸에서 전 프리셋을 소싱해 구한다 — 호출자의 현재 프리셋 상태를
# 오염시키지 않기 위해 반드시 서브셸이어야 한다.
harness_permission_inventory() {
  {
    (
      log_info()  { :; }
      log_warn()  { :; }
      log_error() { :; }
      reset_preset_vars
      local f
      for f in "$DEV_SETTING_DIR"/presets/*/*.conf; do
        [[ -f "$f" ]] && source "$f"
      done
      printf '%s\n' "${HARNESS_PERMISSIONS_ALLOW[@]:-}"
    )
    if (( ${#RETIRED_PERMISSION_ALLOW[@]} > 0 )); then
      printf '%s\n' "${RETIRED_PERMISSION_ALLOW[@]}"
    fi
  } | sed '/^[[:space:]]*$/d' | sort -u
}
