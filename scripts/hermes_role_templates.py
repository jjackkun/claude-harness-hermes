#!/usr/bin/env python3
"""역할 템플릿(assets/templates/agent/roles/*.md) 읽기 — 목록·이름 검증·SOUL 절 추출 (계획 2026-09-20-role-templates 목표 3·4).

템플릿 파일 형식: frontmatter(name·origin·source_commit·description·tools·model·discipline_hint) + `## 역할 / ## 책임 경계 / ## 원칙 / ## 도구`.
설치본은 scripts/templates/agent/roles/, 공장은 assets/templates/agent/roles/. 표준 모듈만(tier 0).
공개 함수 4개: TemplateError · roles_dir · list_templates · load_template
"""
import os
import re

SECTIONS = ("역할", "책임 경계", "원칙", "도구")
_FM = re.compile(r"^---\n(.*?)\n---\n", re.S)


class TemplateError(ValueError):
    pass


def roles_dir(project: str = None) -> str:
    """설치본(scripts/templates/agent/roles) 이 있으면 그것, 없으면 공장 assets. 둘 다 없으면 빈 문자열."""
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [os.path.join(project or "", "scripts", "templates", "agent", "roles") if project else "",
                  os.path.join(here, "templates", "agent", "roles"),
                  os.path.join(os.path.dirname(here), "assets", "templates", "agent", "roles")]
    for c in candidates:
        if c and os.path.isdir(c):
            return c
    return ""


def _frontmatter(text: str) -> dict:
    m = _FM.match(text)
    out = {}
    if not m:
        return out
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            out[k.strip()] = v.strip()
    return out


def list_templates(project: str = None, discipline: str = None) -> list:
    """[{name, origin, description, discipline_hint}] 이름순. discipline 을 주면 hint 가 같은 것만."""
    d = roles_dir(project)
    if not d:
        return []
    out = []
    for fname in sorted(os.listdir(d)):
        if not fname.endswith(".md"):
            continue
        with open(os.path.join(d, fname), encoding="utf-8") as fh:
            fm = _frontmatter(fh.read())
        if discipline and fm.get("discipline_hint") != discipline:
            continue
        out.append({"name": fm.get("name") or fname[:-3], "origin": fm.get("origin", "?"),
                    "description": fm.get("description", ""), "discipline_hint": fm.get("discipline_hint", "")})
    return out


def load_template(project: str, name: str) -> dict:
    """{frontmatter, sections: {역할: str, 책임 경계: str, 원칙: str, 도구: str}}. 없으면 TemplateError."""
    if not re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", name or ""):
        raise TemplateError(f"템플릿 이름 꼴이 아니다: {name!r}")
    d = roles_dir(project)
    path = os.path.join(d, f"{name}.md") if d else ""
    if not (path and os.path.isfile(path)):
        raise TemplateError(f"역할 템플릿이 없다: {name} (목록: hermes-agent.py templates)")
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    fm = _frontmatter(text)
    body = _FM.sub("", text, count=1)
    sections = {}
    for title in SECTIONS:
        m = re.search(r"^## " + re.escape(title) + r"\n(.*?)(?=^## |\Z)", body, re.S | re.M)
        sections[title] = (m.group(1).strip() if m else "")
    return {"frontmatter": fm, "sections": sections, "path": path}
