#!/usr/bin/env bash
# run-all.sh 고아 테스트 검사 검증 (backlog run-all-orphan-test-guard → 계획 2026-09-18-run-all-orphan-guard).
#
#   - tests/ 의 *-test.sh · *smoke*.sh 가 러너 목록에 없으면 run-all 이 실패한다(조용한 건너뜀 금지)
#   - 목록에 있는데 파일이 없어도 실패한다
#   - SKIP_TESTS 에 명시한 이름은 고아가 아니다(침묵이 아니라 명시로 뺀다)
#   - 실 저장소: 고아 0 · 결손 0
#   - 검사 자체 검증: 가짜 고아를 심으면 빨강 (통과만 보는 검증 금지)
#
# 실행: bash tests/run-all-orphan-guard-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "[1] 실 저장소 — 고아·결손 0"
OUT="$(bash "$REPO_ROOT/tests/run-all.sh" --check-orphans 2>&1)"; RC=$?
assert "check-orphans rc 0" "0" "$RC"
assert "고아·결손 보고 없음" "0" "$(grep -c '✗' <<<"$OUT")"

echo "[2] 가짜 고아 → 빨강"
mkdir -p "$T/tests"; cp "$REPO_ROOT"/tests/*.sh "$T/tests/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/tests/zzz-orphan-test.sh"
OUT2="$(bash "$T/tests/run-all.sh" --check-orphans 2>&1)"; RC2=$?
assert "고아가 있으면 rc 1" "1" "$RC2"
assert "고아 이름이 보고에" "1" "$(grep -c 'zzz-orphan-test.sh' <<<"$OUT2")"
assert "수정 지침(run-all 목록 또는 SKIP_TESTS)" "1" "$(grep -c 'SKIP_TESTS' <<<"$OUT2")"
assert "smoke 이름도 잡는다" "1" "$(printf '#!/usr/bin/env bash\nexit 0\n' > "$T/tests/zzz-smoke.sh"; bash "$T/tests/run-all.sh" --check-orphans 2>&1 | grep -c 'zzz-smoke.sh')"
rm -f "$T/tests/zzz-smoke.sh"

echo "[3] 명시 스킵은 고아가 아니다"
OUT3="$(SKIP_TESTS=zzz-orphan-test.sh bash "$T/tests/run-all.sh" --check-orphans 2>&1)"; RC3=$?
assert "SKIP_TESTS 에 적으면 rc 0" "0" "$RC3"

echo "[4] 목록에 있는데 파일이 없으면 빨강"
rm -f "$T/tests/zzz-orphan-test.sh" "$T/tests/hermes-roster-test.sh"
OUT4="$(bash "$T/tests/run-all.sh" --check-orphans 2>&1)"; RC4=$?
assert "결손 rc 1" "1" "$RC4"
assert "결손 이름이 보고에" "1" "$(grep -c 'hermes-roster-test.sh' <<<"$OUT4")"

echo "[5] 전체 실행 경로에서도 검사가 돈다(첫 단계)"
assert "run-all 본문에 orphan 단계 호출" "1" "$(grep -c 'run_step "고아 테스트 검사" orphan_test_check' "$REPO_ROOT/tests/run-all.sh")"

echo
echo "run-all-orphan-guard: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
