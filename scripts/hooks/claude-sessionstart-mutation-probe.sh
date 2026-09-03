#!/usr/bin/env bash
# SessionStart hook — 주 1회 R-mut 변이 점검을 돌리고 생존 변이를 알린다.
#
# 근거: docs/design-docs/core-beliefs.md#r-mut
#   "생존 변이 목록을 **테스트를 추가할 지점** 목록으로 쓴다."
#   그런데 실행 트리거가 없어 수동 실행뿐이었고, 목록이 갱신되지 않았다.
#
# 왜 인라인으로 돌리지 않는가:
#   변이 1회 실행이 수십 초다(실측 2026-09-03: gate_event.py 22변이에 ~40초).
#   SessionStart 훅은 세션 시작을 막으므로 그 자리에서 기다리면 매주 한 번
#   세션이 40초 멈춘다 — 사람이 훅을 끈다. 백그라운드로 띄우고 **결과는 다음 세션에** 알린다.
#
# 왜 1회 1개인가: 전수 실행은 수십 분이다(core-beliefs #r-mut). 대상을 돌아가며 하나씩 본다.
#
# 상태: .harness/mutation-last-run  — "<epoch> <다음 대상 인덱스>"
#       .harness/mutation-report.txt — 백그라운드 실행 결과 (다음 세션에 1회 보고 후 삭제)

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

PROBE="scripts/mutation-probe.py"
STATE=".harness/mutation-last-run"
REPORT=".harness/mutation-report.txt"
INTERVAL_DAYS="${MUTATION_PROBE_INTERVAL_DAYS:-7}"

command -v python3 >/dev/null 2>&1 || exit 0
[[ -f "$PROBE" ]] || exit 0

# ── 1. 지난 실행 결과가 있으면 먼저 보고하고 지운다 ──────────────────────────
if [[ -s "$REPORT" ]]; then
  echo ""
  echo "--- [R-mut 주간 변이 점검 결과] ---"
  head -12 "$REPORT"
  echo "  → 생존 변이는 그 경로를 검증하는 단언이 없다는 뜻입니다."
  echo "  근거: docs/design-docs/core-beliefs.md#r-mut"
  rm -f "$REPORT"
fi

# ── 2. 주기 판정 ────────────────────────────────────────────────────────────
NOW=$(date +%s)
LAST=0
IDX=0
if [[ -f "$STATE" ]]; then
  read -r LAST IDX < "$STATE" 2>/dev/null || true
  [[ "$LAST" =~ ^[0-9]+$ ]] || LAST=0
  [[ "$IDX" =~ ^[0-9]+$ ]] || IDX=0
fi
if (( NOW - LAST < INTERVAL_DAYS * 86400 )); then
  exit 0
fi

# ── 3. 대상 선정 — 이름 규칙으로 짝 테스트가 있는 파이썬만 ──────────────────
# 짝이 없는 파일에 변이를 걸면 "전부 생존" 이 나오는데, 그것은 테스트가 약한 것이
# 아니라 아예 없는 것이다. R-cov 의 관할이지 R-mut 의 신호가 아니다.
TARGETS=()
while IFS= read -r f; do
  stem="$(basename "$f" .py)"
  cand="tests/${stem//_/-}-test.sh"
  [[ -f "$cand" ]] && TARGETS+=("$f|$cand")
done < <(ls assets/hooks/*.py scripts/*.py 2>/dev/null)

(( ${#TARGETS[@]} > 0 )) || exit 0

PICK="${TARGETS[$(( IDX % ${#TARGETS[@]} ))]}"
TARGET="${PICK%%|*}"
TEST="${PICK##*|}"

mkdir -p .harness 2>/dev/null || exit 0
echo "$NOW $(( (IDX + 1) % ${#TARGETS[@]} ))" > "$STATE"

# ── 4. 백그라운드 실행 ──────────────────────────────────────────────────────
# setsid 로 세션에서 떼어낸다 — 훅이 끝나며 프로세스 그룹이 정리돼도 살아남아야 한다.
RUNNER="setsid"
command -v setsid >/dev/null 2>&1 || RUNNER="nohup"
$RUNNER timeout 900 python3 "$PROBE" --target "$TARGET" --test "$TEST" \
  > "$REPORT" 2>&1 < /dev/null &

echo ""
echo "--- [R-mut 주간 변이 점검 시작] ---"
echo "  대상: $TARGET (테스트: $TEST)"
echo "  백그라운드로 실행합니다 — 결과는 다음 세션 시작 시 보고됩니다."

exit 0
