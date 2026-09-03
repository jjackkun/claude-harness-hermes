#!/usr/bin/env bash
# R-mut 주간 트리거 검증 — 주기 판정·대상 선정·결과 보고를 단언한다.
#
# 실행: bash tests/mutation-trigger-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-sessionstart-mutation-probe.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# 가짜 프로젝트: 즉시 끝나는 probe 스텁을 두어 실제 변이 실행(수십 초)을 피한다.
# 검증 대상은 probe 자체가 아니라 **트리거 로직**이다.
setup() {
  local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d/scripts" "$d/assets/hooks" "$d/tests" "$d/.harness"
  cat > "$d/scripts/mutation-probe.py" <<'PY'
import sys
print("변이 4개 / 잡힘 3개 / 생존 1개 — 변이 점수 75.0%")
print("  " + " ".join(sys.argv[1:]))
PY
  printf 'x = 1\n' > "$d/assets/hooks/sample_mod.py"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/tests/sample-mod-test.sh"
  printf 'x = 1\n' > "$d/assets/hooks/no_pair.py"   # 짝 테스트 없음
  echo "$d"
}

run() { (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1); }

echo "== 주기 판정 =="

P=$(setup fresh)
OUT=$(run "$P")
assert "상태 파일이 없으면 실행한다" "1" "$(grep -c '변이 점검 시작' <<< "$OUT")"

OUT=$(run "$P")
assert "방금 돌았으면 침묵한다" "0" "$(grep -c '변이 점검 시작' <<< "$OUT")"

P=$(setup stale)
echo "$(( $(date +%s) - 8 * 86400 )) 0" > "$P/.harness/mutation-last-run"
OUT=$(run "$P")
assert "8일 경과면 실행한다" "1" "$(grep -c '변이 점검 시작' <<< "$OUT")"

P=$(setup recent)
echo "$(( $(date +%s) - 86400 )) 0" > "$P/.harness/mutation-last-run"
OUT=$(run "$P")
assert "1일 경과면 침묵한다" "0" "$(grep -c '변이 점검 시작' <<< "$OUT")"

echo "== 대상 선정 =="

P=$(setup pick)
OUT=$(run "$P")
assert "짝 테스트가 있는 파일만 대상" "1" "$(grep -c 'sample_mod.py' <<< "$OUT")"
assert "짝 테스트가 없는 파일은 제외 (전부 생존은 R-cov 관할)" "0" \
  "$(grep -c 'no_pair.py' <<< "$OUT")"

echo "== 1회 1개 상한 =="

P=$(setup one)
OUT=$(run "$P")
assert "한 번에 대상 1개만" "1" "$(grep -c '대상: ' <<< "$OUT")"

echo "== 결과 보고 =="

P=$(setup report)
OUT=$(run "$P")
# 백그라운드 완료 대기 — 스텁이라 즉시 끝난다.
for _ in $(seq 20); do [[ -s "$P/.harness/mutation-report.txt" ]] && break; sleep 0.1; done
assert "결과가 리포트 파일에 쌓인다" "1" \
  "$([[ -s "$P/.harness/mutation-report.txt" ]] && echo 1 || echo 0)"

echo "$(( $(date +%s) - 8 * 86400 )) 0" > "$P/.harness/mutation-last-run"
OUT2=$(run "$P")
assert "다음 세션이 지난 결과를 보고한다" "1" "$(grep -c '변이 점검 결과' <<< "$OUT2")"
assert "생존 변이 수치가 보고에 포함된다" "1" "$(grep -c '생존 1개' <<< "$OUT2")"

OUT3=$(run "$P")
assert "보고한 결과는 지워져 반복 보고되지 않는다" "0" "$(grep -c '변이 점검 결과' <<< "$OUT3")"

echo "== 안전 =="

P=$(setup noprobe); rm -f "$P/scripts/mutation-probe.py"
rc=0; run "$P" >/dev/null 2>&1 || rc=$?
assert "probe 가 없으면 조용히 통과 (세션을 막지 않는다)" "0" "$rc"

echo
echo "통과 $PASS / 실패 $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
