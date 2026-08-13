#!/usr/bin/env bash
# SessionStart hook — exec-plans 편차 주기 점검 (기본 7일).
#
# 왜 CI 가 아니라 여기인가:
#   가드닝은 원래 주간 CI 워크플로였다. 그런데 2026-08-13 조사에서 등록된 9개 GitLab
#   프로젝트 전부에 `.gitlab-ci.yml` 이 없어 `.gitlab/doc-gardening.yml` 이 include 된
#   적조차 없음을 확인했다. GitLab 은 스케줄 파이프라인 등록(웹 UI)까지 필요해
#   설치기가 끝까지 배선할 수 없다. 결과적으로 가드닝 축이 어디서도 돌지 않았다.
#   CI 배선 여부와 무관하게 동작하는 경로를 하나 둔다.
#
# 출력: SessionStart 훅의 stdout 은 세션 컨텍스트로 주입된다. 편차가 있을 때만
#   짧게 출력하고, 없으면 아무것도 내지 않는다. 고치는 주체는 에이전트다(제안만).
#
# 비차단: 배치 조회를 쓰므로 154개 파일 저장소에서 0.06초다(2026-08-13 실측).
#   그래도 실패는 전부 삼키고 exit 0 한다 — 세션 시작을 막지 않는다.
#
# 비활성화: HARNESS_DISABLED=1 (전체) 또는 HARNESS_GARDENING_ON_SESSION_START=0
# 간격: HARNESS_GARDENING_THROTTLE_HOURS (기본 168 = 7일)

set -uo pipefail

[[ "${HARNESS_DISABLED:-0}" == "1" ]] && exit 0
[[ "${HARNESS_GARDENING_ON_SESSION_START:-1}" == "0" ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# stdin JSON 은 훅 프로세스 안에서만 읽을 수 있으므로 여기서 먼저 읽는다.
input="$(cat 2>/dev/null || true)"
source_val=""
if command -v jq >/dev/null 2>&1; then
  source_val="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)"
else
  source_val="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("source", "") or "")
except Exception:
    pass
' 2>/dev/null || true)"
fi
case "$source_val" in
  startup|resume|"") ;;
  *) exit 0 ;;
esac

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$project_dir" 2>/dev/null || exit 0
[[ -d docs/exec-plans ]] || exit 0

drift="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/doc-gardening-drift.sh"
[[ -f "$drift" ]] || exit 0

# throttle — 마커 mtime 이 간격 이내면 건너뛴다.
# .git/ 에 둔다: 추적 대상이 아니고, 저장소마다 독립이며, 항상 존재한다.
throttle_hours="${HARNESS_GARDENING_THROTTLE_HOURS:-168}"
marker=".git/.harness-gardening-marker"
[[ -d .git ]] || exit 0
if [[ -f "$marker" ]] && [[ -n "$(find "$marker" -mmin "-$((throttle_hours * 60))" 2>/dev/null)" ]]; then
  exit 0
fi
# 선-touch: 동시 세션이 둘 다 돌지 않게 한다. 실패해도 비차단.
touch "$marker" 2>/dev/null || true

report="$(mktemp 2>/dev/null)" || exit 0
trap 'rm -f "$report"' EXIT
bash "$drift" "$report" >/dev/null 2>&1 || exit 0

count=$(grep -c '^-' "$report" 2>/dev/null || echo 0)
[[ "$count" -gt 0 ]] || exit 0

# 상한을 둔다 — 부채가 쌓인 저장소에서 수십 줄이 매 주기 주입되면 무시당한다.
show="${HARNESS_GARDENING_REPORT_MAX:-10}"
echo ""
echo "--- [Doc Gardening] ---"
echo "exec-plans 편차 $count 건. 차단이 아니라 판단 요청입니다."
head -n "$show" "$report"
[[ "$count" -gt "$show" ]] && echo "  ... 외 $((count - show))건 (전체: bash scripts/hooks/doc-gardening-drift.sh <파일>)"
echo "---"

exit 0
