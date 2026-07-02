"""헤르메스 세션 저장 — DB 계층.

hermes-save-session.py 에서 분리된 저장소 헬퍼 모음.
연결/transcript 로드/세션 저장/패턴 카운트 갱신을 담당한다.
"""

import json
import os
import sqlite3
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_redact import redact  # noqa: E402  (민감정보 마스킹 공유 헬퍼)


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
                            messages.append(obj["message"])
                    except json.JSONDecodeError:
                        continue
    except Exception as e:
        print(f"[hermes] transcript 읽기 실패: {e}", file=sys.stderr)
        return []
    return messages


def save_session(db_path: str, messages: list, project_id: str, session_id: str):
    """세션 저장. 같은 session_id 재저장 시 이전 행을 교체한다 (C2)."""
    con = connect_db(db_path)
    con.isolation_level = None  # 명시적 트랜잭션 제어
    cur = con.cursor()

    # 매 턴 Stop 훅이 전체 transcript 를 다시 보내므로,
    # 누적 INSERT 대신 같은 세션의 이전 행을 지우고 최신 1벌만 유지한다.
    # Stop 훅이 연속 발화해 두 프로세스가 겹쳐도 DELETE+INSERT 가 인터리빙되지
    # 않도록 BEGIN IMMEDIATE 로 쓰기 락을 선점한 단일 트랜잭션으로 묶는다.
    inserted = 0
    try:
        cur.execute("BEGIN IMMEDIATE")
        cur.execute("DELETE FROM session_history WHERE session_id = ?", (session_id,))

        ts = datetime.now().isoformat()
        for msg in messages:
            if not isinstance(msg, dict):
                continue
            role = msg.get("role", "")
            if role not in ("user", "assistant", "tool"):
                continue
            raw = msg.get("content", "")
            if isinstance(raw, list):
                content = " ".join(
                    p.get("text", "") for p in raw if isinstance(p, dict) and "text" in p
                )
            else:
                content = str(raw)
            content = content.strip()
            if not content:
                continue
            content = redact(content)  # 원문 적재 전 민감정보 마스킹

            cur.execute(
                "INSERT INTO session_history (content, role, timestamp, project_id, session_id) "
                "VALUES (?, ?, ?, ?, ?)",
                (content, role, ts, project_id, session_id),
            )
            inserted += 1
        cur.execute("COMMIT")
    except Exception:
        try:
            cur.execute("ROLLBACK")
        except sqlite3.OperationalError:
            pass
        raise
    finally:
        con.close()
    print(f"[hermes] session saved: {inserted} messages → {db_path}")
    return inserted


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

    con.commit()
    con.close()
    return crystallize_targets
