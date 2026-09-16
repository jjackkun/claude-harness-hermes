#!/usr/bin/env bash
# SessionStart hook — 공장 자기 설치의 상대경로 링크(.claude/{skills,agents,rules}/* →
# ../../assets/…)가 깨졌는지 판정해 재설치를 안내한다.
#
# 설계: docs/hermes-universe/design/world/copy-install.md §6 (E-02·E-03).
# 상대경로 링크는 저장소를 통째로 옮겨도 살지만, 저장소 안 구조(assets/ 이름, .claude/ 깊이)가
# 바뀌면 깨진다. 링크에 변수를 넣을 수 없으므로 "따라가기" 는 멱등 재설치가 담당한다.
# 소우주(복사 설치)에는 링크가 없으므로 아무것도 하지 않는다.
#
# 출력 형식: [factory-link WARN] …  (테스트가 이 접두어를 고정)

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

broken=()
for kind in skills agents rules; do
  [[ -d ".claude/$kind" ]] || continue
  for entry in ".claude/$kind"/*; do
    [[ -L "$entry" ]] || continue
    [[ -e "$entry" ]] || broken+=("$entry -> $(readlink "$entry")")
  done
done

[[ ${#broken[@]} -gt 0 ]] || exit 0

{
  echo "[factory-link WARN] 공장 설치 링크 ${#broken[@]}개가 깨졌습니다 (저장소 구조가 바뀌었거나 대상이 사라짐):"
  for b in "${broken[@]}"; do echo "  $b"; done
  echo "  → 재설치로 링크를 다시 만드십시오: bash setup.sh --update-all  (또는 bash project-claude.sh <이 저장소> <프리셋…>)"
  echo "  근거: docs/hermes-universe/design/world/copy-install.md §6"
} >&2
exit 0
