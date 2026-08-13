#!/usr/bin/env bash
# exec-plans 편차 탐지 — 주간 문서 가드닝의 판정부.
#
# GitHub Actions 와 GitLab CI 양쪽 워크플로가 이 스크립트 하나를 호출한다.
# 두 벌로 복제하지 않는 이유: 이전 버전은 두 yml 에 인라인으로 복제돼 있었고,
# 템플릿에 존재하지 않는 `status:` 필드를 grep 해 한 번도 발동하지 않았다.
# 판정 규칙은 한 벌만 둔다.
#
# 사용: doc-gardening-drift.sh <report-path>
#   편차 항목을 report 에 append 한다. 종료코드는 항상 0 —
#   탐지에 실패해도 그 사실을 리포트에 적을 뿐 워크플로를 중단시키지 않는다.
#
# 실행 위치: 저장소 루트.

set -uo pipefail

REPORT="${1:?usage: doc-gardening-drift.sh <report-path>}"
PLAN_STATE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/plan_state.py"

if [[ ! -f "$PLAN_STATE" ]] || ! command -v python3 >/dev/null 2>&1; then
  # 조용히 건너뛰지 않는다 — 이 검사가 죽어 있던 것을 아무도 몰랐던 이유가 그것이다.
  echo "- [plan-check-skipped] \`plan_state.py\` 또는 python3 없음 — exec-plans 점검을 건너뜀" >> "$REPORT"
  exit 0
fi

# active/ — 완료 상태인데 옮겨지지 않은 계획
if [[ -d docs/exec-plans/active ]]; then
  while IFS= read -r plan; do
    [[ -n "$plan" ]] || continue
    rc=0; python3 "$PLAN_STATE" is-complete "$plan" || rc=$?
    case $rc in
      0) echo "- [plan-graduation] \`$plan\` 완료 상태 → \`docs/exec-plans/completed/\` 로 이동 고려" >> "$REPORT" ;;
      2) echo "- [plan-unparsable] \`$plan\` 판정 불가 — 마크다운 형식 확인" >> "$REPORT" ;;
    esac
  done < <(find docs/exec-plans/active -maxdepth 1 -name '*.md' ! -name 'template.md' -type f 2>/dev/null | sort)
fi

# completed/ — 회고 없이 들어간 계획. pre-commit 의 R-retro 는 앞으로의 이동만 잡으므로
# 이미 쌓인 것은 여기서 수거한다. 상태를 저장해 "새로 생긴 것만" 보고하지 않는다 —
# 상태 파일이 또 하나의 동기화 지점이 되고, 일괄 백필은 사람의 결정 사항이다.
if [[ -d docs/exec-plans/completed ]]; then
  while IFS= read -r plan; do
    [[ -n "$plan" ]] || continue
    rc=0; python3 "$PLAN_STATE" retro-empty "$plan" || rc=$?
    case $rc in
      0) echo "- [plan-noretro] \`$plan\` 회고(§8) 없이 completed/ 에 있음" >> "$REPORT" ;;
      2) echo "- [plan-unparsable] \`$plan\` 판정 불가 — 마크다운 형식 확인" >> "$REPORT" ;;
    esac
  done < <(find docs/exec-plans/completed -maxdepth 1 -name '*.md' ! -name 'template.md' -type f 2>/dev/null | sort)
fi

exit 0
