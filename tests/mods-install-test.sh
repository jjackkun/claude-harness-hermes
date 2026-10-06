#!/usr/bin/env bash
# tests/mods-install-test.sh
# 패널 모드 전역 선택 프리셋(presets/global/mods.conf) 설치 검사.
#   1. 켜면 모드 세 개가 깔리고 설치 목록에 기록되며, 전역 기본 스킬도 그대로 있다.
#   2. 끄면 모드 세 개만 지워지고, 기본 스킬과 손으로 넣은 무관한 폴더는 남는다.
#   3. 켠 뒤 인자 없이 다시 돌려도(update-all.sh 가 도는 방식) 고른 것이 유지된다.
#   4. 고르지 않으면 깔리지 않는다.
#   5. claude 가 있으면 깔린 모드가 엔진 검사(claude plugin validate)를 통과한다.
# 실제 ~/.claude 는 건드리지 않는다: CLAUDE_CONFIG_DIR 를 임시 폴더로 둔다.
#
# Usage: bash tests/mods-install-test.sh
set -uo pipefail

DEV_SETTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODS=(file-explorer tool-calls-pane hermes-roster-pane)
UNRELATED="my-own-thing"

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'
ERRORS=0
CHECKED=0

ok()   { CHECKED=$((CHECKED + 1)); echo -e "  ${GREEN}✓${RESET} $1"; }
fail() { CHECKED=$((CHECKED + 1)); ERRORS=$((ERRORS + 1)); echo -e "  ${RED}✗${RESET} $1"; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# 전역 기본 스킬 이름은 _common.conf 에서 읽는다(여기에 따로 적어 두면 어긋난다).
SKILLS=(); AGENTS=(); RULES=()
# shellcheck source=/dev/null
source "$DEV_SETTING_DIR/presets/_common.conf"
BASELINE=("${SKILLS[@]}")

# 실제 ~/.claude/skills 의 목록. 시험 앞뒤로 같아야 한다.
real_listing() { ls -A "$HOME/.claude/skills" 2>/dev/null | LC_ALL=C sort | tr '\n' ' '; }
REAL_BEFORE="$(real_listing)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# install <대상 폴더> [public-claude.sh 인자…] — 임시 폴더를 Claude 설정 폴더로 삼아 전역 스킬만 깐다.
install() {
  local target="$1"; shift
  CLAUDE_CONFIG_DIR="$target" bash "$DEV_SETTING_DIR/public-claude.sh" --skills-only "$@" >"$TMP_ROOT/install.log" 2>&1
}
all_present() { local dir="$1"; shift; local name; for name in "$@"; do [[ -d "$dir/skills/$name" ]] || return 1; done; }
none_present() { local dir="$1"; shift; local name; for name in "$@"; do [[ ! -e "$dir/skills/$name" ]] || return 1; done; }
all_in_manifest() { local dir="$1"; shift; local name; for name in "$@"; do grep -q "\"$name\"" "$dir/.factory-manifest.json" 2>/dev/null || return 1; done; }

echo "[1] 켜면 깔린다"
A="$TMP_ROOT/a"; mkdir -p "$A"
check "설치 명령이 성공한다" 'install "$A" --set-global "mods"'
check "모드 세 개의 폴더가 있다" 'all_present "$A" "${MODS[@]}"'
check "모드마다 매니페스트(.claude-plugin/plugin.json)가 있다" '[[ -f "$A/skills/file-explorer/.claude-plugin/plugin.json" && -f "$A/skills/tool-calls-pane/.claude-plugin/plugin.json" && -f "$A/skills/hermes-roster-pane/.claude-plugin/plugin.json" ]]'
check "Prism 묶음과 그 라이선스가 함께 깔린다" '[[ -s "$A/skills/file-explorer/hooks/vendor/prism.js" && -s "$A/skills/file-explorer/hooks/vendor/PRISM-LICENSE" ]]'
check "설치 목록에 세 모드가 기록된다" 'all_in_manifest "$A" "${MODS[@]}"'
check "전역 기본 스킬 ${#BASELINE[@]}종도 그대로 있다" 'all_present "$A" "${BASELINE[@]}"'
check "고른 것이 lock 에 적힌다" '[[ "$(cat "$A/presets.global.lock")" == "mods" ]]'

echo "[2] 끄면 모드 세 개만 지워진다"
mkdir -p "$A/skills/$UNRELATED" && echo "손으로 넣은 것" > "$A/skills/$UNRELATED/note.txt"
check "끄는 명령이 성공한다" 'install "$A" --set-global ""'
check "모드 세 개가 없다" 'none_present "$A" "${MODS[@]}"'
check "전역 기본 스킬은 남는다" 'all_present "$A" "${BASELINE[@]}"'
check "손으로 넣은 무관한 폴더는 남는다" '[[ -f "$A/skills/$UNRELATED/note.txt" ]]'

echo "[3] 인자 없이 다시 돌려도 유지된다"
B="$TMP_ROOT/b"; mkdir -p "$B"
install "$B" --set-global "mods"
check "인자 없는 재실행이 성공한다" 'install "$B"'
check "모드 세 개가 그대로 있다" 'all_present "$B" "${MODS[@]}"'
check "lock 이 그대로다" '[[ "$(cat "$B/presets.global.lock")" == "mods" ]]'

echo "[4] 고르지 않으면 깔리지 않는다"
C="$TMP_ROOT/c"; mkdir -p "$C"
check "기본 설치가 성공한다" 'install "$C"'
check "모드 세 개가 없다" 'none_present "$C" "${MODS[@]}"'
check "전역 기본 스킬은 있다" 'all_present "$C" "${BASELINE[@]}"'

echo "[5] 깔린 모드가 엔진 검사를 통과한다"
if command -v claude >/dev/null 2>&1; then
  for name in "${MODS[@]}"; do
    check "claude plugin validate: $name" 'claude plugin validate "$B/skills/$name" >"$TMP_ROOT/validate.log" 2>&1'
  done
else
  echo "  - claude 가 없어 건너뜀 (이 컴퓨터에서는 엔진 검사가 확인되지 않았다)"
fi

echo "[6] 실제 ~/.claude/skills 는 그대로다"
check "시험 앞뒤 목록이 같다" '[[ "$(real_listing)" == "$REAL_BEFORE" ]]'

echo
if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}mods-install-test: ${CHECKED}건 통과${RESET}"
  exit 0
fi
echo -e "${RED}mods-install-test: ${ERRORS}건 실패 / ${CHECKED}건${RESET}"
echo "--- 마지막 설치 로그 ---"; tail -15 "$TMP_ROOT/install.log" 2>/dev/null
exit 1
