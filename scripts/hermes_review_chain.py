#!/usr/bin/env python3
"""리뷰가 기억이 되는 경로 (C-21·C-22, 계획 2026-09-18-agent-teaching).

- 하급자가 봉투를 finished 로 닫으면 같은 unit 의 바로 위 rank 에게 `review` 봉투가 자동으로 열린다(위 rank 없으면 human).
- 리뷰어가 approved / corrected(about, body) 로 닫으면 **리뷰받은 에이전트의 memory_events** 에 memory.added 가 남고 MEMORY.md 가 다시 만들어진다.
- 사람의 가르침(teach)도 같은 기록기를 쓴다. `about` 은 `<domain>/<slug>` 만 받는다 — 주제 없는 문장은 결정화 키가 못 된다(C-22).
- 본문은 기록 직전 마스킹(T-20). 같은 about 의 corrected 가 3회면 개인 스킬 결정화 후보다(누적 수를 돌려준다).

리뷰 봉투는 새 journal kind 가 아니라 task.assigned 에 intent "리뷰: …" + decision `constraints=review-of=<원 봉투>;reviewee=<id>;verified=<판정>` 으로 표시한다
(kind CHECK 마이그레이션을 피한다). 순환 import 를 피해 hermes_handoff 는 함수 안에서 늦게 부른다(같은 tier 2).
공개 함수 6개: TeachingError · check_about · reviewer_for · open_review · close_review · record_teaching
"""
import re
import sqlite3
from datetime import datetime, timezone

from hermes_memory_events import ensure_memory_schema, record
from hermes_memory_view import write_memory_md
from hermes_org import OrgError, load_org
from hermes_roster import load_roster
from hermes_universe import universe_id
from hermes_uuid7 import uuid7_str
try:
    from hermes_redact import redact
except ImportError:            # 옛 설치본
    redact = None

ABOUT_DOMAINS = ("gate", "test", "git", "debug", "workflow", "file", "sync", "agent")
_ABOUT = re.compile(r"^(%s)/[A-Za-z0-9][A-Za-z0-9._-]{0,127}$" % "|".join(ABOUT_DOMAINS))
_REVIEW_MARK = re.compile(r"review-of=([0-9a-f-]{36});reviewee=([0-9a-f-]{36})")
CORRECTED_THRESHOLD = 3


class TeachingError(ValueError):
    pass


def check_about(about: str) -> str:
    """`<domain>/<slug>` 형식만 — domain 은 고정 집합, slug 는 kebab/점/밑줄 128자 이하. 아니면 TeachingError."""
    about = (about or "").strip()
    if not _ABOUT.match(about):
        raise TeachingError(f"about 은 <domain>/<slug> 꼴이어야 한다(domain: {', '.join(ABOUT_DOMAINS)}): {about[:60]!r}")
    return about


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _agent_of(project: str, actor_or_id: str) -> dict:
    key = actor_or_id.split(":", 1)[1] if actor_or_id.startswith("agent:") else actor_or_id
    for a in load_roster(project).get("agents", []):
        if a.get("agent_id") == key or a.get("name") == key:
            return a
    return None


def reviewer_for(project: str, agent_id: str) -> str:
    """같은 unit 에서 바로 위 rank 의 에이전트(은퇴자 제외). 없으면 더 위로, 그래도 없으면 'human'."""
    me = _agent_of(project, agent_id)
    if not me:
        return "human"
    org = me.get("org") or {}
    try:
        ranks = list(load_org(project).get("rank") or [])
    except OrgError:
        ranks = []
    if org.get("rank") not in ranks:
        return "human"
    idx = ranks.index(org["rank"])
    agents = [a for a in load_roster(project).get("agents", []) if a.get("status") != "retired"]
    for higher in reversed(ranks[:idx]):                       # 바로 위부터 한 칸씩
        for a in sorted(agents, key=lambda x: x.get("created_at") or ""):
            o = a.get("org") or {}
            if o.get("rank") == higher and o.get("unit") == org.get("unit"):
                return f"agent:{a['agent_id']}"
    return "human"


