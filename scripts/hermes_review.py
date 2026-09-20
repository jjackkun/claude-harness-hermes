#!/usr/bin/env python3
"""리뷰 봉투 닫기 — approved | corrected(about, body) 를 리뷰받은 에이전트의 기억으로 (C-21, 계획 2026-09-18-agent-teaching 목표 2·3).

리뷰 봉투를 finished 로 닫고(hermes_handoff.resolve), 리뷰받은 에이전트에 memory.added 를 남기며(hermes_review_chain.record_teaching),
같은 about 의 corrected 가 임계(3)에 닿으면 기존 결정화 루프(hermes-crystallize.py --agent)로 개인 스킬을 만든다.
handoff 와 review_chain 둘 다 위에 있는 상위 모듈 — 순환 없이 두 층을 잇는다.
공개 함수 2개: close_review · CORRECTED_THRESHOLD
"""
import os
import sqlite3
import subprocess
import sys

from hermes_handoff import resolve
from hermes_review_chain import TeachingError, _REVIEW_MARK, _assign_decision, check_about, record_teaching

CORRECTED_THRESHOLD = 3


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
    resolve(db, project, review_id, "finished", actor)
    mid = record_teaching(db, project, reviewee, about, text, f"review:{review_id}:{verdict}:{actor}")
    con = sqlite3.connect(db)
    try:
        n = con.execute("SELECT count(*) FROM memory_events WHERE agent_id=? AND about=? AND kind='memory.added' "
                        "AND source_event LIKE 'review:%:corrected:%'", (reviewee, about)).fetchone()[0]
    finally:
        con.close()
    crystallized = _maybe_crystallize(db, project, reviewee, about) if n >= CORRECTED_THRESHOLD else False
    return {"memory_id": mid, "reviewee": reviewee, "about": about, "corrected_count": n, "crystallized": crystallized}


def _maybe_crystallize(db: str, project: str, agent_id: str, about: str) -> bool:
    """같은 about 의 corrected 가 임계에 닿으면 기존 결정화 루프(hermes-crystallize.py --agent)로 개인 스킬을 만든다.
    철회 보류·junk 거부·이미 결정화는 그 루프가 판정한다. 실패해도 기억은 이미 남았다."""
    cli = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hermes-crystallize.py")
    try:
        done = subprocess.run([sys.executable, cli, "--db", db, "--crystallize", f"agent:{agent_id}:{about}",
                               "--project-dir", project, "--agent", agent_id],
                              capture_output=True, text=True, timeout=180)
        return "DONE:" in (done.stdout or "")
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"[hermes-review] 개인 스킬 결정화 실패(기억은 기록됨): {exc}", file=sys.stderr)
        return False
