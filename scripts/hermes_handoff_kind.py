"""봉투의 `kind`(지시 · 협업 · 요청)를 조직 관계에서 **기계가** 정한다 — handoff-contract.md §1·§2.

| 관계 | kind | 거절 |
|---|---|---|
| 위 → 아래(직급이 높음), 사람 → 에이전트 | 지시 | 못 함(규칙 위반이면 blocked) |
| 같은 수평 단위(unit) | 협업 | 가능(사유 필수) |
| 다른 수평 단위 | 요청 | 가능(사유 필수) |

둘 중 하나라도 명부에 없으면 판정 불가 → `요청` 으로 두고 `(미상)` 을 붙인다. 거절 가능한 쪽이
안전하다 — 지시로 두면 명부 밖 상대의 요구를 거절할 길이 없어진다.
(계획 2026-09-17-design-coverage-gaps 목표 5)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_org import OrgError, load_org  # noqa: E402
from hermes_roster import load_roster  # noqa: E402

KINDS = ("지시", "협업", "요청")
REFUSABLE = ("협업", "요청")


def _agent_org(project: str, actor: str) -> dict:
    """`agent:<id|이름>` 의 org. 사람·미등록이면 None."""
    if not actor or not actor.startswith("agent:"):
        return None
    key = actor.split(":", 1)[1]
    try:
        roster = load_roster(project)
    except (OSError, ValueError):
        return None
    for a in roster.get("agents", []):
        if a.get("agent_id") == key or a.get("name") == key:
            return a.get("org") or {}
    return None


def _rank_index(project: str, rank: str):
    try:
        ranks = list(load_org(project).get("rank") or [])
    except OrgError:
        ranks = []
    return ranks.index(rank) if rank in ranks else None


def derive_kind(project: str, frm: str, to: str) -> tuple:
    """(kind, 확정 여부). 확정이 아니면 호출측이 `(미상)` 을 표시한다."""
    if frm and frm.startswith("human:"):
        return "지시", True
    a, b = _agent_org(project, frm), _agent_org(project, to)
    if a is None or b is None:
        return "요청", False
    ra, rb = _rank_index(project, a.get("rank")), _rank_index(project, b.get("rank"))
    if ra is not None and rb is not None and ra < rb:      # rank 목록은 위에서 아래 순
        return "지시", True
    if a.get("unit") and a.get("unit") == b.get("unit"):
        return "협업", True
    return "요청", True


__all__ = ["KINDS", "REFUSABLE", "derive_kind"]
