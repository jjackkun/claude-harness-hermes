"""담당에 관한 두 기억 — "담당 두지 않음" 과 "담당 없음 제안" — 의 기록·조회만 담당한다.

- 담당 두지 않음(creation-and-organization.md §5 "담당 두지 않음 → 기억해 두고 이 영역은 다시 묻지 않음"):
  사람이 정한 것. 같은 축 값으로 다시 매칭이 비면 ask 대신 이 기억을 보인다.
- 담당 없음 제안(같은 문서 "사람이 없는 세션 … main 이 수행하고 '담당 없음' 제안을 기록한다. 다음
  대화형 세션에서 문의한다"): 기계가 남긴 것. 사람이 답(입사 또는 담당 두지 않음)할 때까지 남는다.

둘 다 새 kind 가 아니라 `decision` 이벤트의 intent 접두어로 적는다 — kind 를 늘리면 DB 마이그레이션이
또 필요하고, 자유 글 칸은 이미 마스킹·길이 검사를 거친다(계획 design-gaps-tier2 §6).
"""
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_journal import emit  # noqa: E402
from hermes_redact import redact  # noqa: E402

NO_OWNER = "no-owner"
PROPOSAL = "owner-proposal"
_AXES = ("discipline", "rank", "unit")


def area_key(want: dict) -> str:
    """축 값을 고정 순서의 한 문자열로 — 기록과 조회가 같은 열쇠를 쓴다."""
    return " ".join(f"{k}:{want[k]}" for k in _AXES if want.get(k))


def _db(project: str) -> str:
    return os.path.join(project, ".hermes", "state.db")


def record_no_owner(project: str, want: dict, by: str) -> str:
    """사람이 "이 영역은 담당을 두지 않는다" 고 정했다. 같은 열쇠의 제안이 열려 있었으면 이것이 답이다."""
    return emit(_db(project), project, {"kind": "decision", "actor": by, "requested_by": by,
                                        "intent": f"{NO_OWNER} {area_key(want)}"})


def record_proposal(project: str, want: dict, by: str) -> str:
    """무인 세션이 담당 없이 main 으로 수행했다 — 다음 대화형 세션에서 사람에게 물을 제안."""
    return emit(_db(project), project, {"kind": "decision", "actor": by, "requested_by": by,
                                        "intent": f"{PROPOSAL} {area_key(want)}"})


def no_owner_since(project: str, want: dict) -> str:
    """그 영역에 "담당 두지 않음" 기억이 있으면 그 날짜(ts), 없으면 빈 문자열.

    저장은 emit 이 자유 글 칸을 마스킹한 뒤 하므로, 조회 열쇠도 같은 마스킹을 거친다 — 축 값이
    전화·메일 꼴이면 저장값과 어긋나 "다시 묻지 않음" 이 조용히 깨진다(리뷰 MEDIUM)."""
    return _latest(project, redact(f"{NO_OWNER} {area_key(want)}", project))


def open_proposals(project: str) -> list:
    """답이 없는 제안 [{'area','ts'}] — 같은 열쇠에 이후 no-owner 결정이 있으면 답한 것으로 본다."""
    db = _db(project)
    if not os.path.isfile(db):
        return []
    con = sqlite3.connect(db)
    try:
        rows = con.execute("SELECT intent, ts FROM journal_events WHERE kind='decision' "
                           "AND (intent LIKE ? OR intent LIKE ?) ORDER BY ts",
                           (f"{PROPOSAL} %", f"{NO_OWNER} %")).fetchall()
    except sqlite3.DatabaseError:
        return []
    finally:
        con.close()
    answered, out = set(), []
    for intent, ts in rows:
        head, _, area = intent.partition(" ")
        if head == NO_OWNER:
            answered.add(area)
    for intent, ts in rows:
        head, _, area = intent.partition(" ")
        if head == PROPOSAL and area not in answered:
            out.append({"area": area, "ts": ts})
    return out


def _latest(project: str, intent: str) -> str:
    db = _db(project)
    if not os.path.isfile(db):
        return ""
    con = sqlite3.connect(db)
    try:
        row = con.execute("SELECT ts FROM journal_events WHERE kind='decision' AND intent=? "
                          "ORDER BY ts DESC LIMIT 1", (intent,)).fetchone()
    except sqlite3.DatabaseError:
        return ""
    finally:
        con.close()
    return row[0] if row else ""


__all__ = ["NO_OWNER", "PROPOSAL", "area_key", "record_no_owner", "record_proposal",
           "no_owner_since", "open_proposals"]
