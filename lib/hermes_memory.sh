#!/usr/bin/env bash
# dev-setting/lib/hermes_memory.sh
# 헤르메스 SQLite 기억 구조 공통 함수.
# Sourced by hermes.conf 및 헤르메스 Hook 스크립트들.
#
# 구현 노트: sqlite3 CLI 가 없는 환경이 흔하므로 python3 의 sqlite3 모듈로 실행한다.
# 사용자 입력이 들어가는 쿼리는 전부 파라미터 바인딩(?) — SQL 문자열 보간 금지.

HERMES_GLOBAL_DIR="${HOME}/.hermes"
HERMES_GLOBAL_DB="${HERMES_GLOBAL_DIR}/global.db"

# hermes_project_db <project_path>
# 프로젝트 DB 경로 반환
hermes_project_db() {
  echo "${1}/.hermes/state.db"
}

# hermes_init <project_path>
# global DB + project DB 초기화 (없을 때만)
hermes_init() {
  local project_path="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local init_script="$script_dir/scripts/hermes-init.py"

  [[ -f "$init_script" ]] || { echo "[hermes] ERROR: hermes-init.py not found" >&2; return 1; }

  python3 "$init_script" --both "$project_path"
}

# _hermes_py <db_path> <op> [args...]
# python3 sqlite3 디스패처. op 별로 파라미터 바인딩 쿼리 실행.
# 출력은 sqlite3 CLI 호환('|' 구분)을 유지한다.
_hermes_py() {
  local db="$1"
  shift
  [[ -f "$db" ]] || return 1
  command -v python3 >/dev/null 2>&1 || {
    echo "[hermes] ERROR: python3 not found — hermes memory disabled" >&2
    return 1
  }
  python3 - "$db" "$@" <<'PYEOF'
import sqlite3
import sys

CRYSTALLIZE_THRESHOLD = 3


def emit(rows):
    for row in rows:
        print("|".join("" if v is None else str(v) for v in row))


def main() -> int:
    db, op, *args = sys.argv[1:]
    con = sqlite3.connect(db)
    cur = con.cursor()
    try:
        if op == "query":
            emit(cur.execute(args[0]))
        elif op == "search":
            emit(cur.execute(
                "SELECT content FROM session_history "
                "WHERE session_history MATCH ? LIMIT 5",
                (args[0],),
            ))
        elif op == "skill_search":
            emit(cur.execute(
                "SELECT skill_path FROM skill_index WHERE keywords LIKE ? "
                "ORDER BY used_count DESC LIMIT 3",
                (f"%{args[0]}%",),
            ))
        elif op == "pattern_inc":
            cur.execute(
                "INSERT INTO pattern_count (pattern_key, count, last_seen) "
                "VALUES (?, 1, CURRENT_TIMESTAMP) "
                "ON CONFLICT(pattern_key) DO UPDATE SET "
                "count = count + 1, last_seen = CURRENT_TIMESTAMP",
                (args[0],),
            )
            row = cur.execute(
                "SELECT count FROM pattern_count "
                "WHERE pattern_key = ? AND crystallized = 0",
                (args[0],),
            ).fetchone()
            if row and row[0] >= CRYSTALLIZE_THRESHOLD:
                print("CRYSTALLIZE")
        elif op == "skill_register":
            skill_path, keywords, scope = args
            cur.execute(
                "INSERT OR REPLACE INTO skill_index (skill_path, keywords, scope) "
                "VALUES (?, ?, ?)",
                (skill_path, keywords, scope),
            )
        elif op == "skill_used":
            cur.execute(
                "UPDATE skill_index SET used_count = used_count + 1 "
                "WHERE skill_path = ?",
                (args[0],),
            )
        elif op == "message_send":
            from_agent, to_agent, content = args
            cur.execute(
                "INSERT INTO messages (from_agent, to_agent, content) "
                "VALUES (?, ?, ?)",
                (from_agent, to_agent, content),
            )
        elif op == "message_recv":
            emit(cur.execute(
                "SELECT id, from_agent, content FROM messages "
                "WHERE to_agent = ? AND status = 'unread'",
                (args[0],),
            ))
            cur.execute(
                "UPDATE messages SET status = 'read' "
                "WHERE to_agent = ? AND status = 'unread'",
                (args[0],),
            )
        else:
            print(f"[hermes] unknown op: {op}", file=sys.stderr)
            return 2
        con.commit()
        return 0
    except sqlite3.Error as exc:
        print(f"[hermes] sqlite error ({op}): {exc}", file=sys.stderr)
        return 1
    finally:
        con.close()


sys.exit(main())
PYEOF
}

