#!/usr/bin/env bash
# 헤르메스 cron 래퍼 — crontab 한 줄 호출용 (H1/H2).
#
# crontab 은 백슬래시 멀티라인을 지원하지 않고, claude CLI 에는 --bg 플래그가 없다.
# 이 래퍼가 매니저 프롬프트 조립 → nohup claude -p 백그라운드 실행을 한 번에 처리한다.
#
# 사용법:
#   hermes-cron-run.sh <project-dir> <start|check|end> [projects-csv]
#
# 예시 (crontab):
#   0 9 * * 1-5 /path/to/claude-harness-hermes/scripts/hermes-cron-run.sh /path/to/project start proj-a,proj-b

set -uo pipefail

usage() {
  echo "usage: hermes-cron-run.sh <project-dir> <start|check|end> [projects-csv]" >&2
  exit 1
}

project_dir="${1:-}"
action="${2:-}"
projects="${3:-}"

[[ -z "$project_dir" || -z "$action" ]] && usage
[[ "$action" != "start" && "$action" != "check" && "$action" != "end" ]] && usage
[[ ! -d "$project_dir" ]] && { echo "[hermes-cron] 프로젝트 디렉터리 없음: $project_dir" >&2; exit 1; }
[[ "$action" == "start" && -z "$projects" ]] && { echo "[hermes-cron] start 액션에는 projects-csv 가 필요합니다" >&2; usage; }

command -v python3 >/dev/null 2>&1 || { echo "[hermes-cron] python3 없음" >&2; exit 1; }
command -v claude  >/dev/null 2>&1 || { echo "[hermes-cron] claude CLI 없음 (cron PATH 확인)" >&2; exit 1; }

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
db_path="$project_dir/.hermes/state.db"
[[ ! -f "$db_path" ]] && { echo "[hermes-cron] DB 없음: $db_path (hermes-init.py 먼저 실행)" >&2; exit 1; }

# cron 이 시작한 일은 사람이 지시한 것이 아니다 (계획 2 목표 7).
export HERMES_REQUESTED_BY="${HERMES_REQUESTED_BY:-system:hermes-cron}"
export HERMES_ACTOR="${HERMES_ACTOR:-system:hermes-cron}"
export HERMES_HEADLESS=1   # 사람 없는 세션 — 담당 없으면 main 이 수행하고 제안을 남긴다(creation-and-organization.md §5)
# cron 세션도 main 으로 소환된다(토큰 없이 도는 세션을 남기지 않는다, 계획 4 목표 5).
if [[ -f "$scripts_dir/hermes-summon.py" && -z "${HERMES_SUMMON_NONCE:-}" ]]; then
  if grep -q '"name": *"main"' "$project_dir/.hermes/agents.json" 2>/dev/null; then
    if _issued="$(python3 "$scripts_dir/hermes-summon.py" --project "$project_dir" issue main 2>&1)"; then
      export HERMES_AGENT_ID="${_issued%% *}" HERMES_SUMMON_NONCE="${_issued##* }"
    else
      echo "[hermes-cron] 소환 토큰 발급 실패 — 실행하지 않습니다: $_issued" >&2; exit 1
    fi
  fi
fi

log_dir="$project_dir/.hermes/logs"
mkdir -p "$log_dir"
log_file="$log_dir/cron-$action-$(date +%Y%m%d).log"

prompt_file="$(mktemp /tmp/hermes-cron-prompt-XXXXXX)"
trap 'rm -f "$prompt_file"' EXIT

# 1. 매니저 프롬프트 조립
manager_args=(--db "$db_path" --action "$action" --output "$prompt_file")
[[ "$action" == "start" ]] && manager_args+=(--projects "$projects")

if ! python3 "$scripts_dir/hermes-manager.py" "${manager_args[@]}" >>"$log_file" 2>&1; then
  echo "[hermes-cron] 프롬프트 조립 실패 — $log_file 확인" >&2
  exit 1
fi

# 2. claude -p 백그라운드 실행 (claude --bg 는 존재하지 않는 플래그)
prompt="$(cat "$prompt_file")"
echo "[hermes-cron] $(date '+%F %T') action=$action 매니저 에이전트 시작" >>"$log_file"
cd "$project_dir" || exit 1
nohup claude -p "$prompt" >>"$log_file" 2>&1 &
manager_pid=$!
echo "[hermes-cron] manager pid=$manager_pid log=$log_file"
exit 0
