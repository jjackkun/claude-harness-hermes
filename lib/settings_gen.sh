#!/usr/bin/env bash
# dev-setting/lib/settings_gen.sh
# Responsibility:
#   generate_settings_json  → .claude/settings.json  (committed: hooks + permissions)
#   generate_settings_local → .claude/settings.local.json (gitignored: env only)
# Python tmpdir 브리지로 shell 배열을 JSON 구조로 안전 직렬화.

_settings_gen_check_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 is required to generate settings files"
    return 1
  fi
}

_settings_gen_write_arrays() {
  local tmpdir="$1"

  _write_array() {
    local path="$1"; shift
    : > "$path"
    local item
    for item in "$@"; do
      [[ -z "$item" ]] && continue
      printf '%s\n' "$item" >> "$path"
    done
  }

  _write_array "$tmpdir/post_edit" "${POST_EDIT_HOOKS[@]:-}"
  _write_array "$tmpdir/stop"      "${STOP_HOOKS[@]:-}"
  _write_array "$tmpdir/env"       "${ENV_VARS[@]:-}"
  _write_array "$tmpdir/deny"      "${DENY_AGENTS[@]:-}"
  _write_array "$tmpdir/session_start"      "${SESSION_START_HOOKS[@]:-}"
  _write_array "$tmpdir/user_prompt_submit" "${USER_PROMPT_SUBMIT_HOOKS[@]:-}"
  _write_array "$tmpdir/pre_tool_use"       "${PRE_TOOL_USE_HOOKS[@]:-}"
  _write_array "$tmpdir/post_tool_use"      "${POST_TOOL_USE_HOOKS[@]:-}"
  _write_array "$tmpdir/permissions_allow"  "${HARNESS_PERMISSIONS_ALLOW[@]:-}"
  _write_array "$tmpdir/worktree_bg_isolation" "${WORKTREE_BG_ISOLATION[@]:-}"

  unset -f _write_array
}

# _settings_gen_run <generator.py> <output_path>
# 공통 실행기 — 서브셸 + EXIT trap 으로 python 실패(set -e 종료 포함)에도
# tmpdir 가 누수되지 않는다. 실패 시 rc 를 그대로 반환.
_settings_gen_run() {
  local script="$1" output="$2"
  _settings_gen_check_python || return 1

  local rc=0
  (
    tmpdir=$(mktemp -d -t cc-settings-XXXXXX) || exit 1
    trap 'rm -rf "$tmpdir"' EXIT
    _settings_gen_write_arrays "$tmpdir"
    DS_TMPDIR="$tmpdir" python3 "$DEV_SETTING_DIR/lib/$script" "$output"
  ) || rc=$?

  if [[ $rc -ne 0 ]]; then
    log_error "settings generation failed: $output (exit $rc)"
    return "$rc"
  fi
  log_info "  settings→ $output"
}

# generate_settings_json <output_path>
# → .claude/settings.json (committed): hooks + permissions.deny + permissions.allow
generate_settings_json() {
  _settings_gen_run generate_settings_json.py "$1"
}

# generate_settings_local <output_path>
# → .claude/settings.local.json (gitignored): env only
generate_settings_local() {
  _settings_gen_run generate_settings.py "$1"
}
