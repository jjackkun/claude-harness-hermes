#!/usr/bin/env bash
# CLAUDE.md / AGENTS.md 목차의 스킬 줄 단위 테스트.
#
# 왜 필요한가: 종전 목차는 스킬을 "특별·대형 작업 시 직접 호출"로 소개하면서
# 이름만 나열했다. 그 문틀은 스킬 자신이 frontmatter 에 적어 둔 발동 조건
# (예: structured-file-layout — "before any code is written")보다 좁고, 매 세션
# 컨텍스트에 들어가는 CLAUDE.md 쪽이 이긴다. 실제로 파일 대여섯 개짜리 작업에서
# 스킬이 호출되지 않는 위반이 발생했다.
# 설계: docs/superpowers/specs/2026-08-21-skill-invocation-gate-design.md §3.1–3.2
#
# 실행: bash tests/claude-md-skill-index-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
assert_contains() {
  local desc="$1" needle="$2" hay="$3"
  [[ "$hay" == *"$needle"* ]] && ok "$desc" || { bad "$desc"; echo "      찾는 문자열: $needle"; }
}
assert_not_contains() {
  local desc="$1" needle="$2" hay="$3"
  [[ "$hay" != *"$needle"* ]] && ok "$desc" || bad "$desc"
}

# ── 픽스처: 발동 조건 보존·한글 절단·description 결손을 각각 대표하는 스킬 4종 ──
mk_skill() {  # mk_skill <name> [description]
  mkdir -p "$TMP/assets/skills/$1"
  if [[ $# -ge 2 ]]; then
    printf -- '---\nname: %s\ndescription: %s\n---\n\n# %s\n' "$1" "$2" "$1" > "$TMP/assets/skills/$1/SKILL.md"
  else
    printf -- '---\nname: %s\n---\n\n# %s\n' "$1" "$1" > "$TMP/assets/skills/$1/SKILL.md"
  fi
}

# 관측된 최장 발동 조건 절(98자)을 그대로 쓴다 — 상한값이 이것을 자르면 회귀다.
TRIGGER='Use when creating new files, planning features, or writing exec-plans — before any code is written'
mk_skill structured-file-layout "$TRIGGER, to ensure each file has a single responsibility and folders are organized by domain"
mk_skill korean-long '반복되는 결함·리뷰 지적·경계 위반을 설계 문서의 규칙으로 승격하고, 대응하는 검사 스크립트와 테스트까지 함께 배선한다. 승격되지 않은 지적은 같은 형태로 다시 돌아온다는 것이 이 스킬의 전제다.'
mk_skill no-desc
mkdir -p "$TMP/assets/skills/ghost"   # SKILL.md 자체가 없는 스킬

ASSETS_DIR="$TMP/assets"
SKILLS=(structured-file-layout korean-long no-desc ghost)
RULES=(); AGENTS=()
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/claude_md_gen.sh"

OUT=$(_managed_block_preamble claude)

echo "▶ 문틀 (§3.1)"
assert_not_contains '"특별·대형 작업 시" 문구가 사라졌다' '특별·대형' "$OUT"
assert_not_contains '크기 기준으로 호출을 좁히지 않는다' '대형 작업' "$OUT"

echo "▶ 발동 조건 게재 (§3.2)"
assert_contains '스킬 이름 옆에 발동 조건이 실린다' 'structured-file-layout — Use when creating new files' "$OUT"
assert_contains '관측된 최장 발동 조건 절이 절단되지 않는다' "$TRIGGER" "$OUT"
assert_contains 'description 없는 스킬은 이름만 남는다' '- no-desc' "$OUT"
assert_contains 'SKILL.md 가 없는 스킬도 이름은 남는다' '- ghost' "$OUT"
assert_not_contains 'description 없는 스킬에 빈 구분자가 붙지 않는다' 'no-desc — ' "$OUT"

echo "▶ 절단 안전성"
assert_contains '상한 초과분은 생략 부호로 표시된다' '…' "$OUT"
if printf '%s' "$OUT" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
  ok '한글 절단이 UTF-8 문자를 반토막 내지 않는다'
else
  bad '한글 절단이 UTF-8 문자를 반토막 내지 않는다'
fi
LONGEST=$(printf '%s\n' "$OUT" | grep -- ' — ' | awk '{print length($0)}' | sort -rn | head -1)
if [[ ${LONGEST:-0} -le 160 ]]; then
  ok "가장 긴 스킬 줄이 상한 안에 있다 (${LONGEST}자)"
else
  bad "가장 긴 스킬 줄이 상한을 넘었다 (${LONGEST}자)"
fi

echo "▶ Codex 경로 공유"
OUT_CODEX=$(_managed_block_preamble codex)
assert_contains 'codex 타깃은 .codex/skills/ 를 가리킨다' '.codex/skills/' "$OUT_CODEX"
assert_contains 'codex 목차에도 발동 조건이 실린다' 'structured-file-layout — Use when' "$OUT_CODEX"

echo "▶ 스킬이 하나도 없을 때"
SKILLS=()
OUT_EMPTY=$(_managed_block_preamble claude)
assert_not_contains '스킬 절이 통째로 생략된다' '.claude/skills/' "$OUT_EMPTY"

echo
echo "통과 $PASS / 실패 $FAIL"
[[ $FAIL -eq 0 ]]
