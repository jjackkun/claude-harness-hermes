#!/usr/bin/env python3
"""SOUL.md 초안 — 기계가 이미 아는 것(이름·분야·직급·조직·조직 코드 경로·직무 템플릿)으로 틀의 빈 자리를 채운다 (계획 agent-hire-form 목표 5 재정의).

사람에게 세 답을 받지 않는다(cumora 는 에이전트 자신이, ECC 는 미리 쓴 역할 템플릿이 쓴다 — 2026-09-20 대조). 승인은 여전히 사람 몫(D-01):
초안에는 "초안" 표시 줄이 남고, 사람이 고친 SOUL(표시 줄 없음)은 절대 덮지 않는다. 모델 호출 0(R3).
역할 템플릿(`--template`, 계획 2026-09-20-role-templates 목표 4)이 있으면 그 절(역할·책임 경계·원칙·도구)을 조직 문장 뒤에 잇는다.
공개 함수 2개: draft_soul · is_untouched_draft
"""
import os

from hermes_org import OrgError, load_org
from hermes_role_templates import TemplateError, load_template

DRAFT_MARK = "> 초안 — 기계가 조직 값에서 채웠다. 사람이 읽고 고친 뒤 이 줄을 지우면 승인이다(D-01)."
_ROLE_PH = "(이 에이전트가 맡는 일 한 문단. 직무 템플릿 `{TEMPLATE}` 의 역할을 이 소우주에 맞게 좁힌다.)"
_TOOLS_PH = "(이 역할이 쓰는 도구·스킬. 개인 스킬은 `skills/` 에.)"


def _unit_paths(project: str, unit: str) -> list:
    try:
        spec = (load_org(project).get("unit") or {}).get(unit) or {}
    except OrgError:
        return []
    return list(spec.get("code") or []) if isinstance(spec, dict) else []


def _role_paragraph(agent: dict, paths: list) -> str:
    org = agent.get("org") or {}
    d, r, u = org.get("discipline"), org.get("rank"), org.get("unit")
    parts = []
    parts.append(f"{u} 조직에서 " if u else "")
    parts.append(f"{d} 을(를) 맡는 " if d else "")
    parts.append(f"{r}" if r else "담당")
    head = "".join(parts) + "이다."
    tmpl = (agent.get("template") or "").split("@")[0]
    body = f" 직무 템플릿 `{tmpl}` 의 역할을 이 소우주에 맞게 좁혀 맡는다." if tmpl else ""
    scope = f" 맡는 코드 경로는 {', '.join(f'`{p}`' for p in paths)} 이다." if paths else ""
    return head + body + scope + " 봉투(goal·done_when)로 받은 일을 끝내고, 끝나면 배운 것 한 줄을 남긴다."


def _template_sections(project: str, agent: dict) -> dict:
    """agent.template("<이름>@factory") 의 역할 템플릿 절. 없거나 못 읽으면 빈 dict — 초안은 조직 값만으로 선다."""
    name = (agent.get("template") or "").split("@")[0]
    if not name:
        return {}
    try:
        return load_template(project, name)["sections"]
    except TemplateError:
        return {}


def _merge_template(soul: str, sections: dict) -> str:
    """각 `## 절` 의 조직 문장 뒤에 템플릿 절 본문을 잇는다. 절이 없으면 건너뛴다."""
    for title, body in sections.items():
        if not body:
            continue
        head = f"\n## {title}\n"
        start = soul.find(head)
        if start < 0:
            continue
        nxt = soul.find("\n## ", start + len(head))
        end = len(soul) if nxt < 0 else nxt
        soul = soul[:end].rstrip("\n") + f"\n\n{body.strip()}\n" + soul[end:]
    return soul


def draft_soul(project: str, agent: dict, template_text: str) -> str:
    """틀 문자열의 {{자리}} 와 괄호 안내를 조직 값으로 채우고, 역할 템플릿 절을 이은 초안."""
    org = agent.get("org") or {}
    paths = _unit_paths(project, org.get("unit")) if org.get("unit") else []
    fill = {"AGENT_ID": agent["agent_id"], "NAME": agent["name"], "STATUS": agent.get("status", "probation"),
            "ORG": str(org), "TEMPLATE": (agent.get("template") or "(없음)"),
            "CREATED_AT": agent.get("created_at", ""), "CREATED_BY": agent.get("created_by", "")}
    soul = template_text
    for key, value in fill.items():
        soul = soul.replace("{{" + key + "}}", value)
    soul = soul.replace(_ROLE_PH.replace("{TEMPLATE}", fill["TEMPLATE"]), _role_paragraph(agent, paths))
    does = f"- 한다: {org.get('unit') or '이 소우주'} 의 {org.get('discipline') or '맡은 분야'} 일" + (f" — 경로 {', '.join(paths)}" if paths else "")
    dont = f"- 하지 않는다(다른 담당에게 넘긴다): 다른 조직의 코드, {org.get('discipline') or '맡은 분야'} 밖의 판단, 사람 승인이 필요한 일(은퇴·설정·비밀값)"
    soul = soul.replace("- 한다:\n- 하지 않는다(다른 담당에게 넘긴다):", f"{does}\n{dont}")
    tools = "- 조직 층 스킬(unit)과 개인 스킬(`skills/`) · `hermes-agent.py note` 로 배운 것 기록 · 봉투 닫기(`resolve`)"
    soul = soul.replace(_TOOLS_PH, tools)
    soul = _merge_template(soul, _template_sections(project, agent))
    marker = f"\n{DRAFT_MARK}\n"
    head_end = soul.find("\n---", 4)
    if head_end > 0:
        nl = soul.find("\n", head_end + 4)
        soul = soul[:nl + 1] + marker + soul[nl + 1:]
    return soul


def is_untouched_draft(soul_path: str) -> bool:
    """초안 표시 줄이 남아 있거나(승인 전) 틀의 괄호 안내가 그대로면 True — 그때만 다시 채울 수 있다."""
    if not os.path.isfile(soul_path):
        return True
    with open(soul_path, encoding="utf-8") as fh:
        text = fh.read()
    return DRAFT_MARK in text or "(이 에이전트가 맡는 일 한 문단." in text
