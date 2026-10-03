#!/usr/bin/env bash
# 스킬 주입 한 줄 — 머리말 블록 스칼라를 펼치고, SKILL.md 는 폴더 이름을 이름표로 (계획 2026-10-03-prompt-audit-fixes 목표 1).
#
#   1 한 줄 description → 그대로
#   2 description: |  (여러 줄) → 한 줄로 펼친 본문, "|" 한 글자가 아니다
#   3 description: >- (접힘) → 한 줄로 펼친 본문
#   4 이름표: SKILL.md → 폴더 이름 · 그 밖의 파일 이름은 그대로
#
# 실행: bash tests/hermes-skill-render-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
inject() {   # $1 = 이름, $2 = 경로
  python3 -c "import sys; sys.path.insert(0, sys.argv[1]); from hermes_skill_render import inject_text; print(inject_text(sys.argv[2], sys.argv[3]))" \
    "$REPO_ROOT/scripts" "$1" "$2"
}

mkdir -p "$T/one" "$T/lit" "$T/fold"
printf -- '---\nname: one\ndescription: 한 줄 설명이다.\n---\n본문\n' > "$T/one/SKILL.md"
printf -- '---\nname: lit\ndescription: |\n  첫 줄 설명.\n  둘째 줄 설명.\nmetadata: x\n---\n본문\n' > "$T/lit/SKILL.md"
printf -- '---\nname: fold\ndescription: >-\n  접힌 첫 줄\n  접힌 둘째 줄\n---\n본문\n' > "$T/fold/SKILL.md"
printf -- '---\ndescription: 평범한 파일 스킬.\n---\n' > "$T/plain-rule.md"
mkdir -p "$T/quoted" "$T/strip"
printf -- '---\nname: quoted\ndescription: "따옴표 설명"\n---\n' > "$T/quoted/SKILL.md"
printf -- '---\nname: strip\ndescription: |-\n    네 칸 들여쓴 줄\n\n    빈 줄 뒤 줄\n---\n' > "$T/strip/SKILL.md"

echo "1 한 줄"
assert "한 줄 그대로" "[헤르메스 규칙 — one] 한 줄 설명이다." "$(inject SKILL.md "$T/one/SKILL.md")"
echo "2 블록 스칼라 |"
assert "펼친 한 줄" "[헤르메스 규칙 — lit] 첫 줄 설명. 둘째 줄 설명." "$(inject SKILL.md "$T/lit/SKILL.md")"
echo "3 블록 스칼라 >-"
assert "펼친 한 줄" "[헤르메스 규칙 — fold] 접힌 첫 줄 접힌 둘째 줄" "$(inject SKILL.md "$T/fold/SKILL.md")"
echo "3b 따옴표 한 줄 · |- 와 빈 줄"
assert "따옴표 벗김(회귀)" "[헤르메스 규칙 — quoted] 따옴표 설명" "$(inject SKILL.md "$T/quoted/SKILL.md")"
assert "|- 빈 줄 건너 이어 붙임" "[헤르메스 규칙 — strip] 네 칸 들여쓴 줄 빈 줄 뒤 줄" "$(inject SKILL.md "$T/strip/SKILL.md")"
echo "4 이름표"
assert "SKILL.md 아닌 파일은 이름 그대로" "[헤르메스 규칙 — plain-rule.md] 평범한 파일 스킬." "$(inject plain-rule.md "$T/plain-rule.md")"

echo
echo "결과: $PASS 통과 / $FAIL 실패"
(( FAIL == 0 ))
