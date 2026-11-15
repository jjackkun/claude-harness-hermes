#!/usr/bin/env bash
# lib/factory_path.sh
# Responsibility: 이 컴퓨터의 공장 위치(메인 저장소 루트)를 ~/.hermes/factory-path 에 적는 것만 담당한다.
# 계획: docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G6
#
# 소우주 세션은 이 파일로 (1) 알림 문구를 고르고 (2) "공장에서 올려" 를 공장에서 실행한다.
# 공장이 없는 컴퓨터에는 이 파일이 생기지 않는다. 워크트리·임시 사본은 사라질 경로라 적지 않는다.
#
# 공개 함수 2개: factory_main_root · factory_path_record

# factory_main_root <dir> — 워크트리면 메인 저장소 루트, 아니면 그 저장소 루트. 못 구하면 rc 1.
factory_main_root() {
  local common
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [[ -n "$common" && -d "$common" ]] || return 1
  (cd "$common/.." && pwd -P)
}

# factory_path_record <factory_dir>
# 기록 조건: 메인 루트를 구할 수 있고, 거기에 assets/upstream.json 이 있고, 임시 경로가 아니다.
# 실패해도 설치를 멈추지 않는다.
factory_path_record() {
  local root
  root="$(factory_main_root "$1")" || return 0
  [[ -f "$root/assets/upstream.json" ]] || return 0
  if declare -F registry_is_temp_path >/dev/null 2>&1 && registry_is_temp_path "$root"; then
    return 0
  fi
  local dir="${HOME:-}/.hermes"
  [[ -n "${HOME:-}" ]] || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\n' "$root" > "$dir/factory-path.tmp" 2>/dev/null && mv -f "$dir/factory-path.tmp" "$dir/factory-path" 2>/dev/null
  return 0
}
