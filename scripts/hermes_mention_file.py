#!/usr/bin/env python3
"""명부 에이전트의 `.claude/agents/<slug>.md`(@agent-<slug> 로 부르는 얇은 파일)를 명부와 맞추는 것만 담당한다.

파일에는 이름·설명·도구·모델만 둔다. SOUL·기억은 **넣지 않는다** — 부를 때마다 SubagentStart 훅이 최신본을 넣는다
(creation-and-organization.md §1: 개인은 "소환될 때마다 폴더를 읽고 출근". 파일에 굳히면 기억이 낡는다).
  만든다   slug 가 있고 은퇴하지 않은 에이전트
  지운다   은퇴자 · 명부에 없는 slug 의 생성물(고아). 표지(MARKER) 없는 파일은 사람 것이라 건드리지 않는다
도구·모델은 입사 템플릿(역할 템플릿)에서 물려받되, Claude Code 가 모르는 값이면 칸을 비운다(= 부모 설정 상속).
계획: docs/exec-plans/active/2026-09-28-agent-mention-bridge.md 목표 2

공개: MARKER · render_mention_file · sync_mention_files
"""

import os

from hermes_role_templates import TemplateError, load_template

MARKER = "hermes-mention-file"
_AGENTS_DIR = os.path.join(".claude", "agents")
# Claude Code 서브에이전트 frontmatter 가 받는 값만 옮긴다 — 템플릿 출처(ECC·cumora)마다 표기가 달라서.
_TOOLS = frozenset({"Read", "Write", "Edit", "MultiEdit", "Grep", "Glob", "Bash", "WebFetch", "WebSearch",
                    "NotebookEdit", "TodoWrite", "Agent", "Task"})
_MODELS = frozenset({"sonnet", "opus", "haiku", "inherit"})


def _template_fields(project: str, agent: dict) -> dict:
    name = (agent.get("template") or "").split("@")[0]
    if not name:
        return {}
    try:
        fm = load_template(project, name)["frontmatter"]
    except TemplateError:
        return {}                                  # 템플릿이 사라졌으면 상속 없이 — 파일은 그래도 만든다
    out = {}
    tools = [t.strip() for t in (fm.get("tools") or "").split(",") if t.strip()]
    if tools and all(t in _TOOLS for t in tools):
        out["tools"] = ", ".join(tools)
    if fm.get("model") in _MODELS:
        out["model"] = fm["model"]
    return out


def render_mention_file(project: str, agent: dict) -> str:
    """에이전트 하나의 파일 본문. 같은 명부·템플릿이면 늘 같은 글자(멱등)."""
    org = agent.get("org") or {}
    org_text = "/".join(org.get(k) or "-" for k in ("discipline", "rank", "unit"))
    lines = ["---", f"name: {agent['slug']}",
             f"description: 명부 에이전트 \"{agent['name']}\" ({org_text}). "
             f"사용자가 이 이름(\"{agent['name']}\")으로 부르거나 그에게 일을 맡기면 이 에이전트를 쓴다."]
    lines += [f"{k}: {v}" for k, v in _template_fields(project, agent).items()]
    lines += ["---",
              f"<!-- {MARKER}: 생성물 — 손으로 고치지 말 것. 원본 .hermes/agents.json "
              "(python3 scripts/hermes-agent.py sync-mention-files) -->",
              f"너는 헤르메스 명부 에이전트 \"{agent['name']}\" (agent:{agent['agent_id']}) 다.",
              "정체성(SOUL)과 기억(MEMORY)은 불릴 때마다 훅이 이 대화 앞에 넣는다 — \"[헤르메스 출근]\" 으로 시작한다.",
              "그 주입이 보이지 않으면 답의 첫 줄에 \"정체성 주입 없음\" 이라고 알리고 일반 규칙으로 일한다.", ""]
    return "\n".join(lines)


def _is_generated(path: str) -> bool:
    try:
        with open(path, encoding="utf-8") as fh:
            return MARKER in fh.read(4096)
    except OSError:
        return False


def _write_one(path: str, body: str) -> str:
    """"written" · "same" · "skipped"(같은 이름의 사람 파일 — 덮어쓰지 않는다)."""
    if os.path.isfile(path):
        if not _is_generated(path):
            return "skipped"
        with open(path, encoding="utf-8") as fh:
            if fh.read() == body:
                return "same"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(body)
    return "written"


def _remove_orphans(folder: str, keep: set) -> list:
    """keep 에 없는 생성물(표지 있는 파일)만 지운다. 사람 파일·공장 에이전트는 표지가 없어 남는다."""
    if not os.path.isdir(folder):
        return []
    removed = []
    for fname in sorted(os.listdir(folder)):
        path = os.path.join(folder, fname)
        if fname.endswith(".md") and fname[:-3] not in keep and _is_generated(path):
            os.remove(path)
            removed.append(fname[:-3])
    return removed


def sync_mention_files(project: str, roster: dict) -> dict:
    """명부와 파일을 맞춘다. {"written", "removed", "skipped"} 는 slug 목록 — 두 번째 호출은 written·removed 가 빈다.
    skipped: 같은 이름의 사람 파일(표지 없음)이 있어 덮어쓰지 않은 slug."""
    folder = os.path.join(project, _AGENTS_DIR)
    want = {a["slug"]: a for a in roster["agents"] if a.get("slug") and a.get("status") != "retired"}
    out = {"written": [], "removed": [], "skipped": []}
    for slug, agent in sorted(want.items()):
        state = _write_one(os.path.join(folder, f"{slug}.md"), render_mention_file(project, agent))
        if state != "same":
            out[state].append(slug)
    out["removed"] = _remove_orphans(folder, set(want))
    return out
