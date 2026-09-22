#!/usr/bin/env bash
# SessionStart 훅 — 소우주 대시보드(.hermes/dashboards/dashboard.html)를 하루 1회 백그라운드로 갱신한다 (계획 2026-09-18-hermes-dashboard 목표 7).
# 공장(.installed-projects 가 있는 곳)에서는 우주 대시보드(.hermes/dashboards/universe-dashboard.html)도 같은 실행에서 갱신한다 (계획 2026-09-22-universe-dashboard-auto).
# 드림 훅과 같은 마커 방식: source 가 startup/resume 이고, 마커(.hermes/dashboard-last-run) mtime 이 throttle 시간 밖일 때만.
# 세션 시작 지연 0 — 생성은 nohup 백그라운드. stdout 은 비운다(컨텍스트 오염 방지). 어떤 경우에도 exit 0.
# 비활성화: HERMES_DISABLED=1 · HERMES_DASHBOARD_ON_SESSION_START=0 / 간격: HERMES_DASHBOARD_THROTTLE_HOURS(기본 24)
set -uo pipefail
[[ "${HERMES_DISABLED:-0}" == "1" ]] && exit 0
[[ "${HERMES_DASHBOARD_ON_SESSION_START:-1}" == "0" ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null || true)"
source_val="$(printf '%s' "$input" | python3 -c 'import json,sys
try: print((json.load(sys.stdin) or {}).get("source", "") or "")
except Exception: print("")' 2>/dev/null)"

project_dir="${CLAUDE_PROJECT_DIR:-${HERMES_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}}"
log="$project_dir/.hermes/hooks.log"
_log() { mkdir -p "$(dirname "$log")"; printf '[dashboard] %s source=%s %s\n' "$(date -Is)" "$source_val" "$*" >>"$log" 2>/dev/null || true; }

case "$source_val" in
  startup|resume) ;;
  *) _log "action=skip:source"; exit 0 ;;
esac
[[ -f "$project_dir/.hermes/state.db" ]] || { _log "action=skip:no-db"; exit 0; }

throttle_hours="${HERMES_DASHBOARD_THROTTLE_HOURS:-24}"
marker="$project_dir/.hermes/dashboard-last-run"
if [[ -f "$marker" ]] && [[ -n "$(find "$marker" -mmin "-$((throttle_hours * 60))" 2>/dev/null)" ]]; then
  _log "action=skip:throttle(${throttle_hours}h)"; exit 0
fi

cli="$project_dir/scripts/hermes-dashboard.py"
[[ -f "$cli" ]] || cli="$(cd "$(dirname "$0")/../../scripts" 2>/dev/null && pwd)/hermes-dashboard.py"
[[ -f "$cli" ]] || { _log "action=skip:no-cli"; exit 0; }

# 소우주 한 장 + (공장일 때만) 우주 한 장. 공장 판별은 우주 CLI 가 실제로 읽는
# 레지스트리(.installed-projects) 존재로 한다 — 판별과 입력이 어긋날 수 없다.
_render() {
  python3 "$cli" --project-dir "$project_dir" >>"$log" 2>&1 || _log "action=failed kind=project rc=$?"
  [[ -f "$project_dir/.installed-projects" ]] || return 0
  python3 "$cli" --universe --factory "$project_dir" >>"$log" 2>&1 || _log "action=failed kind=universe rc=$?"
}

touch "$marker"
if [[ "${HERMES_DASHBOARD_SYNC:-0}" == "1" ]]; then     # 테스트·수동 확인용: 앞에서 기다린다
  _render
else
  ( trap '' HUP; _render ) >>"$log" 2>&1 &      # nohup 대신 서브셸 — 두 번 부르는 동안 한 번만 떼어 낸다
fi
_log "action=run"
exit 0
