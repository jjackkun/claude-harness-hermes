#!/usr/bin/env python3
"""명부 에이전트의 slug(@agent-<slug> 로 부르는 영문 이름) 규칙만 담당한다.

Claude Code 는 `.claude/agents/*.md` 의 frontmatter `name` 으로 서브에이전트를 부르는데, 한글 name 은
`@` 멘션이 안 된다(2026-09-28 실측, claude 2.1.283). 그래서 명부 이름은 한글 그대로 두고 slug 를 따로 둔다.
  형식   영문 소문자로 시작, 소문자·숫자·`-`, 2~40자
  유일   명부 전체(은퇴자 포함)에서 하나 — 이름과 같은 이유로 재사용 금지(RV-17)
  예약   내장 에이전트 · main · 이미 깔린 에이전트 파일(.claude/agents · assets/agents) 이름
계획: docs/exec-plans/active/2026-09-28-agent-mention-bridge.md 목표 1

공개: SlugError · slug_problem · assign_slug
"""

import os
import re

_SLUG_RE = re.compile(r"^[a-z][a-z0-9-]{1,39}$")
_SLUG_RULE = "영문 소문자로 시작하고 a-z·0-9·- 만, 2~40자"
# Claude Code 내장 에이전트 이름(대소문자 무시로 비교) + 헤르메스의 main.
_BUILTIN = frozenset({"general-purpose", "explore", "plan", "statusline-setup", "claude-code-guide", "claude", "main"})
_AGENT_DIRS = (os.path.join(".claude", "agents"), os.path.join("assets", "agents"))


class SlugError(ValueError):
    """slug 규칙 위반 — 무엇이 왜 안 되는지 함께 알린다."""


def slug_problem(slug) -> str:
    """형식이 틀렸으면 이유, 맞으면 빈 문자열."""
    if not isinstance(slug, str) or not _SLUG_RE.match(slug):
        return f"slug '{slug}' 형식 오류 — {_SLUG_RULE}"
    return ""


def _installed_names(project: str) -> dict:
    """깔려 있는 에이전트 파일 이름 → 그 폴더."""
    found = {}
    for rel in _AGENT_DIRS:
        folder = os.path.join(project, rel)
        if os.path.isdir(folder):
            for fname in os.listdir(folder):
                if fname.endswith(".md"):
                    found.setdefault(fname[:-3], rel)
    return found


def assign_slug(roster: dict, agent: dict, slug: str, project: str) -> None:
    """agent 에 slug 를 붙인다(명부 dict 를 고침, 저장은 호출측). 규칙 위반이면 SlugError."""
    problem = slug_problem(slug)
    if problem:
        raise SlugError(problem)
    if slug.lower() in _BUILTIN:
        raise SlugError(f"slug '{slug}' 는 내장 에이전트·main 이름이라 쓸 수 없다")
    for other in roster["agents"]:
        if other is not agent and other.get("slug") == slug:
            raise SlugError(f"slug '{slug}' 는 이미 '{other['name']}' 의 것이다(은퇴자 포함 — 재사용 금지)")
    owned = {a.get("slug") for a in roster["agents"]}
    folder = _installed_names(project).get(slug)
    if folder and slug not in owned:
        raise SlugError(f"slug '{slug}' 는 {folder}/{slug}.md 에이전트와 겹친다 — 다른 이름을 고르십시오")
    agent["slug"] = slug
