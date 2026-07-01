#!/usr/bin/env bash
# tests/preset-integrity-test.sh
# 프리셋 참조 무결성 검사 — 모든 presets/**/*.conf 의 SKILLS / AGENTS / RULES 항목이
# assets/{skills,agents,rules} 에 실존하는지 확인한다. 깨진 참조가 하나라도 있으면 exit 1.
#
# Usage: bash tests/preset-integrity-test.sh
set -uo pipefail

DEV_SETTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$DEV_SETTING_DIR/assets"
TEMPLATES_DIR="$DEV_SETTING_DIR/templates"
export DEV_SETTING_DIR ASSETS_DIR TEMPLATES_DIR

# preset 이 사용하는 헬퍼 로드 (reset_preset_vars / merge_permissions_file)
# shellcheck source=../lib/preset.sh
source "$DEV_SETTING_DIR/lib/preset.sh"
# preset 이 log_* 를 호출할 수 있으므로 no-op 스텁 제공
log_info()  { :; }
log_warn()  { :; }
log_error() { :; }

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

ERRORS=0
CHECKED=0

_check_entry() {
  local conf="$1" kind="$2" name="$3" path="$4"
  CHECKED=$((CHECKED + 1))
  if [[ ! -e "$path" ]]; then
    echo -e "  ${RED}✗${RESET} ${conf#$DEV_SETTING_DIR/}: $kind '$name' → assets 에 없음 ($path)"
    ERRORS=$((ERRORS + 1))
  fi
}

check_conf() {
  local conf="$1"

  # 프리셋이 참조하는 추가 배열/플래그도 source 전에 초기화 (set -u 대비)
  reset_preset_vars
  GITIGNORE_ENTRIES=()
  WORKTREE_BG_ISOLATION=()
  HARNESS_DOC_GARDENING=0
  HARNESS_COMPONENT_STRUCTURE=0
  PROJECT_PATH=""

  # subshell 부작용 방지가 아니라 참조 수집이 목적이므로 직접 source.
  # (프리셋은 설치 부작용을 source 시점에 일으키지 않는다는 규약 — hermes.conf 참고)
  # shellcheck source=/dev/null
  if ! source "$conf"; then
    echo -e "  ${RED}✗${RESET} ${conf#$DEV_SETTING_DIR/}: source 실패"
    ERRORS=$((ERRORS + 1))
    return
  fi

  local item
  for item in "${SKILLS[@]:-}"; do
    [[ -z "$item" ]] && continue
    _check_entry "$conf" "skill" "$item" "$ASSETS_DIR/skills/$item"
  done
  for item in "${AGENTS[@]:-}"; do
    [[ -z "$item" ]] && continue
    _check_entry "$conf" "agent" "$item" "$ASSETS_DIR/agents/$item.md"
  done
  for item in "${RULES[@]:-}"; do
    [[ -z "$item" ]] && continue
    _check_entry "$conf" "rule" "$item" "$ASSETS_DIR/rules/$item"
  done
  # DENY_AGENTS 의 유령 항목도 회귀 방지 차원에서 검사
  for item in "${DENY_AGENTS[@]:-}"; do
    [[ -z "$item" ]] && continue
    _check_entry "$conf" "deny-agent" "$item" "$ASSETS_DIR/agents/$item.md"
  done
}

echo "━━━ preset integrity test ━━━"
shopt -s nullglob
CONF_COUNT=0
for conf in "$DEV_SETTING_DIR/presets"/*.conf "$DEV_SETTING_DIR/presets"/*/*.conf; do
  [[ -f "$conf" ]] || continue
  CONF_COUNT=$((CONF_COUNT + 1))
  check_conf "$conf"
done
shopt -u nullglob

echo ""
if [[ $ERRORS -gt 0 ]]; then
  echo -e "${RED}FAIL${RESET}: ${CONF_COUNT}개 conf, ${CHECKED}개 참조 중 ${ERRORS}개 깨짐"
  exit 1
fi
echo -e "${GREEN}PASS${RESET}: ${CONF_COUNT}개 conf, ${CHECKED}개 참조 모두 유효"
