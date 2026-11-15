#!/usr/bin/env bash
# claude-sessionstart-upstream.sh — SessionStart hook (matcher 없음, source 로 거른다)
#
# 밖에서 가져온 스킬·규칙·에이전트의 원본이 바뀌었는지 컴퓨터마다 하루 한 번 확인하고, 바뀌었으면 알린다.
# 공장이 없는 컴퓨터(소우주만 clone)에서도 돈다 — 장부(.claude/.upstream.json)와 확인 프로그램
# (scripts/upstream-check.py)이 프로젝트 안에 커밋돼 있다.
# 계획: docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G5
#
#   1) 알림(앞, 네트워크 없음): 이미 있는 상태로 뒤처진 항목을 보고, 있으면 JSON 한 줄을 stdout 에 낸다.
#      SessionStart stdout 은 세션 문맥에 들어간다 — 그래서 알림은 하루 한 번, 한 줄로만 낸다.
#   2) 확인(뒤, setsid): 원본 저장소마다 트리를 한 번 묻는다. 세션 시작을 막지 않는다.
#
# 비활성화: HERMES_DISABLED=1 (전체) 또는 HERMES_UPSTREAM_CHECK=0 (이 훅만)
# 상태: ~/.hermes/upstream-status.json · 직접 보기: python3 scripts/upstream-check.py --show

set -uo pipefail

[[ "${HERMES_DISABLED:-0}" == "1" ]] && exit 0
[[ "${HERMES_UPSTREAM_CHECK:-1}" == "0" ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null || true)"
source_val="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("source", "") or "")
except Exception:
    pass
' 2>/dev/null || true)"

case "$source_val" in
  startup|resume) ;;
  *) exit 0 ;;
esac

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
ledger="$project_dir/.claude/.upstream.json"
checker="$project_dir/scripts/upstream-check.py"
log_file="$project_dir/.hermes/hooks.log"
_log() {
  [[ -d "$project_dir/.hermes" ]] || return 0
  echo "[upstream-hook] $(date -Iseconds) $*" >>"$log_file" 2>/dev/null || true
}

[[ -f "$ledger" ]] || { _log "skip:no-ledger"; exit 0; }
[[ -f "$checker" ]] || { _log "skip:no-checker"; exit 0; }

# 1) 알림 — 상태 파일만 읽으므로 빠르다. 실패해도 세션은 계속된다.
timeout 5 python3 "$checker" --notice --ledger "$ledger" 2>>"$log_file" || _log "notice rc=$?"

# 2) 확인 — 뒤에서. 잠금·20시간·1시간 재시도 판단은 확인 프로그램이 한다.
UPSTREAM_CHECKER="$checker" UPSTREAM_LEDGER="$ledger" UPSTREAM_LOG="$log_file" \
setsid bash -c '
  timeout 120 python3 "$UPSTREAM_CHECKER" --check --ledger "$UPSTREAM_LEDGER" >/dev/null 2>&1
  rc=$?
  [[ -d "$(dirname "$UPSTREAM_LOG")" ]] && echo "[upstream-hook] $(date -Iseconds) check rc=$rc" >>"$UPSTREAM_LOG"
' </dev/null >/dev/null 2>&1 &

_log "run source=$source_val"
exit 0
