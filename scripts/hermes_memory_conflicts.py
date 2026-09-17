#!/usr/bin/env python3
"""기억 이벤트에서 충돌·규칙 충돌·단일 사례를 계산한다(읽기 전용, 파생).

판정 이름은 셋뿐이다(설계 4절). **최신 자동 승리는 없다** — 늦게 온 쪽이 이기지 않는다.
  갈라짐   같은 기억(revises 같음)을 각자 다르게 갱신 → 둘 다 표시              → "충돌"
  about 모순  같은 about 을 부정형으로 말하는 이벤트가 공존                      → "충돌"
  완전 중복  content_hash 같음 → 한 줄로 보이되 두 이벤트는 남는다              → "합침"

규칙 충돌(RV-11): 기억 about 이 규칙 키(SOUL·공통 규칙·소우주 R 룰)와 겹치고 본문이 부정형이면
"규칙 충돌" — 소환 시 기억보다 규칙을 먼저 읽게 한다. 근거가 하나뿐이면 "단일 사례"(승격 안 함).
계획: docs/exec-plans/active/2026-09-15-agent-identity.md 목표 8·9

공개 함수 4개: current_memories · find_conflicts · rule_conflicts · single_source
"""

import re

# 본문이 "부정형" 인지 — 규칙·다른 기억과 모순되는지 판정하는 약한 신호.
# 모델 호출 없이 어휘로만 본다(R3 회피). 틀리면 표시가 과할 뿐 데이터는 안전하다.
_NEGATION = re.compile(r"(않는다|않다|않는|안\s*된다|아니다|없다|금지|말라|말아야|틀렸|not\b|never\b|no longer)")


def _rows(con) -> list:
    cur = con.execute(
        "SELECT memory_id, kind, agent_id, about, revises, content_hash, source_event, body, ts "
        "FROM memory_events ORDER BY ts, memory_id")
    names = [d[0] for d in cur.description]
    return [dict(zip(names, r)) for r in cur.fetchall()]


def _retracted_ids(events: list) -> set:
    return {e["revises"] for e in events if e["kind"] == "memory.retracted" and e["revises"]}


def current_memories(con, agent_id: str = None) -> list:
    """지금 살아 있는 기억 — 철회된 것과 그 갱신 사슬은 뺀다. 최신 승리는 없다.

    같은 본문(content_hash)이 전에 철회된 적 있으면 previously_retracted 에 그 철회 사유를 붙인다
    (memory-events.md "철회는 흔적을 남긴다") — 다시 배워도 "전에 틀렸다" 가 보이게."""
    events = [e for e in _rows(con) if agent_id is None or e["agent_id"] == agent_id]
    retracted = _retracted_ids(events)
    reasons = _retracted_hash_reasons(events, retracted)
    return [{**e, "previously_retracted": reasons.get(e.get("content_hash"))}
            for e in events
            if e["kind"] != "memory.retracted" and e["memory_id"] not in retracted]


def _retracted_hash_reasons(events: list, retracted: set) -> dict:
    """철회된 기억의 content_hash → 철회 사유(memory.retracted 의 body)."""
    by_id = {e["memory_id"]: e for e in events}
    out = {}
    for e in events:
        if e["kind"] == "memory.retracted" and e["revises"] in by_id:
            h = by_id[e["revises"]].get("content_hash")
            if h:
                out[h] = e.get("body") or "사유 없음"
    return out


def find_conflicts(con, agent_id: str = None) -> list:
    """[{type, about|hash, memory_ids}] — 갈라짐·about 모순은 '충돌', 완전 중복은 '합침'."""
    events = current_memories(con, agent_id)
    out = []
    out += _diverged(events)
    out += _about_contradiction(events)
    out += _duplicates(events)
    return out


def _diverged(events: list) -> list:
    by_parent = {}
    for e in events:
        if e["kind"] == "memory.revised" and e["revises"]:
            by_parent.setdefault(e["revises"], []).append(e["memory_id"])
    return [{"type": "충돌", "reason": "갈라짐", "revises": parent, "memory_ids": sorted(ids)}
            for parent, ids in by_parent.items() if len(ids) > 1]


def _about_contradiction(events: list) -> list:
    by_about = {}
    for e in events:
        if e["about"]:
            by_about.setdefault(e["about"], []).append(e)
    return [{"type": "충돌", "reason": "about 모순", "about": about,
             "memory_ids": sorted(e["memory_id"] for e in group)}
            for about, group in by_about.items() if _has_both_polarities(group)]


def _has_both_polarities(group: list) -> bool:
    """한 about 에 긍정형과 부정형이 함께 있으면 모순이다."""
    neg = any(e["body"] and _NEGATION.search(e["body"]) for e in group)
    pos = any(e["body"] and not _NEGATION.search(e["body"]) for e in group)
    return neg and pos


def _duplicates(events: list) -> list:
    by_hash = {}
    for e in events:
        if e["content_hash"]:
            by_hash.setdefault(e["content_hash"], []).append(e["memory_id"])
    return [{"type": "합침", "reason": "완전 중복", "content_hash": h, "memory_ids": sorted(ids)}
            for h, ids in by_hash.items() if len(ids) > 1]


def rule_conflicts(con, rule_keys, agent_id: str = None) -> list:
    """about 이 규칙 키와 겹치고 본문이 부정형인 기억 — 규칙이 이긴다(RV-11)."""
    keys = set(rule_keys or [])
    out = []
    for e in current_memories(con, agent_id):
        if e["about"] in keys and e["body"] and _NEGATION.search(e["body"]):
            out.append({"type": "규칙 충돌", "about": e["about"], "memory_id": e["memory_id"]})
    return out


def single_source(con, agent_id: str = None) -> list:
    """source_event 가 하나뿐인 기억 — '단일 사례'. 두 번째 근거 전까지 규칙 승격 금지."""
    by_about = {}
    for e in current_memories(con, agent_id):
        if e["about"] and e["source_event"]:
            by_about.setdefault(e["about"], set()).add(e["source_event"])
    return [{"type": "단일 사례", "about": about} for about, srcs in by_about.items() if len(srcs) == 1]
