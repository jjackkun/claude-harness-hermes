"""한 에이전트의 열린 인계 봉투를 우선순위 순으로 나열하는 것만 담당한다.

handoff-contract.md "같은 에이전트에게 동시에 여러 요청이 몰리면 지시 → 협업 → 요청 순으로
우선하고, 같은 종류 안에서는 먼저 온 것부터 처리한다(합의)". 열린 봉투 = task.assigned 가 있고
task.finished · handoff.declined · handoff.expired 가 없는 것. 되묻기(handoff.question) 중인 봉투는
답을 기다리는 것이라 대기열에 넣지 않는다.
(계획 2026-09-17-design-gaps-tier2 목표 6)
"""
import re
import sqlite3

PRIORITY = {"지시": 0, "협업": 1, "요청": 2}
# handoff.question 도 뺀다 — 답이 올 때까지 시작하지 않는 봉투다(handoff-contract.md §3). 답이 오면 보낸 쪽이
# 채운 봉투를 **새 handoff 로 다시 연다**(같은 task_id 재개 경로는 없다)는 것이 현재 구현의 전제(리뷰 LOW, 확인 필요).
_CLOSING = ("task.finished", "handoff.declined", "handoff.expired", "handoff.question")


def _kind(decision: str) -> str:
    m = re.search(r"kind=([^\s(]+)", decision or "")
    return m.group(1) if m else "요청"


def queue(db: str, agent: str) -> list:
    """agent(`agent:<id>`)에게 열린 봉투를 [{'task_id','kind','goal','ts'}] 로, 지시→협업→요청·선착순."""
    con = sqlite3.connect(db)
    try:
        assigned = con.execute(
            "SELECT task_id, ts, intent, decision FROM journal_events "
            "WHERE kind='task.assigned' ORDER BY ts, event_id").fetchall()
        closed = {t for (t,) in con.execute(
            "SELECT DISTINCT task_id FROM journal_events WHERE kind IN (%s)" % ",".join("?" * len(_CLOSING)),
            _CLOSING)}
        # 받는 쪽은 task.assigned 에 직접 적히지 않는다 — 봉투의 return_to 가 보내는 쪽이므로,
        # 받는 쪽은 evidence 가 아니라 summons/handoff 기록의 to 다. open_handoff 는 decision 에 to= 를 남긴다.
        # `to=` 는 `return_to=` 의 꼬리에도 들어 있다 — 부분 문자열로 보면 보낸 쪽의 대기열에 남의 봉투가
        # 뜬다(리뷰 HIGH). 앞에 return_ 이 없는 to= 만 본다.
        to_re = re.compile(r"(?<!return_)\bto=" + re.escape(agent) + r"(?=\s|$)")
        rows = [(t, ts, goal, dec) for t, ts, goal, dec in assigned
                if t not in closed and to_re.search(dec or "")]
    finally:
        con.close()
    items = [{"task_id": t, "kind": _kind(dec), "goal": goal, "ts": ts} for t, ts, goal, dec in rows]
    items.sort(key=lambda i: (PRIORITY.get(i["kind"], 2), i["ts"]))
    return items


__all__ = ["PRIORITY", "queue"]
