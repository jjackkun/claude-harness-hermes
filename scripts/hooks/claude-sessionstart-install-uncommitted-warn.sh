#!/usr/bin/env bash
# SessionStart hook — 설치 영수증(.claude/.last-install.txt)에 적힌 파일 중 git 이 무시하지
# 않으면서 아직 커밋되지 않은 것이 있으면 경고한다.
#
# 근거: docs/exec-plans/active/2026-09-16-install-receipt.md — 전파 커밋의 add 경로를 기억으로
# 정하다 hermes 스크립트 7개를 5곳에서 빠뜨린 사고. 경고이지 차단이 아니다.
#
# 출력 형식: [install-uncommitted WARN] 설치물 N건이 커밋되지 않았습니다 …  (테스트가 이 접두어를 고정)

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
RECEIPT="$PROJECT_DIR/.claude/.last-install.txt"
[[ -f "$RECEIPT" ]] || exit 0
git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# 영수증 경로 중 무시되지 않은 것만 (추적 중이거나 새 파일)
mapfile -t PATHS < <(cd "$PROJECT_DIR" && xargs -d '\n' git ls-files -co --exclude-standard -- < "$RECEIPT" 2>/dev/null)
[[ ${#PATHS[@]} -gt 0 ]] || exit 0

mapfile -t DIRTY < <(cd "$PROJECT_DIR" && git status --porcelain --untracked-files=all -- "${PATHS[@]}" 2>/dev/null | cut -c4-)
[[ ${#DIRTY[@]} -gt 0 ]] || exit 0

{
  echo "[install-uncommitted WARN] 설치물 ${#DIRTY[@]}건이 커밋되지 않았습니다 (.claude/.last-install.txt 기준). 다른 컴퓨터·동료는 옛 버전을 받습니다."
  printf '  %s\n' "${DIRTY[@]:0:5}"
  [[ ${#DIRTY[@]} -gt 5 ]] && echo "  … 외 $(( ${#DIRTY[@]} - 5 ))건"
  echo "  → 커밋: git add \$(git ls-files -co --exclude-standard -- \$(cat .claude/.last-install.txt)) && git commit"
} >&2
exit 0
