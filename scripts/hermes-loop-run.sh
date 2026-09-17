#!/usr/bin/env bash
# 헤르메스 루프 헤드리스 래퍼 — 목표 한 줄로 init → nohup 드라이버 백그라운드 기동.
# hermes-cron-run.sh 의 형제 (claude CLI 에 --bg 플래그 없음 → nohup 패턴).
#
# 사용법:
#   hermes-loop-run.sh <project-dir> "<목표>" [init 추가 인자...]
#   hermes-loop-run.sh <project-dir> --resume <loop-id>
#
# 예시:
#   hermes-loop-run.sh ~/proj "테스트 커버리지 80% 달성" --verify "pytest -q"
#   hermes-loop-run.sh ~/proj --resume loop-20260703-101010-a1b2c3

set -uo pipefail

usage() {
  echo "usage: hermes-loop-run.sh <project-dir> \"<목표>\" [init 추가 인자...]" >&2
  echo "       hermes-loop-run.sh <project-dir> --resume <loop-id>" >&2
  exit 1
}

project_dir="${1:-}"
[[ -z "$project_dir" || ! -d "$project_dir" ]] && usage
shift

command -v python3 >/dev/null 2>&1 || { echo "[hermes-loop] python3 없음" >&2; exit 1; }
command -v claude  >/dev/null 2>&1 || { echo "[hermes-loop] claude CLI 없음" >&2; exit 1; }

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
db_path="$project_dir/.hermes/state.db"
[[ ! -f "$db_path" ]] && { echo "[hermes-loop] DB 없음: $db_path (hermes-init.py 먼저 실행)" >&2; exit 1; }

# 이 루프를 시작한 사람. 작업 이력의 requested_by 와 loops.started_by 가 이 값을 쓴다
# (계획 2026-09-15-universe-id-journal 목표 7). 이미 정해져 있으면 존중한다.
if [[ -z "${HERMES_REQUESTED_BY:-}" ]]; then
  _git_user="$(git -C "$project_dir" config user.name 2>/dev/null || true)"
  export HERMES_REQUESTED_BY="${_git_user:+human:$_git_user}"
  export HERMES_REQUESTED_BY="${HERMES_REQUESTED_BY:-system:unknown}"
  export HERMES_HEADLESS=1   # 사람 없는 세션 — 담당 없으면 main 이 수행하고 제안을 남긴다(creation-and-organization.md §5)
fi

# 이 루프의 세션은 main 으로 소환된다 — 토큰을 발급해 환경으로 넘긴다(RV-06, 계획 4 목표 5).
# 발급 실패(pending 파일을 못 만듦)면 소환하지 않고 사람에게 알린다(계획 4 §6).
if [[ -f "$scripts_dir/hermes-summon.py" && -z "${HERMES_SUMMON_NONCE:-}" ]]; then
  if grep -q '"name": *"main"' "$project_dir/.hermes/agents.json" 2>/dev/null; then
    if _issued="$(python3 "$scripts_dir/hermes-summon.py" --project "$project_dir" issue main 2>&1)"; then
      export HERMES_AGENT_ID="${_issued%% *}" HERMES_SUMMON_NONCE="${_issued##* }"
    else
      echo "[hermes-loop] 소환 토큰 발급 실패 — 루프를 시작하지 않습니다: $_issued" >&2; exit 1
    fi
  fi
fi

log_dir="$project_dir/.hermes/logs"
mkdir -p "$log_dir"

if [[ "${1:-}" == "--resume" ]]; then
  loop_id="${2:-}"
  [[ -z "$loop_id" ]] && usage
  action=resume
else
  goal="${1:-}"
  [[ -z "$goal" ]] && usage
  shift
  init_out="$(python3 "$scripts_dir/hermes-loop.py" --project-dir "$project_dir" \
    init --goal "$goal" "$@")" \
    || { echo "[hermes-loop] init 실패" >&2; exit 1; }
  loop_id="$(printf '%s\n' "$init_out" | sed -n 's/^LOOP_ID://p')"
  [[ -z "$loop_id" ]] && { echo "[hermes-loop] LOOP_ID 파싱 실패" >&2; exit 1; }
  action=run
fi

log_file="$log_dir/loop-$loop_id.log"
echo "[hermes-loop] $(date '+%F %T') action=$action id=$loop_id 시작" >>"$log_file"
nohup python3 "$scripts_dir/hermes-loop.py" --project-dir "$project_dir" \
  "$action" "$loop_id" >>"$log_file" 2>&1 &
echo "[hermes-loop] id=$loop_id pid=$! log=$log_file"
echo "[hermes-loop] 상태: python3 $scripts_dir/hermes-loop.py --project-dir $project_dir status $loop_id"
exit 0
