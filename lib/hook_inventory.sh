#!/usr/bin/env bash
# dev-setting/lib/hook_inventory.sh
# Responsibility: "하네스가 배포한 hook" 파일명 목록을 단일 소스로 제공한다.
#
# 설치/제거 경로가 프로젝트의 hook 을 두 부류로 가르는 근거가 된다.
#   - 하네스 소유 : 프리셋에서 빠지면 걷어내야 함
#   - 사용자 소유 : 프리셋과 무관하므로 항상 보존
# 이 구분이 없으면 settings.json 병합이 "프리셋에서 빠진 hook"과
# "사용자가 직접 넣은 hook"을 구별하지 못해 한번 등록된 hook 이 영구히 남는다.

# 더 이상 배포하지 않는 hook 파일명.
# 소유 판별은 assets/hooks/ 디렉터리 스캔에 의존하므로, 파일을 지우는 순간
# "하네스 소유"로 인식되지 않아 기존 프로젝트에서 제거할 수 없게 된다.
# 배포 중단한 hook 은 파일을 지우기 전에 반드시 여기 등재한다.
# 지금은 비어 있다. 배포를 중단하는 hook 이 생기면 파일을 지우기 전에 여기 넣는다.
RETIRED_HOOK_SOURCES=()

# harness_hook_inventory
# 하네스 소유 hook 파일명 전체(현행 assets/hooks + 은퇴분)를 개행 구분으로 출력.
harness_hook_inventory() {
  {
    local hooks_dir="$DEV_SETTING_DIR/assets/hooks"
    if [[ -d "$hooks_dir" ]]; then
      find "$hooks_dir" -maxdepth 1 -type f \
        \( -name "*.sh" -o -name "*.json" -o -name "*.py" \) 2>/dev/null \
        | xargs -I{} basename {}
    fi
    local name
    if (( ${#RETIRED_HOOK_SOURCES[@]} > 0 )); then
      for name in "${RETIRED_HOOK_SOURCES[@]}"; do
        printf '%s\n' "$name"
      done
    fi
  } | sort -u
}
