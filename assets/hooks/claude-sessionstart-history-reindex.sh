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
#   need=2 는 발산(텍스트 < DB). 발산은 사유가 갈리고 **해결 방향이 정반대**라 하위 분류한다:
#     compacted — 발산 파일이 전부 압축 산물. reindex --force(파일→DB)로 수용.
#     lagging   — 압축 마커 없는 세션의 파일이 DB 보다 뒤처짐(Stop 훅 export 실패).
#                 여기에 --force 를 쓰면 DB 원문이 영구 소실된다. 해결은 세션 단위 export.
#     mixed     — 둘 다 존재. --force 는 전역이라 뒤처진 세션까지 파괴하므로 권하지 않는다.
#     db-only   — 파일이 아예 없는 세션(양성). reindex --backfill 로 보정.
#   증가가 없어 need=0 이지만 "동기화됨"이 아니므로 in-sync 와 분리해 기록한다.
gate="$(python3 -c "
import sqlite3, sys, glob, os, json
files = glob.glob(os.path.join(sys.argv[1], '*.jsonl'))
tl = 0
fmeta = {}
for f in files:
    lines = []
    try:
        with open(f, encoding='utf-8') as fh: lines = fh.readlines()
    except Exception: pass
    tl += len(lines)
    body = [l for l in lines if l.strip()]
    sid, comp = None, False
    if body:
        try:
            obj = json.loads(body[0])
            if isinstance(obj, dict):
                sid = obj.get('session_id')
                # 압축본 판정 — scripts/hermes-export-history.py _compacted_record() 와 동일 기준
                # (훅은 하네스와 독립 실행이라 중복 구현한다. 한쪽을 바꾸면 다른 쪽도 바꿀 것)
                comp = len(body) == 1 and obj.get('compacted') is True
        except Exception: pass
    if sid:
        n, c = fmeta.get(sid, (0, False))
        fmeta[sid] = (n + len(body), c or comp)
ts = len(files)
db_ok = True
counts = {}
try:
    con = sqlite3.connect(sys.argv[2])
    ds = con.execute('SELECT COUNT(DISTINCT session_id) FROM session_history').fetchone()[0]
    dr = con.execute('SELECT COUNT(*) FROM session_history').fetchone()[0]
    counts = dict(con.execute('SELECT session_id, COUNT(*) FROM session_history GROUP BY session_id'))
except Exception:
    ds = dr = 2**31
    db_ok = False
reason, sids = 'none', ''
if ts > ds or tl > dr:
    need = 1
elif db_ok and (ts < ds or tl < dr):
    need = 2
    lag = sorted(s for s, (n, c) in fmeta.items() if not c and n < counts.get(s, 0))
    comp = sorted(s for s, (n, c) in fmeta.items() if c and counts.get(s, 0) > n)
    reason = 'mixed' if (lag and comp) else ('lagging' if lag else ('compacted' if comp else 'db-only'))
    sids = ','.join(lag or comp)
else:
    need = 0
print('%d reason=%s ts=%d ds=%d tl=%d dr=%d sids=%s' % (need, reason, ts, ds, tl, dr, sids or '-'))
" "$hist_dir" "$db_path" 2>/dev/null || echo '0 reason=error')"
need="${gate%% *}"
if [[ "$need" == "2" ]]; then
  # 자동 복구하지 않는다 — 훅이 --force 를 붙이면 "손상된 텍스트가 DB 를 파괴하지
  # 못하게" 막는 재색인 행수감소 가드가 통째로 무력화된다. 로그 안내까지만.
  reason="${gate#* reason=}"; reason="${reason%% *}"
  sids="${gate#* sids=}"; sids="${sids%% *}"
  first_sid="${sids%%,*}"    # --session 은 세션 1개씩 — 여러 개면 대표 1개를 예시로 보인다
  case "$reason" in
    compacted)
      # 방향 주의: 이 상태에서 전량 export(DB→파일)는 압축을 되돌리므로 쓰지 않는다.
      _log "action=skip:diverged:compacted $gate — 발산 파일이 전부 압축본이다(타 기계가 압축한 요약본을 pull 한 상태). 압축을 수용하려면 수동으로: python3 <harness>/scripts/hermes-reindex.py --db '$db_path' --project '$project_dir' --force ⚠ 주의: --force 는 세션 단위가 아니라 전역이다. 파일이 DB 보다 뒤처진 다른 세션이 있으면 그 원문까지 파일 기준으로 덮어써 소실된다. 실행 전 .hermes/history 의 git 상태를 확인하라."
      ;;
    lagging)
      _log "action=skip:diverged:lagging $gate — 압축과 무관한 발산이다. 파일이 DB 보다 뒤처졌다(Stop 훅 export 실패 가능). DB 원문이 정본이므로 해당 세션을 파일로 내보낸 뒤 커밋하라: python3 <harness>/scripts/hermes-export-history.py --db '$db_path' --project '$project_dir' --session $first_sid (대상 세션: $sids — 세션마다 1회씩)"
      ;;
    mixed)
      _log "action=skip:diverged:mixed $gate — 압축본과 뒤처진 세션이 섞여 있다. 뒤처진 세션을 먼저 세션 단위로 동기화·커밋하라: python3 <harness>/scripts/hermes-export-history.py --db '$db_path' --project '$project_dir' --session $first_sid (대상 세션: $sids — 세션마다 1회씩). 그 뒤에 압축 수용 여부를 판단하라 — 지금 전역 재색인을 돌리면 뒤처진 세션의 DB 원문이 소실된다."
      ;;
    *)
      _log "action=skip:diverged:db-only $gate — DB 에만 있고 파일이 없는 세션이 있다(양성). 파일로 보정하려면: python3 <harness>/scripts/hermes-reindex.py --db '$db_path' --project '$project_dir' --backfill"
      ;;
  esac
  exit 0
fi
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
