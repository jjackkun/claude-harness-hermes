#!/usr/bin/env python3
"""세션마다 나온 패턴 후보 낱말을 적고, 한 낱말이 몇 세션에 나왔는지 세는 것만 담당한다.

대화 원문(session_history) 전문 검색을 대신한다 — 원문을 저장하지 않게 되어(계획 carry-agent-knowledge 목표 10)
"2개 이상 세션에서 나온 후보만 패턴으로 인정" 하는 관문이 기댈 곳이 필요하다. 원문 검색은 옛 세션의
**아무 곳**에 나온 낱말도 셌지만, 여기는 그 세션의 **후보(세션 안 2회 이상, 상위 50)** 였던 낱말만 센다.
같은 세션을 다시 저장해도 한 번만 센다(PRIMARY KEY).

공개: record · session_count
"""


def _ensure(con) -> None:
    con.execute("CREATE TABLE IF NOT EXISTS token_session ("
                " token TEXT NOT NULL, session_id TEXT NOT NULL, PRIMARY KEY (token, session_id))")


def record(con, tokens: list, session_id: str) -> None:
    """이 세션의 후보 낱말을 적는다. session_id 가 없으면 적지 않는다(셀 근거가 없다)."""
    if not session_id:
        return
    _ensure(con)
    con.executemany("INSERT OR IGNORE INTO token_session (token, session_id) VALUES (?, ?)",
                    [(t, session_id) for t in tokens])
    con.commit()


def session_count(con, token: str) -> int:
    _ensure(con)
    row = con.execute("SELECT COUNT(*) FROM token_session WHERE token = ?", (token,)).fetchone()
    return int(row[0]) if row else 0
