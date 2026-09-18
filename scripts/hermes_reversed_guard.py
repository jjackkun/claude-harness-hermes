#!/usr/bin/env python3
"""결정화 철회 보류 판정 — 패턴 키와 겹치는 기억이 철회된 채인지 본다 (L-06).

결정화(hermes-crystallize)는 반복 패턴을 규칙으로 굳힌다. 그 패턴의 주제가 `memory_events` 에서
**철회(memory.retracted)된 채**라면 폐기된 방침이 규칙이 된다 — 그래서 결정화 전에 한 번 묻는다.

판정은 어휘·이벤트로만 한다(R3: 결정화 경로에 모델 호출 금지). 표준 라이브러리만 import 한다
(`.deprc` tier 0 — hermes-crystallize 가 tier 1 이라 그 아래여야 한다).

규칙:
  - 검색어(패턴 키에서 도출) 중 하나라도 `about` 또는 `body` 에 들어 있는 기억 이벤트를 "겹침" 으로 본다.
  - 겹치는 이벤트 가운데 **가장 최근(ts) 것이 철회**면 보류(hold). 철회 뒤 같은 주제가 다시 추가됐으면
    가장 최근이 added/revised 라 보류가 풀린다 — 사람이 다시 확정한 것이다.
  - 철회 이벤트 자체는 사유(body)만 있고 주제(about)가 비었을 수 있으므로, 철회가 가리키는(revises) 원 기억의
    about/body 로 겹침을 판단한다.
  - `memory_events` 표가 없으면 판정하지 않는다(None).

공개 함수 1개: reversal_hold
설계: docs/hermes-universe/design/skills/skill-lifecycle.md (L-06)
계획: docs/exec-plans/completed/2026-09-18-crystallize-reversed-guard.md
"""
import sqlite3

_RETRACTED = "memory.retracted"


def _has_memory_table(con) -> bool:
    return con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='memory_events'").fetchone() is not None


def _events(con) -> list:
    cur = con.execute(
        "SELECT memory_id, kind, about, revises, body, ts FROM memory_events ORDER BY ts, memory_id")
    names = [d[0] for d in cur.description]
    return [dict(zip(names, r)) for r in cur.fetchall()]


def _subject_text(event: dict, by_id: dict) -> str:
    """겹침 판단에 쓸 글 — 철회 이벤트는 원 기억의 글을 쓴다."""
    target = by_id.get(event.get("revises")) if event["kind"] == _RETRACTED else None
    src = target or event
    return " ".join(x for x in (src.get("about"), src.get("body")) if x).lower()


def _overlaps(text: str, terms: list) -> bool:
    return any(t and t.lower() in text for t in terms)


def _latest_overlap(events: list, terms: list) -> dict | None:
    """검색어와 겹치는 이벤트 중 가장 최근 것. 없으면 None."""
    by_id = {e["memory_id"]: e for e in events}
    matched = [e for e in events if _overlaps(_subject_text(e, by_id), terms)]
    return matched[-1] if matched else None


def _hold_record(latest: dict, events: list) -> dict:
    origin = next((e for e in events if e["memory_id"] == latest.get("revises")), {})
    return {
        "memory_id": latest["memory_id"],
        "retracts": latest.get("revises") or "",
        "about": origin.get("about") or latest.get("about") or "",
        "reason": latest.get("body") or "",
        "ts": latest.get("ts") or "",
    }


def reversal_hold(con: sqlite3.Connection, terms: list) -> dict | None:
    """보류해야 하면 {"memory_id", "retracts", "about", "reason", "ts"} 를, 아니면 None 을 돌려준다.
    memory_id 는 철회 이벤트, retracts 는 철회된 원 기억의 id 다.

    terms 는 패턴 키에서 도출한 검색어 목록(hermes-crystallize 의 search_terms). 빈 목록이면 None.
    """
    if not terms or not _has_memory_table(con):
        return None
    events = _events(con)
    latest = _latest_overlap(events, terms)
    if latest is None or latest["kind"] != _RETRACTED:
        return None
    return _hold_record(latest, events)
