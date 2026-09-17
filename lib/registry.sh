#!/usr/bin/env bash
# lib/registry.sh
# Responsibility: 머신 로컬 레지스트리(.installed-projects[.codex]) 등록 판정·기록만 담당.
#
# 임시 디렉터리 아래 프로젝트와 HERMES_NO_REGISTER=1 은 등록하지 않는다 — 테스트·리허설·일회성
# 설치는 전파 대상이 아니다. /tmp 와 $TMPDIR 를 **둘 다** 본다: 하나만 보면 TMPDIR 을 딴 곳으로
# 둔 채 /tmp 사본을 설치할 때 샌다(2026-09-17 리허설이 이 조합으로 실 레지스트리를 두 번 오염).
# project-claude.sh 와 project-codex.sh 가 같은 판정을 써야 하므로 한 곳에 둔다.

# registry_is_temp_path <project_path> → 0 이면 임시 경로
registry_is_temp_path() {
  local real root
  real="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  for root in /tmp "${TMPDIR:-}"; do
    [[ -n "$root" && -d "$root" ]] || continue
    root="$(cd "$root" 2>/dev/null && pwd -P)" || continue
    [[ "$real" == "$root"/* ]] && return 0
  done
  return 1
}

# registry_register <registry_file> <project_path> <label>
# 등록했으면 "Registered → <label>", 생략했으면 생략 사유를 log_info 로 남긴다.
registry_register() {
  local registry="$1" project_path="$2" label="$3"
  touch "$registry"
  # HERMES_FORCE_REGISTER=1 은 테스트 전용 — 샌드박스 레지스트리에 임시 경로를 일부러 올릴 때만.
  # 예전에는 TMPDIR 을 딴 곳으로 돌려 같은 효과를 냈는데, 그것이 곧 실 레지스트리 오염 경로였다.
  if [[ "${HERMES_FORCE_REGISTER:-0}" != "1" ]] && { [[ "${HERMES_NO_REGISTER:-0}" == "1" ]] || registry_is_temp_path "$project_path"; }; then
    log_info "레지스트리 등록 생략 (임시 경로 또는 HERMES_NO_REGISTER=1)"
  elif ! grep -qxF "$project_path" "$registry"; then
    echo "$project_path" >> "$registry"
    log_info "Registered → $label"
  fi
}