def _assign_decision(db: str, handoff_id: str) -> str:
    con = sqlite3.connect(db)
    try:
        row = con.execute("SELECT decision, intent FROM journal_events WHERE task_id=? AND kind='task.assigned' "
                          "ORDER BY ts LIMIT 1", (handoff_id,)).fetchone()
    finally:
        con.close()
    return row or ("", "")


def open_review(db: str, project: str, handoff_id: str, finished_actor: str, verified: str = "none") -> str:
    """finished 뒤 자동 개봉. 리뷰 봉투 자체가 닫힌 것이거나 행위자가 명부 밖이면 None."""
    decision, intent = _assign_decision(db, handoff_id)
    if _REVIEW_MARK.search(decision or ""):
        return None                                            # 리뷰의 리뷰는 열지 않는다
    me = _agent_of(project, finished_actor) if finished_actor.startswith("agent:") else None
    if not me:
        return None
    to = reviewer_for(project, me["agent_id"])
    from hermes_handoff import open_handoff                    # 같은 tier — 늦게 불러 순환을 피한다
    env = {"goal": f"리뷰: {(intent or '')[:150]}", "done_when": "manual", "inputs": [handoff_id],
           "constraints": f"review-of={handoff_id};reviewee={me['agent_id']};verified={verified}"}
    return open_handoff(db, project, to, env, parent_task_id=handoff_id, by="system:review-chain")


def record_teaching(db: str, project: str, agent_id: str, about: str, body: str, source_event: str) -> str:
    """기억 이벤트 한 건(memory.added) + MEMORY.md 재생성. about 형식 검사·본문 마스킹은 여기서. memory_id 를 돌려준다."""
    about = check_about(about)
    body = (body or "").strip()
    if not body:
        raise TeachingError("본문(한 줄)이 비었다")
    if redact is not None:
        body = redact(body, project_dir=project)
    con = sqlite3.connect(db)
    try:
        ensure_memory_schema(con)
        mid = record(con, {"memory_id": uuid7_str(), "kind": "memory.added", "agent_id": agent_id,
                           "universe_id": universe_id(project), "ts": _now(), "about": about,
                           "body": body[:500], "source_event": source_event})
        con.commit()
        agent = _agent_of(project, agent_id) or {}
        write_memory_md(con, project, agent_id, agent.get("name"))
    finally:
        con.close()
    return mid


def close_review(db: str, project: str, review_id: str, verdict: str, actor: str,
                 about: str = None, body: str = None) -> dict:
    """approved | corrected(about, body). 리뷰 봉투를 finished 로 닫고 리뷰받은 에이전트의 기억에 남긴다.
    돌려주는 것: {memory_id, reviewee, about, corrected_count} — corrected_count 가 CORRECTED_THRESHOLD 면 개인 스킬 결정화 후보."""
    if verdict not in ("approved", "corrected"):
        raise TeachingError(f"판정은 approved 또는 corrected: {verdict}")
    decision, _ = _assign_decision(db, review_id)
    m = _REVIEW_MARK.search(decision or "")
    if not m:
        raise TeachingError("리뷰 봉투가 아니다(review-of 표시 없음)")
    reviewee = m.group(2)
    about = check_about(about)
    if verdict == "corrected" and not (body or "").strip():
        raise TeachingError("corrected 는 지적 한 줄(body)이 필요하다")
    text = body if verdict == "corrected" else (body or f"{about} 가 맞았다 (리뷰 승인)")
    from hermes_handoff import resolve                         # 같은 tier — 늦게
    resolve(db, project, review_id, "finished", actor)
    mid = record_teaching(db, project, reviewee, about, text, f"review:{review_id}:{verdict}:{actor}")
    con = sqlite3.connect(db)
    try:
        n = con.execute("SELECT count(*) FROM memory_events WHERE agent_id=? AND about=? AND kind='memory.added' "
                        "AND source_event LIKE 'review:%:corrected:%'", (reviewee, about)).fetchone()[0]
    finally:
        con.close()
    return {"memory_id": mid, "reviewee": reviewee, "about": about, "corrected_count": n}
