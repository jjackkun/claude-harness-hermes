#!/usr/bin/env bash
# R-design-cover 검증 (계획 docs/exec-plans/active/2026-09-17-r-design-cover.md 목표 1·2·3).
#
#   - (A) 계획서에 인용되지 않은 결정 ID 를 잡는다 · (B) ID 없는 확정 절 제목을 잡는다
#   - 기준선에 있는 틈은 억제, 계획서에 인용을 더하면 해소, 설계 디렉터리 없으면 rc 2
#   - 실 저장소: 기준선 적용 뒤 새 틈 0(rc 1)
#   - pre-commit 블록: 설계/계획 파일이 스테이징돼 있을 때만 판정, 없으면 skipped
#
# 실행: bash tests/design-cover-gate-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DC="$REPO_ROOT/assets/hooks/design_cover.py"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R/docs/hermes-universe/design/agent" "$R/docs/exec-plans/completed"
cat > "$R/docs/hermes-universe/design/agent/x.md" <<'EOF'
# x 설계
## 1. 인용된 결정 (확정, RV-90)
본문.
## 2. 인용 안 된 결정 (확정, G-91)
본문.
## 3. ID 없는 확정 절 (확정)
본문.
## 4. 표지 없는 절
> ✅ 리뷰 확정 (2026-09-17, V-92) — 인용됨
EOF
printf '# 계획\n- [x] 목표 1 — RV-90 구현. V-92 도.\n' > "$R/docs/exec-plans/completed/2026-09-17-p.md"

echo "[1] 판정기 — (A)·(B) 검출"
OUT="$(python3 "$DC" check --root "$R")"; RC=$?
assert "새 틈 있음 → rc 0" "0" "$RC"
assert "(A) 미인용 ID G-91" "1" "$(printf '%s\n' "$OUT" | grep -c '^id:G-91$')"
assert "(A) 인용된 RV-90·V-92 는 안 잡힘" "0" "$(printf '%s\n' "$OUT" | grep -cE '^id:(RV-90|V-92)$')"
assert "(B) ID 없는 확정 절" "1" "$(printf '%s\n' "$OUT" | grep -c '^heading:docs/hermes-universe/design/agent/x.md:3. ID 없는 확정 절$')"
assert "(B) ID 있는 확정 절은 안 잡힘" "0" "$(printf '%s\n' "$OUT" | grep -c '인용된 결정')"
assert "틈은 정확히 2건" "2" "$(printf '%s\n' "$OUT" | grep -c .)"

echo "[2] 기준선 억제 · 인용으로 해소 · 판정 불가"
python3 "$DC" baseline --root "$R" > "$R/.design-cover-baseline"
python3 "$DC" check --root "$R" >/dev/null; assert "기준선 적용 → rc 1" "1" "$?"
printf '## 5. 새 결정 (확정, K-93)\n' >> "$R/docs/hermes-universe/design/agent/x.md"
OUT2="$(python3 "$DC" check --root "$R")"; assert "기준선 뒤 새 ID 는 잡힘" "id:K-93" "$OUT2"
printf -- '- 목표 2 — K-93 구현.\n' >> "$R/docs/exec-plans/completed/2026-09-17-p.md"
python3 "$DC" check --root "$R" >/dev/null; assert "계획서 인용 추가 → 해소 rc 1" "1" "$?"
mkdir -p "$T/empty"; python3 "$DC" check --root "$T/empty" >/dev/null 2>&1; assert "설계 디렉터리 없음 → rc 2" "2" "$?"

echo "[3] 실 저장소 — 기준선 뒤 새 틈 0"
python3 "$DC" check --root "$REPO_ROOT" > "$T/real.out"; assert "실 저장소 rc 1" "1" "$?"
assert "실 저장소 출력 0줄" "0" "$(grep -c . "$T/real.out")"
assert "기준선은 판정기 출력과 동기" "0" "$(diff <(python3 "$DC" baseline --root "$REPO_ROOT" | grep -v '^#') <(grep -v '^#' "$REPO_ROOT/.design-cover-baseline") | wc -l)"

echo "[4] pre-commit 블록 — 선언·근거 링크"
PC="$REPO_ROOT/assets/hooks/pre-commit.sh"
assert "GATE 선언 있음" "1" "$(grep -c '^# GATE: R-design-cover warn' "$PC")"
assert "근거 앵커가 core-beliefs 에 존재" "1" "$(grep -c '{#r-design-cover}' "$REPO_ROOT/docs/design-docs/core-beliefs.md")"
assert "설계 디렉터리 없으면 skipped 로 기록" "1" "$(grep -c 'skipped precommit "" "설계 디렉터리 없음"' "$PC")"

echo
echo "design-cover-gate: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
