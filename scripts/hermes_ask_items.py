"""커밋 때 사람에게 물을 항목을 모은다 — 문장 확인 대기 · 성향 승인 대기 · 정답지 표본.

항목 id: `p:<해시8>` 문장 대기 · `s:<라벨>` 성향 승인 · `g:<해시8>` 표본. 한 폼은 질문 4개까지라 합이 4 를 넘으면 뒤에서 자른다.
표본 목표(정답지)에 못 미친 동안은 1칸을 표본용으로 예약한다 — 대기가 많아도 정답지가 자라도록.
프로젝트 DB 와 전역 DB(성향)를 함께 읽는 곳은 여기 한 곳이다(성향은 `persona_items` 하나로만).
계획: docs/exec-plans/completed/2026-09-29-privacy-gate-hardening.md 목표 5

공개: MAX_ITEMS · persona_items · privacy_items · gold_candidates · collect · already_asked · mark_asked
"""

import os
import random
import sqlite3
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_privacy_gold import TARGET, count as gold_count, known  # noqa: E402
from hermes_privacy_pending import pending_rows, status_of, text_hash  # noqa: E402
from hermes_privacy_staged import staged_texts  # noqa: E402

MAX_ITEMS = 4            # 질문 폼 한 번에 질문 4개(도구 제약)
GOLD_PER_COMMIT = 3      # 커밋마다 묻는 표본 수 — 사용자가 연달아 답하기 부담스럽지 않은 양
GLOBAL_DB = os.path.join("~", ".hermes", "global.db")


def ensure_marker(con) -> None:
    con.execute("CREATE TABLE IF NOT EXISTS ask_marker (session_id TEXT PRIMARY KEY, asked_at TEXT DEFAULT CURRENT_TIMESTAMP,"
                " n_items INTEGER)")


def already_asked(con, session_id: str) -> bool:
    ensure_marker(con)
    return con.execute("SELECT 1 FROM ask_marker WHERE session_id=?", (session_id,)).fetchone() is not None


def mark_asked(con, session_id: str, n_items: int) -> None:
    ensure_marker(con)
    con.execute("INSERT OR IGNORE INTO ask_marker (session_id, n_items) VALUES (?,?)", (session_id, n_items))
    con.commit()


def privacy_items(con) -> list:
    return [("p:" + h[:8], text) for h, _kind, _ref, text in pending_rows(con)]


def persona_items() -> list:
    """성향 승인 대기 [(s:라벨, 문장)]. 전역 DB 가 없거나 못 읽으면 빈 목록."""
    path = os.path.expanduser(GLOBAL_DB)
    if not os.path.isfile(path):
        return []
    try:
        from hermes_persona_view import build_view
        view = build_view(sqlite3.connect(path), datetime.now(timezone.utc))
    except (sqlite3.Error, ImportError):
        return []
    return [("s:" + i["label"], i["statement"]) for i in view["items"] if i["state"] == "pending"]


def gold_candidates(con) -> dict:
    """정답지 후보 {해시: 문장} — 스테이징된 통과(clean) 문장 중 아직 안 물은 것. 스킬 본문(통째 판정)은 뺀다."""
    out = {}
    for path, text in staged_texts():
        h = text_hash(text)
        if not path.endswith(".md") and status_of(con, text) == "clean" and not known(con, h):
            out[h] = text
    return out


def gold_items(con, session_id: str, limit: int) -> list:
    cands = gold_candidates(con)
    picks = random.Random(session_id).sample(sorted(cands), min(limit, len(cands)))   # 같은 세션이면 같은 표본
    return [("g:" + h[:8], cands[h]) for h in picks]


def collect(con, session_id: str) -> list:
    """이번 세션에 물을 항목 [(id, 문장)] — 문장 대기 → 성향 대기 → 표본 순, 표본 1칸 예약."""
    pool = gold_items(con, session_id, GOLD_PER_COMMIT) if gold_count(con) < TARGET else []
    head = (privacy_items(con) + persona_items())[: MAX_ITEMS - (1 if pool else 0)]
    return head + pool[: MAX_ITEMS - len(head)]
