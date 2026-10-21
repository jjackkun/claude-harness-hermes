#!/usr/bin/env python3
"""서브에이전트 호출이 어느 모델로 도는지 정해져 있는지 가른다 (R-cost G2).

근거: docs/exec-plans/active/2026-10-21-cost-guard-plan.md 목표 G2
      (모델을 지정하지 않은 내장 general-purpose 24개가 부모 모델 Opus 로 돌았다)

단일 책임: Agent 도구 입력 → 정해진 모델 이름, 못 정하면 None.

찾는 순서: tool_input.model → 환경변수 CLAUDE_CODE_SUBAGENT_MODEL → 정의 파일의 `model:` —
  프로젝트 .claude/agents/ → 전역 ~/.claude/agents/ →
  플러그인 `플러그인:이름` 은 ~/.claude/plugins/installed_plugins.json 의 installPath/agents/.
  폴더는 하위까지 보고, 정의는 머리말 `name:` 또는 파일 이름으로 맞춘다 — Claude Code 가
  에이전트를 `name:` 으로 부르고 하위 폴더도 읽기 때문이다(리뷰 지적).
내장 타입(general-purpose·Explore·Plan·claude)은 정의 파일이 없으므로 None —
기본 모델을 가정하지 않는다(계획 §6). fork 는 부모 모델을 쓰는 것이 정의된 동작이다.
"""

import json
import os
import re

_FORK = "fork"
# 정의 머리말(--- … ---) 안의 model: 줄
_MODEL_LINE = re.compile(r"^model:\s*(\S+)", re.MULTILINE)
_NAME_LINE = re.compile(r"^name:\s*(\S+)", re.MULTILINE)
# 타입 이름이 경로로 새지 않게 — 이름에 쓰이는 글자만
_SAFE_NAME = re.compile(r"^[A-Za-z0-9_.-]+$")


def _front(path):
    """정의 머리말의 (name, model). 없는 값은 None."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read(8192)
    except OSError:
        return None, None
    if not text.startswith("---"):
        return None, None
    end = text.find("\n---", 3)
    head = text[3:end if end > 0 else len(text)]
    found = [rx.search(head) for rx in (_NAME_LINE, _MODEL_LINE)]
    return tuple(m.group(1).strip("\"'") if m else None for m in found)


def _find_in(folder, name):
    """folder 아래(하위 포함)에서 name 에 맞는 정의를 찾아 (찾음, model)."""
    for root, _dirs, files in sorted(os.walk(folder)):
        for fn in sorted(files):
            if not fn.endswith(".md"):
                continue
            front_name, model = _front(os.path.join(root, fn))
            if front_name == name or (front_name is None and fn[:-3] == name):
                return True, model
    return False, None


def _plugin_dirs(plugin, home):
    try:
        with open(os.path.join(home, ".claude", "plugins", "installed_plugins.json"), encoding="utf-8") as f:
            plugins = json.load(f).get("plugins", {})
    except (OSError, ValueError, AttributeError):
        return []
    dirs = []
    for key, entries in plugins.items():
        if key.split("@", 1)[0] != plugin or not isinstance(entries, list):
            continue
        dirs += [e.get("installPath") for e in entries if isinstance(e, dict) and e.get("installPath")]
    return dirs


def _search_dirs(subagent_type, project_dir, home):
    """(찾을 폴더 목록, 정의 안의 이름). 이름이 안전하지 않으면 폴더 없음."""
    if ":" in subagent_type:
        plugin, name = subagent_type.split(":", 1)
        if not (_SAFE_NAME.match(plugin) and _SAFE_NAME.match(name)):
            return [], name
        return [os.path.join(d, "agents") for d in _plugin_dirs(plugin, home)], name
    if not _SAFE_NAME.match(subagent_type):
        return [], subagent_type
    return [os.path.join(project_dir, ".claude", "agents"),
            os.path.join(home, ".claude", "agents")], subagent_type


def resolve(tool_input, project_dir, home):
    """정해진 모델 이름(fork 는 "parent"), 못 정하면 None."""
    ti = tool_input if isinstance(tool_input, dict) else {}
    if isinstance(ti.get("model"), str) and ti["model"].strip():
        return ti["model"].strip()
    if os.environ.get("CLAUDE_CODE_SUBAGENT_MODEL", "").strip():
        return os.environ["CLAUDE_CODE_SUBAGENT_MODEL"].strip()
    subagent_type = ti.get("subagent_type") or "general-purpose"
    if subagent_type == _FORK:
        return "parent"
    folders, name = _search_dirs(str(subagent_type), project_dir, home)
    for folder in folders:
        found, model = _find_in(folder, name) if os.path.isdir(folder) else (False, None)
        if found:
            return model  # 먼저 찾은 정의가 이긴다 — model 이 없으면 None
    return None
