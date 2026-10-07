#!/usr/bin/env bash
# dev-setting/lib/newline_key.sh
# Responsibility: 이 컴퓨터에서 Claude Code 프롬프트의 shift+enter 가 개행이 되게 한다.
#
# 두 곳을 맞춘다 (둘 다 저장소 밖의 컴퓨터별 설정이라 새 컴퓨터에는 안 따라온다):
#   1. <claude_config_dir>/keybindings.json   shift+enter → chat:newline
#   2. Windows Terminal settings.json (WSL)   shift+enter → ESC CR 보내기
# 2 가 없으면 Windows Terminal 은 shift+enter 를 enter 와 같은 신호로 보내 1 만으로는 안 된다.
#
# 이미 정해 둔 shift+enter 는 건드리지 않고, 고치기 전에 백업을 뜬다. 다시 돌려도 안전하다.
# 다른 터미널(Orca 등)은 설정 자리가 없어 다루지 않는다.
#
# Sourced, not executed directly.

# find_windows_terminal_settings
# Windows Terminal 설정 파일 경로를 한 줄에 하나씩 낸다 (설치판·프리뷰·비설치판).
# WSL 이 아니면 아무것도 안 낸다. DS_WINDOWS_USERS_DIR 로 Users 폴더를 바꿔 끼울 수 있다(시험용).
find_windows_terminal_settings() {
  [[ -n "${DS_WINDOWS_USERS_DIR:-}" ]] || is_wsl || return 0
  local users_dir="${DS_WINDOWS_USERS_DIR:-/mnt/c/Users}"
  local file
  for file in \
    "$users_dir"/*/AppData/Local/Packages/Microsoft.WindowsTerminal*/LocalState/settings.json \
    "$users_dir"/*/AppData/Local/Microsoft/"Windows Terminal"/settings.json; do
    [[ -f "$file" && -w "$file" ]] && echo "$file"
  done
  return 0
}

# install_newline_key <claude_config_dir>
install_newline_key() {
  local claude_dir="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    log_warn "  newline → python3 가 없어 shift+enter 개행 설정을 건너뜁니다"
    return 0
  fi
  local line
  while IFS= read -r line; do
    log_info "  newline → $line"
  done < <(python3 "$DEV_SETTING_DIR/lib/newline_key_claude.py" "$claude_dir")

  local -a wt_settings=()
  mapfile -t wt_settings < <(find_windows_terminal_settings)
  if [[ ${#wt_settings[@]} -eq 0 ]]; then
    log_info "  newline → Windows Terminal 설정을 찾지 못했습니다 — 터미널 쪽은 건너뜁니다"
    return 0
  fi
  while IFS= read -r line; do
    log_info "  newline → $line"
  done < <(python3 "$DEV_SETTING_DIR/lib/newline_key_wt.py" "${wt_settings[@]}")
}
