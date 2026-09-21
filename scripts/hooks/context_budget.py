#!/usr/bin/env python3
"""세션이 시작하며 내는 **고정 비용**을 항목별로 센다. R-out 의 옆자리 — 그쪽은 턴 중 유입, 이쪽은 시작 비용.

두 표로 나누는 것이 이 도구의 핵심이다:

  항상 로드   CLAUDE.md · 룰 문서 · 스킬 **설명** · 에이전트 **설명**
  필요할 때   스킬 본문(호출 시) · 에이전트 본문(dispatch 시) · 결정화 스킬(턴마다 선별 주입)

첫 측정에서 에이전트 **본문** 34 KB 를 고정 비용에 넣었다가 정정했다(2026-09-21). 본문은 dispatch 때만 들어오고
설명만 늘 들어온다 — 둘을 섞으면 "줄일 곳" 을 엉뚱하게 가리킨다.

토큰은 **바이트÷3** 근사다. 정확한 토크나이저는 쓰지 않는다(모델 호출 0, R3). 이 표의 쓸모는 항목 간 비교이지
절대값이 아니다 — 한글 위주 문서에서 대략 맞고, 영어가 많으면 과대평가한다.

사용:
  context_budget.py --root DIR            사람이 읽는 두 표
  context_budget.py --root DIR --json     기계용(대시보드 합류)
"""
import glob
import json
import os
import sys

BYTES_PER_TOKEN = 3


def _size(paths):
    return sum(os.path.getsize(p) for p in paths if os.path.isfile(p))


def _description_bytes(path):
    """frontmatter 의 `description:` 한 항목(이어지는 들여쓴 줄 포함) 크기. 본문은 세지 않는다."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            head = fh.read(16384)
    except OSError:
        return 0
    if not head.startswith("---"):
        return 0
    parts = head.split("---", 2)
    if len(parts) < 3:
        return 0
    total, grabbing = 0, False
    for line in parts[1].splitlines():
        if line.startswith("description:"):
            grabbing = True
            total += len(line.encode())
        elif grabbing and (line.startswith(" ") or line.startswith("\t")):
            total += len(line.encode())
        elif grabbing:
            break
    return total


def _entry(byte_count, item_count):
    return {"bytes": byte_count, "tokens": byte_count // BYTES_PER_TOKEN, "items": item_count}


def collect(root="."):
    """{always, on_demand, always_total, on_demand_total, root} — 읽기 전용."""
    rules = glob.glob(os.path.join(root, ".claude", "rules", "**", "*.md"), recursive=True)
    global_rules = glob.glob(os.path.expanduser("~/.claude/rules/common/*.md"))
    skills = glob.glob(os.path.join(root, ".claude", "skills", "*", "SKILL.md"))
    agents = glob.glob(os.path.join(root, ".claude", "agents", "*.md"))
    local_skills = glob.glob(os.path.join(root, ".hermes", "skills", "*.md"))
    claude_md = [p for p in (os.path.join(root, "CLAUDE.md"), os.path.join(root, "AGENTS.md")) if os.path.isfile(p)]

    always = {
        "CLAUDE.md": _entry(_size(claude_md), len(claude_md)),
        "프로젝트 룰": _entry(_size(rules), len(rules)),
        "전역 룰(~/.claude/rules/common)": _entry(_size(global_rules), len(global_rules)),
        "스킬 설명": _entry(sum(_description_bytes(p) for p in skills), len(skills)),
        "에이전트 설명": _entry(sum(_description_bytes(p) for p in agents), len(agents)),
    }
    on_demand = {
        "스킬 본문(호출 시)": _entry(_size(skills), len(skills)),
        "에이전트 본문(dispatch 시)": _entry(_size(agents), len(agents)),
        "결정화 스킬(턴마다 선별 주입)": _entry(_size(local_skills), len(local_skills)),
    }
    return {
        "root": os.path.abspath(root),
        "always": always,
        "on_demand": on_demand,
        "always_total": sum(v["bytes"] for v in always.values()),
        "on_demand_total": sum(v["bytes"] for v in on_demand.values()),
    }


def _render(data):
    lines = []
    for title, key, total_key in (("【항상 로드 — 세션 고정 비용】", "always", "always_total"),
                                  ("【필요할 때만】", "on_demand", "on_demand_total")):
        lines.append(title)
        for name, v in sorted(data[key].items(), key=lambda x: -x[1]["bytes"]):
            lines.append("  %-34s %8d B  ≈%6d 토큰  (%d개)" % (name, v["bytes"], v["tokens"], v["items"]))
        total = data[total_key]
        lines.append("  %-34s %8d B  ≈%6d 토큰" % ("합계", total, total // BYTES_PER_TOKEN))
    lines.append("※ 토큰은 바이트÷3 근사 — 항목 간 비교용이지 절대값이 아니다.")
    return "\n".join(lines)


def main(argv):
    root = argv[argv.index("--root") + 1] if "--root" in argv else "."
    data = collect(root)
    print(json.dumps(data, ensure_ascii=False, indent=2) if "--json" in argv else _render(data))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as exc:  # noqa: BLE001 — 판정 불가는 2
        print("context_budget: %s" % exc, file=sys.stderr)
        sys.exit(2)
