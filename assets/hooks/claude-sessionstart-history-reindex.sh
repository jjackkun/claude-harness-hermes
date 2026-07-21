#!/usr/bin/env bash
# SessionStart hook — pull 후 자동 재색인 트리거.
#
# 다른 컴퓨터에서 pull 한 .hermes/history/*.jsonl 텍스트가 로컬 DB 보다 많으면
# hermes-reindex.py 를 setsid 백그라운드로 1회 구동한다. clone·pull 한 사람이
# 재색인 명령의 존재를 몰라도 "즉시 아는 상태"로 시작하게 한다.
#
# 재색인 성질(T3): 이 auto-reindex 는 세션을 추가·복원만 하고 축소하지 않는다.
#   신규 세션은 항상 색인되지만, 기존 세션의 행수 축소는 --force 없이 거부된다(안전 우선).
#   따라서 이 훅은 --force 를 쓰지 않는다.
#
# 저렴한 감지: 텍스트 세션 수 증가 OR 총 라인 수 증가일 때만 실행한다.
#   세션 수만 보면 "다른 PC 에서 이어간 세션"(같은 파일이 더 긴 버전으로 pull —
#   파일 개수 불변)을 놓친다. 총 라인 수를 2차 신호로 결합해 그 케이스도 감지한다.
#   매 세션 전량 재색인은 낭비(zeroday 기준 14,280행)이므로 게이트로 막는다.
#
# 중요: SessionStart 훅은 stdout 이 세션 컨텍스트로 주입되므로 stdout 무출력.
#       모든 진단은 .hermes/hooks.log 로만. 세션 시작을 절대 블로킹하지 않는다.
#
# 비활성화: HERMES_DISABLED=1

set -uo pipefail

# [게이트 0] 옵트아웃
[[ "${HERMES_DISABLED:-0}" == "1" ]] && exit 0

# [게이트 1] python3 필수
command -v python3 >/dev/null 2>&1 || exit 0

# project_dir 해석 — 워크트리 경로는 메인 루트로 정규화(백그라운드 워크트리 세션이
# 워크트리 안의 없는 .hermes 를 보지 않도록, memory-guard·dream 훅과 동일 처리).
raw_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="$(printf '%s' "$raw_dir" | sed 's|/.claude/worktrees/[^/]*$||')"
log_file="$project_dir/.hermes/hooks.log"

_log() {
  [[ -d "$project_dir/.hermes" ]] || return 0
  echo "[hermes-reindex-hook] $(date -Iseconds) $*" >>"$log_file" 2>/dev/null || true
}

# [게이트 2] .hermes 존재 (비-hermes 프로젝트 no-op)
[[ -d "$project_dir/.hermes" ]] || exit 0

# [게이트 3] DB 존재
db_path="$project_dir/.hermes/state.db"
[[ -f "$db_path" ]] || { _log "action=skip:no-db"; exit 0; }

# [게이트 4] history 디렉터리 존재
hist_dir="$project_dir/.hermes/history"
[[ -d "$hist_dir" ]] || { _log "action=skip:no-history"; exit 0; }

# 텍스트 세션 파일 수 — 배열 글롭(파이프 없음: ugrep/SIGPIPE 회피). D3 이 세션당 파일 1개 보장.
shopt -s nullglob
hist_files=("$hist_dir"/*.jsonl)
shopt -u nullglob
text_count=${#hist_files[@]}
[[ "$text_count" -eq 0 ]] && { _log "action=skip:no-jsonl"; exit 0; }

# [게이트 5] 재색인 필요 판정 — 세션 수 증가 OR 총 라인 수 증가(같은 세션의 더 긴 버전 pull 감지).
#   파이썬 1회(파이프 없음: ugrep/SIGPIPE 회피). DB 조회 실패 시 보수적으로 "불필요"(2**31).
gate="$(python3 -c "
import sqlite3, sys, glob, os
files = glob.glob(os.path.join(sys.argv[1], '*.jsonl'))
tl = 0
for f in files:
    try:
        with open(f, encoding='utf-8') as fh: tl += sum(1 for _ in fh)
    except Exception: pass
ts = len(files)
try:
    con = sqlite3.connect(sys.argv[2])
    ds = con.execute('SELECT COUNT(DISTINCT session_id) FROM session_history').fetchone()[0]
    dr = con.execute('SELECT COUNT(*) FROM session_history').fetchone()[0]
except Exception:
    ds = dr = 2**31
need = 1 if (ts > ds or tl > dr) else 0
print(f'{need} ts={ts} ds={ds} tl={tl} dr={dr}')
" "$hist_dir" "$db_path" 2>/dev/null || echo '0 error')"
need="${gate%% *}"
if [[ "$need" != "1" ]]; then
  _log "action=skip:in-sync $gate"
  exit 0
fi

# 재색인 스크립트 존재 확인.
scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"
[[ -f "$scripts_dir/hermes-reindex.py" ]] || { _log "action=skip:no-script"; exit 0; }

_log "action=run $gate"

# setsid 백그라운드 분리 — 세션 시작 비차단. --force 미사용(축소 거부·안전 우선).
HERMES_DB_PATH="$db_path" \
HERMES_PROJECT_DIR="$project_dir" \
HERMES_SCRIPTS_DIR="$scripts_dir" \
HERMES_LOG="$log_file" \
setsid bash -c '
  timeout 120 python3 "$HERMES_SCRIPTS_DIR/hermes-reindex.py" \
    --db "$HERMES_DB_PATH" \
    --project "$HERMES_PROJECT_DIR" \
    >>"$HERMES_LOG" 2>&1 || true
  echo "[hermes-reindex-hook] reindex done $(date -Iseconds)" >>"$HERMES_LOG"
' </dev/null >/dev/null 2>&1 &

exit 0
