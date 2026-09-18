"""에이전트를 우주 템플릿으로 보낼 본문을 모으는 것만 담당한다 — SOUL.md 본문 + 개인 스킬.

handoff-contract.md §5(H-09): 에이전트는 소우주 하나에만 있고, 다른 소우주에서 같은 실력이 필요하면
**우주 템플릿을 거쳐 복제**한다. 경계를 넘는 것은 SOUL(정체성·원칙·금지)과 개인 스킬뿐이고,
기억(MEMORY.md)·작업 이력·수습 성적은 **넣지 않는다** — 그 소우주의 사실이다.

SOUL 머리말(agent_id·created_by 같은 기계 칸)은 뗀다 — 복제본은 새 id 로 다시 태어난다.
소우주 이름·경로·티켓이 본문에 남아 있으면 호출측의 누출 게이트가 거부한다(여기서 판정하지 않는다).
(계획 2026-09-18-unplanned-decisions 목표 4)
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_roster import find_agent, load_roster  # noqa: E402


def _strip_frontmatter(text: str) -> str:
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            return text[end + 5:]
    return text


def _strip_name(text: str, name: str) -> str:
    """에이전트 이름은 소우주 사실이다(누출 게이트가 명부 이름을 잡는다) — 제목 줄은 '역할 템플릿' 으로,
    본문의 이름은 '이 역할' 로 바꾼다. 복제본은 B 소우주에서 새 이름·새 id 로 입사한다."""
    lines = []
    for line in text.splitlines():
        if line.strip() == f"# {name}":
            lines.append("# 역할 템플릿")
        else:
            lines.append(line.replace(name, "이 역할"))
    return "\n".join(lines)


def export_agent(project: str, who: str) -> dict:
    """{'agent_id','name','body'} — body 는 SOUL 본문과 개인 스킬을 이어 붙인 것. 명부에 없으면 KeyError."""
    agent = find_agent(load_roster(project), who)
    if agent is None:
        raise KeyError(f"명부에 없다: {who}")
    folder = os.path.join(project, ".hermes", "agents", agent["agent_id"])
    parts = []
    soul = os.path.join(folder, "SOUL.md")
    if os.path.isfile(soul):
        with open(soul, encoding="utf-8") as fh:
            parts.append(_strip_name(_strip_frontmatter(fh.read()), agent["name"]).strip())
    for path in sorted(glob.glob(os.path.join(folder, "skills", "*.md"))):
        with open(path, encoding="utf-8") as fh:
            parts.append(f"<!-- skill: {os.path.basename(path)} -->\n" + _strip_frontmatter(fh.read()).strip())
    # MEMORY.md · 이력 · 성적은 의도적으로 읽지 않는다(§5 표).
    return {"agent_id": agent["agent_id"], "name": agent["name"], "body": "\n\n".join(parts)}


__all__ = ["export_agent"]
