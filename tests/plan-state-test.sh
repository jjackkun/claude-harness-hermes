#!/usr/bin/env bash
# plan_state.py 단위 테스트 — 계획서 마크다운 판정 규칙의 유일한 검증 수단.
#
# 이 저장소는 자기 자신에 하네스를 설치하지 않으므로(설계 §3.9-bis),
# 판정 규칙의 정확성은 이 테스트로만 담보된다.
#
# 실행: bash tests/plan-state-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$REPO_ROOT/assets/hooks/plan_state.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"
    FAIL=$((FAIL+1))
  fi
}

# rc <subcmd> <file> [args...] — 종료코드를 표준출력으로 반환
rc() {
  local r=0
  python3 "$MOD" "$@" >/dev/null 2>&1 || r=$?
  echo "$r"
}

echo "== 1. is-complete =="

cat > "$TMP/all-done.md" << 'EOF'
# 계획

- [x] 항목1
- [x] 항목2
EOF
assert "전부 [x] → 완료(0)" "0" "$(rc is-complete "$TMP/all-done.md")"

cat > "$TMP/upper.md" << 'EOF'
# 계획

- [x] 항목1
- [X] 항목2
EOF
assert "대문자 [X] 혼용도 완료(0)" "0" "$(rc is-complete "$TMP/upper.md")"

cat > "$TMP/partial.md" << 'EOF'
# 계획

- [x] 항목1
- [ ] 항목2
EOF
assert "일부 미완료 → 1" "1" "$(rc is-complete "$TMP/partial.md")"

cat > "$TMP/links.md" << 'EOF'
# 계획

- [testing.md](testing.md) - 커버리지 요건
- [x] 항목1
EOF
assert "링크 불릿은 체크박스로 세지 않음 → 완료(0)" "0" "$(rc is-complete "$TMP/links.md")"

cat > "$TMP/nobox.md" << 'EOF'
# 계획

본문만 있고 체크박스가 없다.
EOF
assert "체크박스 0개 → 1 (위반 아님)" "1" "$(rc is-complete "$TMP/nobox.md")"

assert "존재하지 않는 경로 → 2" "2" "$(rc is-complete "$TMP/nope.md")"

printf '# \xff\xfe\x00bad\n- [x] a\n' > "$TMP/broken.md"
assert "깨진 인코딩 → 2 (1 로 새지 않음)" "2" "$(rc is-complete "$TMP/broken.md")"

assert "알 수 없는 서브커맨드 → 2" "2" "$(rc bogus "$TMP/all-done.md")"

cp "$REPO_ROOT/assets/docs-templates/docs/exec-plans/template.md" "$TMP/template.md"
assert "template.md 는 판정 대상 아님 → 1" "1" "$(rc is-complete "$TMP/template.md")"

echo ""
echo "== 2. retro-empty =="

cat > "$TMP/retro-blank.md" << 'EOF'
# 계획

- [x] 항목1

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
EOF
assert "라벨만 있고 콜론 뒤 공백 → 비었음(0)" "0" "$(rc retro-empty "$TMP/retro-blank.md")"

cat > "$TMP/retro-one.md" << 'EOF'
# 계획

## 8. 회고 (완료 시 작성)

- 잘된 것: 판정 규칙을 한 곳에 모았다
- 잘못된 것:
- 다음 룰 후보:
EOF
assert "세 항목 중 하나만 채워도 통과(1)" "1" "$(rc retro-empty "$TMP/retro-one.md")"

cat > "$TMP/retro-free.md" << 'EOF'
# 계획

## 8. 회고 (완료 시 작성)

라벨을 쓰지 않고 산문으로 적었다.
EOF
assert "라벨 외 실질 텍스트도 채워진 것(1)" "1" "$(rc retro-empty "$TMP/retro-free.md")"

cat > "$TMP/retro-none.md" << 'EOF'
# 계획

- [x] 항목1
EOF
assert "§8 헤딩 자체가 없음 → 비었음(0)" "0" "$(rc retro-empty "$TMP/retro-none.md")"

cat > "$TMP/retro-fallback.md" << 'EOF'
# 계획

## 회고

- 잘된 것: 폴백 헤딩도 인식한다
EOF
assert "번호 없는 '## 회고' 폴백 인식(1)" "1" "$(rc retro-empty "$TMP/retro-fallback.md")"

cat > "$TMP/retro-bounded.md" << 'EOF'
# 계획

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:

## 9. 부록

여기 내용은 §8 이 아니다.
EOF
assert "다음 ## 헤딩에서 섹션이 끊김 → 비었음(0)" "0" "$(rc retro-empty "$TMP/retro-bounded.md")"

assert "template.md 는 판정 대상 아님 → 1" "1" "$(rc retro-empty "$TMP/template.md")"

# 템플릿의 라벨과 모듈 상수가 어긋나면 여기서 잡힌다.
TEMPLATE_SRC="$REPO_ROOT/assets/docs-templates/docs/exec-plans/template.md"
for label in "잘된 것" "잘못된 것" "다음 룰 후보"; do
  grep -q -- "- $label:" "$TEMPLATE_SRC"
  assert "template.md 에 라벨 '$label' 존재 (모듈 상수와 동기)" "0" "$?"
done

echo ""
echo "== 3. pending =="

cat > "$TMP/pending5.md" << 'EOF'
# 계획

- [x] 끝난 것
- [ ] 목표1 — 검증: A
- [ ] 목표2 — 검증: B
- [ ] 목표3 — 검증: C
- [ ] 목표4 — 검증: D
- [ ] 목표5 — 검증: E
EOF

OUT=$(python3 "$MOD" pending "$TMP/pending5.md" 2>/dev/null)
assert "기본 상한 3줄" "3" "$(echo "$OUT" | grep -c '^')"
echo "$OUT" | grep -q "목표1"
assert "첫 미완료 항목 포함" "0" "$?"
echo "$OUT" | grep -q "끝난 것"
assert "완료 항목은 제외" "1" "$?"

OUT=$(python3 "$MOD" pending "$TMP/pending5.md" --max 2 2>/dev/null)
assert "--max 2 → 2줄" "2" "$(echo "$OUT" | grep -c '^')"

assert "pending 정상 종료 0" "0" "$(rc pending "$TMP/pending5.md")"
assert "pending 존재하지 않는 경로 → 2" "2" "$(rc pending "$TMP/nope.md")"

# stdin 소비 금지 — UserPromptSubmit 훅이 while-read 루프 안에서 호출한다.
STDIN_LEFT=$(printf 'line1\nline2\n' | { python3 "$MOD" pending "$TMP/pending5.md" >/dev/null 2>&1; cat; })
assert "stdin 을 소비하지 않음" "line1
line2" "$STDIN_LEFT"

echo ""
echo "== 결과 =="
echo "  통과: $PASS / 실패: $FAIL"
[[ $FAIL -eq 0 ]]
