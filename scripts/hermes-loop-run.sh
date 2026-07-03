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