# hermes_query <db_path> <sql>
# SQLite 쿼리 실행 후 결과 출력.
# 주의: 호출자가 신뢰된 고정 SQL 만 넘겨야 한다 (사용자 입력 보간 금지 —
# 키워드 검색 등은 hermes_search / hermes_skill_search 의 바인딩 경로 사용).
hermes_query() {
  local db="$1"
  local sql="$2"
  _hermes_py "$db" query "$sql"
}

# hermes_search <db_path> <keyword>
# session_history FTS5 검색 — 관련 내용 최대 5개 반환
hermes_search() {
  local db="$1"
  local keyword="$2"
  _hermes_py "$db" search "$keyword"
}

# hermes_skill_search <db_path> <keyword>
# skill_index에서 키워드로 관련 스킬 경로 반환
hermes_skill_search() {
  local db="$1"
  local keyword="$2"
  _hermes_py "$db" skill_search "$keyword"
}

# hermes_pattern_inc <db_path> <pattern_key>
# 패턴 카운트 증가. 결정화 임계값(3회) 도달 시 echo "CRYSTALLIZE"
hermes_pattern_inc() {
  local db="$1"
  local key="$2"
  _hermes_py "$db" pattern_inc "$key"
}

# hermes_skill_register <db_path> <skill_path> <keywords> <scope>
# 새 스킬을 skill_index에 등록
hermes_skill_register() {
  local db="$1"
  local skill_path="$2"
  local keywords="$3"
  local scope="${4:-local}"
  _hermes_py "$db" skill_register "$skill_path" "$keywords" "$scope"
}

# hermes_skill_used <db_path> <skill_path>
# 스킬 사용 카운트 +1
hermes_skill_used() {
  local db="$1"
  local skill_path="$2"
  _hermes_py "$db" skill_used "$skill_path"
}

# hermes_message_send <db_path> <from> <to> <content>
# 에이전트 메시지 전송
hermes_message_send() {
  local db="$1"
  local from="$2"
  local to="$3"
  local content="$4"
  _hermes_py "$db" message_send "$from" "$to" "$content"
}

# hermes_message_recv <db_path> <to_agent>
# 에이전트 미읽은 메시지 수신 후 read 처리
hermes_message_recv() {
  local db="$1"
  local to="$2"
  _hermes_py "$db" message_recv "$to"
}

# hermes_status <db_path>
# 헤르메스 현황 출력 (/hermes-status 에서 사용)
hermes_status() {
  local db="$1"
  [[ -f "$db" ]] || { echo "[hermes] DB not found: $db"; return 1; }

  local skill_count rule_count session_count
  skill_count=$(_hermes_py "$db" query "SELECT COUNT(*) FROM skill_index;")
  rule_count=$(_hermes_py "$db" query "SELECT COUNT(*) FROM harness_rules;")
  session_count=$(_hermes_py "$db" query "SELECT COUNT(*) FROM session_history;")

  local latest_skill
  latest_skill=$(_hermes_py "$db" query "SELECT skill_path, created_at FROM skill_index ORDER BY created_at DESC LIMIT 1;")

  local top_skill
  top_skill=$(_hermes_py "$db" query "SELECT skill_path, used_count FROM skill_index ORDER BY used_count DESC LIMIT 1;")

  echo "╔══════════════════════════════════════╗"
  echo "║        헤르메스 현황 (Hermes)         ║"
  echo "╠══════════════════════════════════════╣"
  printf "║  스킬: %-5s  규칙: %-5s  세션: %-5s ║\n" "$skill_count" "$rule_count" "$session_count"
  echo "╠══════════════════════════════════════╣"
  [[ -n "$latest_skill" ]] && echo "║  최근 스킬: $latest_skill"
  [[ -n "$top_skill"    ]] && echo "║  최다 활용: $top_skill"
  echo "╚══════════════════════════════════════╝"
}
