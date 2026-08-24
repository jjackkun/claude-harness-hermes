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
echo "== 4. 배치 조회 (list-complete / list-retro-empty) =="
# 파일마다 python 을 새로 띄우면 completed/ 가 148개인 저장소에서 2.6초가 걸린다
# (2026-08-13 실측). 세션 시작 훅이 동기로 부르기엔 길어 배치 모드를 둔다.
# 경로 열거는 여전히 bash 몫이다 — 파이썬은 넘겨받은 경로의 마크다운만 읽는다.

OUT=$(python3 "$MOD" list-complete "$TMP/all-done.md" "$TMP/partial.md" "$TMP/upper.md" 2>/dev/null)
assert "완료된 것만 출력 (2건)" "2" "$(echo "$OUT" | grep -c '^')"
echo "$OUT" | grep -q "partial.md"
assert "미완료는 제외" "1" "$?"

OUT=$(python3 "$MOD" list-retro-empty "$TMP/retro-blank.md" "$TMP/retro-one.md" "$TMP/retro-none.md" 2>/dev/null)
assert "회고 빈 것만 출력 (2건)" "2" "$(echo "$OUT" | grep -c '^')"
echo "$OUT" | grep -q "retro-one.md"
assert "회고 채운 것은 제외" "1" "$?"

OUT=$(python3 "$MOD" list-complete "$TMP/all-done.md" "$TMP/template.md" 2>/dev/null)
echo "$OUT" | grep -q "template.md"
assert "배치에서도 template.md 제외" "1" "$?"

ERR=$(python3 "$MOD" list-complete "$TMP/all-done.md" "$TMP/broken.md" 2>&1 >/dev/null)
assert "판정불가 파일이 섞이면 exit 2" "2" "$(rc list-complete "$TMP/all-done.md" "$TMP/broken.md")"
echo "$ERR" | grep -q "unparsable"
assert "판정불가 경로를 stderr 로 보고" "0" "$?"
OUT=$(python3 "$MOD" list-complete "$TMP/all-done.md" "$TMP/broken.md" 2>/dev/null)
echo "$OUT" | grep -q "all-done.md"
assert "판정불가가 있어도 나머지는 계속 처리" "0" "$?"

assert "빈 인자 목록도 정상 종료" "0" "$(rc list-complete)"

# ── R-acc — §2 목표가 실행 가능한 형태인가 ──────────────────────────────
# 스펙: docs/superpowers/specs/2026-08-24-executable-acceptance-spec-design.md
echo ""
echo "== R-acc-1: 목표에 검증 명령이 붙어 있는가 =="

cat > "$TMP/acc-verified.md" <<'EOF'
# 계획

## 2. 목표 (What — 검증 가능한 형태)

- [ ] 공개 심볼 8개짜리 새 파일 생성이 차단된다
      `bash tests/iface-gate-test.sh`
- [x] 7개짜리는 통과한다
      `bash tests/iface-gate-test.sh`

## 3. 다음
- [ ] 검증 명령 없는 항목이지만 §2 가 아니다
EOF
assert "모든 §2 목표에 명령이 있으면 exit 1(위반 없음)" "1" "$(rc goals-unverified "$TMP/acc-verified.md")"

cat > "$TMP/acc-bare.md" <<'EOF'
# 계획

## 2. 목표 (What — 검증 가능한 형태)

- [ ] 무언가를 잘 되게 한다
- [ ] 이건 명령이 있다
      `bash tests/foo.sh`
EOF
assert "명령 없는 목표가 있으면 exit 0(위반)" "0" "$(rc goals-unverified "$TMP/acc-bare.md")"
OUT=$(python3 "$MOD" goals-unverified "$TMP/acc-bare.md" 2>/dev/null)
echo "$OUT" | grep -q "무언가를 잘 되게 한다"
assert "명령 없는 목표만 stdout 에 나온다" "0" "$?"
echo "$OUT" | grep -q "이건 명령이 있다"
assert "명령 있는 목표는 나오지 않는다" "1" "$?"

