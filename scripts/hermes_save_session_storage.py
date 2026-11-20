"""헤르메스 세션 저장 — DB 계층.

hermes-save-session.py 에서 분리된 저장소 헬퍼 모음.
연결/transcript 로드/세션 저장/패턴 카운트 갱신을 담당한다.
"""

import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_human_turn import HUMAN_MARK, is_human_entry  # noqa: E402  (사람 입력 판정)
from hermes_mistake_keys import MISTAKE_KEYS, NOT_CRYSTALLIZED  # noqa: E402  (실수 감지 키)


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1).

    훅들이 병렬로 같은 DB를 만질 수 있으므로 잠금 대기를 보장한다.
    (hermes 스크립트들은 독립 배포되므로 각 파일에 동일 함수를 복제한다)
    """
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def load_transcript(path: str) -> list:
    if not os.path.isfile(path):
        return []
    messages = []
    try:
        with open(path, "r", encoding="utf-8") as f:
            first_char = f.read(1)
            f.seek(0)
            if first_char == "[":
                data = json.load(f)
                if isinstance(data, list):
                    return data
                return data.get("messages", [])
            else:
                # JSONL: Claude Code transcript 형식
                # 각 줄: {"type": "user"|"assistant", "message": {"role": ..., "content": ...}}
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                        t = obj.get("type")
                        if t in ("user", "assistant") and "message" in obj:
                            # 바깥 표시(isMeta·origin 등)는 여기서 버려지므로 사람 여부를 사본에 남긴다.
                            messages.append({**obj["message"], HUMAN_MARK: is_human_entry(obj)})
                    except json.JSONDecodeError:
                        continue
    except Exception as e:
        print(f"[hermes] transcript 읽기 실패: {e}", file=sys.stderr)
        return []
    return messages




def _mistake_targets(cur, already: list) -> list:
    """실수 감지 훅이 센 키 가운데 임계(3)를 넘고 아직 판정 안 된 것 — 요약 키 루프는 이 키를 보지 않는다(G5).

    훅은 hermes-increment.py 로 count 만 올리므로, 여기서 따로 고르지 않으면 영원히 결정화되지 않는다
    (jj-agent-room worktree-not-synced: 104번, 2026-11-20). 계획: docs/exec-plans/completed/2026-11-20-worktree-finish-plan.md
    """
    wanted = [k for k in MISTAKE_KEYS if k not in NOT_CRYSTALLIZED and k not in already]
    if not wanted:
        return []
    marks = ",".join("?" * len(wanted))
    rows = cur.execute(
        f"SELECT pattern_key FROM pattern_count WHERE count >= 3 AND crystallized = 0 AND pattern_key IN ({marks}) "
        "ORDER BY count DESC",
        wanted,
    ).fetchall()
    return [r[0] for r in rows]


def update_patterns(db_path: str, patterns: list, session_id: str) -> list:
    """pattern_count 업데이트. 결정화 임계값(3) 도달 패턴 목록 반환.

    pattern_session 테이블로 (패턴, 세션) 쌍을 기록해
    같은 세션의 재저장으로 카운트가 중복 증가하지 않도록 한다 (C2).
    """
    con = connect_db(db_path)
    cur = con.cursor()
    cur.execute(
        "CREATE TABLE IF NOT EXISTS pattern_session ("
        "  pattern_key TEXT NOT NULL,"
        "  session_id  TEXT NOT NULL,"
        "  PRIMARY KEY (pattern_key, session_id)"
        ")"
    )
    crystallize_targets = []

    for key in patterns:
        marked = cur.execute(
            "INSERT OR IGNORE INTO pattern_session (pattern_key, session_id) "
            "VALUES (?, ?)",
            (key, session_id),
        )
        if marked.rowcount == 0:
            # 같은 세션에서 이미 집계됨 — 재저장으로 인한 중복 증가 방지
            continue

        cur.execute(
            "INSERT INTO pattern_count (pattern_key, count, last_seen) "
            "VALUES (?, 1, CURRENT_TIMESTAMP) "
            "ON CONFLICT(pattern_key) DO UPDATE SET "
            "count = count + 1, last_seen = CURRENT_TIMESTAMP "
            "WHERE crystallized = 0",
            (key,),
        )
        row = cur.execute(
            "SELECT count FROM pattern_count WHERE pattern_key=? AND crystallized=0",
            (key,),
        ).fetchone()
        if row and row[0] >= 3:
            crystallize_targets.append(key)

    crystallize_targets += _mistake_targets(cur, crystallize_targets)
    con.commit()
    con.close()
    return crystallize_targets
