#!/usr/bin/env bash
# dev-setting/lib/codex_settings_gen.sh
# Responsibility: generate Codex project hook metadata.

generate_codex_hooks_json() {
  local output="$1"
  local project_path="$2"

  if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 is required to generate Codex hooks.json"
    return 1
  fi

  local tmpdir
  tmpdir=$(mktemp -d -t codex-hooks-XXXXXX)

  _write_array() {
    local path="$1"; shift
    : > "$path"
    local item
    for item in "$@"; do
      [[ -z "$item" ]] && continue
      printf '%s\n' "$item" >> "$path"
    done
  }

  # generate_codex_hooks.py 는 post_edit / stop / env 만 읽는다.
  # (pre_tool_use, user_prompt_submit tmp 파일은 dead output 이어서 제거)
  _write_array "$tmpdir/post_edit" "${POST_EDIT_HOOKS[@]:-}"
  _write_array "$tmpdir/stop" "${STOP_HOOKS[@]:-}"
  _write_array "$tmpdir/env" "${ENV_VARS[@]:-}"

  unset -f _write_array

  DS_TMPDIR="$tmpdir" CODEX_PROJECT_DIR="$project_path" \
    python3 "$DEV_SETTING_DIR/lib/generate_codex_hooks.py" "$output"
  local rc=$?
  rm -rf "$tmpdir"
  log_info "  hooks   → $output"
  return $rc
}