cat > "$TMP/acc-nosection.md" <<'EOF'
# 계획

## 3. 다음
- [ ] 명령 없음
EOF
assert "§2 가 없으면 판정불가(exit 2)" "2" "$(rc goals-unverified "$TMP/acc-nosection.md")"

cat > "$TMP/acc-empty.md" <<'EOF'
# 계획

## 2. 목표 (What — 검증 가능한 형태)

아직 항목 없음.

## 3. 다음
EOF
assert "§2 에 목표 항목이 0개면 위반 아님" "1" "$(rc goals-unverified "$TMP/acc-empty.md")"

cat > "$TMP/acc-fallback.md" <<'EOF'
# 계획

## 목표

- [ ] 명령 없음
EOF
assert "번호 없는 '목표' 제목도 §2 로 본다" "0" "$(rc goals-unverified "$TMP/acc-fallback.md")"

assert "template.md 는 판정 대상 밖" "1" "$(rc goals-unverified "$REPO_ROOT/assets/docs-templates/docs/exec-plans/template.md")"

echo ""
echo "== R-acc-2: §2 목표가 미완인 채 완료 처리되는가 =="

cat > "$TMP/acc-pending.md" <<'EOF'
# 계획

## 2. 목표 (What — 검증 가능한 형태)

- [x] 끝난 목표
      `bash tests/a.sh`
- [ ] 안 끝난 목표
      `bash tests/b.sh`

## 3. 다음
- [ ] §2 가 아닌 미완 항목
EOF
assert "§2 에 미완 목표가 있으면 exit 0(위반)" "0" "$(rc goals-pending "$TMP/acc-pending.md")"
OUT=$(python3 "$MOD" goals-pending "$TMP/acc-pending.md" 2>/dev/null)
echo "$OUT" | grep -q "안 끝난 목표"
assert "미완 목표가 stdout 에 나온다" "0" "$?"
echo "$OUT" | grep -q "§2 가 아닌 미완 항목"
assert "§2 밖의 미완 항목은 세지 않는다" "1" "$?"

cat > "$TMP/acc-alldone.md" <<'EOF'
# 계획

## 2. 목표 (What — 검증 가능한 형태)

- [x] 끝난 목표
      `bash tests/a.sh`
EOF
assert "§2 가 전부 완료면 exit 1(위반 없음)" "1" "$(rc goals-pending "$TMP/acc-alldone.md")"
assert "§2 가 없으면 판정불가(exit 2)" "2" "$(rc goals-pending "$TMP/acc-nosection.md")"

echo ""
echo "== R-acc 회귀: 인터페이스 폭과 복잡도가 늘지 않았는가 =="
# plan_state.py 는 공개 심볼 8개로 이미 R-iface 임계(8)에 있다.
# 새 파서를 공개로 추가하면 폭이 늘어난다 — 비공개로 넣어야 한다.
WIDTH=$(python3 -c "
import ast
t = ast.parse(open('$MOD', encoding='utf-8').read())
print(len([n.name for n in t.body
           if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
           and not n.name.startswith('_')]))")
assert "공개 심볼이 8개를 넘지 않는다" "0" "$([[ "$WIDTH" -le 8 ]] && echo 0 || echo 1)"

# main 복잡도 13 이 .cxbaseline 동결값이다. 서브커맨드를 그냥 더하면 14 가 되어 막힌다.
CXMAIN=$(python3 "$REPO_ROOT/assets/hooks/complexity.py" --report "$MOD" 2>/dev/null \
  | awk '$3 == "main" { print $1 }')
assert "main 복잡도가 기준선(13) 이하" "0" "$([[ "${CXMAIN:-99}" -le 13 ]] && echo 0 || echo 1)"

echo ""
echo "== 결과 =="
echo "  통과: $PASS / 실패: $FAIL"
[[ $FAIL -eq 0 ]]
