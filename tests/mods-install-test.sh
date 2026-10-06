#!/usr/bin/env bash
# tests/mods-install-test.sh
# 패널 모드 세 개가 전역 기본 설치(presets/_common.conf)로 깔리는지 검사.
#   1. 아무것도 고르지 않은 기본 설치에 모드 세 개가 깔리고 설치 목록에 기록된다.
#   2. 다시 돌려도(update-all.sh 가 도는 방식) 그대로이고, 백업 폴더가 생기지 않는다.
#   3. 옛 선택 기록(presets.global.lock 의 mods)이 남은 컴퓨터에서도 실패 없이 깔린다.
#   4. 손으로 넣은 무관한 폴더는 건드리지 않는다.
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

echo "[1] 고르지 않아도 기본 설치에 깔린다"
A="$TMP_ROOT/a"; mkdir -p "$A/skills/$UNRELATED"; echo "mine" > "$A/skills/$UNRELATED/note.txt"
check "기본 설치가 성공한다" 'install "$A"'
check "모드 세 개의 폴더가 있다" 'all_present "$A" "${MODS[@]}"'
check "모드마다 매니페스트(.claude-plugin/plugin.json)가 있다" '[[ -f "$A/skills/file-explorer/.claude-plugin/plugin.json" && -f "$A/skills/tool-calls-pane/.claude-plugin/plugin.json" && -f "$A/skills/hermes-roster-pane/.claude-plugin/plugin.json" ]]'
check "Prism 묶음과 그 라이선스가 함께 깔린다" '[[ -s "$A/skills/file-explorer/hooks/vendor/prism.js" && -s "$A/skills/file-explorer/hooks/vendor/PRISM-LICENSE" ]]'
check "설치 목록에 세 모드가 기록된다" 'all_in_manifest "$A" "${MODS[@]}"'
check "전역 기본 스킬 ${#BASELINE[@]}종이 모두 있다" 'all_present "$A" "${BASELINE[@]}"'
check "선택 기록(lock)을 만들지 않는다" '[[ ! -s "$A/presets.global.lock" ]]'

echo "[2] 다시 돌려도 그대로다"
check "두 번째 설치가 성공한다" 'install "$A"'
check "모드 세 개가 그대로 있다" 'all_present "$A" "${MODS[@]}"'
check "백업 폴더가 생기지 않는다" '[[ -z "$(ls -d "$A/skills/"*.backup-* 2>/dev/null)" ]]'

echo "[3] 옛 선택 기록이 남은 컴퓨터에서도 깔린다"
B="$TMP_ROOT/b"; mkdir -p "$B"; echo "mods" > "$B/presets.global.lock"
check "옛 lock(mods)이 있어도 설치가 성공한다" 'install "$B"'
check "모드 세 개가 있다" 'all_present "$B" "${MODS[@]}"'
check "전역 기본 스킬이 모두 있다" 'all_present "$B" "${BASELINE[@]}"'

echo "[4] 손으로 넣은 무관한 폴더는 남는다"
check "무관한 폴더의 파일이 그대로다" '[[ "$(cat "$A/skills/$UNRELATED/note.txt")" == "mine" ]]'

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
