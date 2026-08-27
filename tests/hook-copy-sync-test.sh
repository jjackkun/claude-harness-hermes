#!/usr/bin/env bash
# tests/hook-copy-sync-test.sh
# assets/hooks/ (원본) 과 scripts/hooks/ (이 저장소의 설치본) 의 동명 파일이
# 갈라지지 않았는지 검사한다.
#
# 왜 필요한가: 하네스는 훅을 *복사* 로 배포한다(lib/harness_installers.sh:4 —
# "심볼릭 X, 이유: 사용자 편집 + WSL 호환"). 복사는 갈라진다. 실제로 시크릿 검사기와
# 계획 계수기가 각각 한 번씩 갈라져, 한쪽만 고쳐 놓고 고쳤다고 믿은 사고가 났다.
#
# 링크로 묶는 대신 테스트로 막는 이유: 복사 결정을 뒤집을 근거가 없기 때문이다.
# 결정을 유지하되 그 결정이 만드는 위험을 기계가 지킨다.
#
# 검사 대상은 앞의 두 자리다. `.git/hooks/` 사본은 재설치가 갱신하므로 보지 않는다.
#
# 실행: bash tests/hook-copy-sync-test.sh
# 종료 코드: 0 = 전부 동일, 1 = 갈라진 파일 있음
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$REPO_ROOT/assets/hooks"
INSTALLED="$REPO_ROOT/scripts/hooks"

GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'

PASS=0; FAIL=0
ok()   { echo -e "  ${GREEN}✓${RESET} $1"; PASS=$((PASS+1)); }
bad()  { echo -e "  ${RED}✗${RESET} $1"; FAIL=$((FAIL+1)); }

if [[ ! -d "$INSTALLED" ]]; then
  echo "  scripts/hooks/ 없음 — 이 저장소에 하네스가 설치되지 않았다. 검사 생략."
  exit 0
fi

echo "== 동명 훅 파일 대조 =="

CHECKED=0
for installed in "$INSTALLED"/*; do
  [[ -f "$installed" ]] || continue
  name="$(basename "$installed")"
  origin="$ASSETS/$name"

  # assets 에 없는 파일 = 프로젝트가 직접 둔 것. 하네스 소유가 아니므로 검사하지 않는다.
  [[ -f "$origin" ]] || continue

  CHECKED=$((CHECKED+1))
  if cmp -s "$origin" "$installed"; then
    ok "$name"
  else
    bad "$name — assets/hooks 와 scripts/hooks 가 갈라졌다"
    echo "      원본이 assets/hooks/$name 다. 다음으로 맞춘다:"
    echo "        cp assets/hooks/$name scripts/hooks/$name"
    echo "      설치본 쪽이 옳다면 먼저 그 수정을 assets/hooks/ 로 옮긴 뒤 다시 복사한다."
  fi
done

if [[ $CHECKED -eq 0 ]]; then
  bad "대조할 동명 파일이 하나도 없다 — 검사가 조용히 아무것도 안 했다"
fi

echo ""
echo "== 결과 =="
echo "  대조: $CHECKED / 통과: $PASS / 실패: $FAIL"
[[ $FAIL -eq 0 ]]
