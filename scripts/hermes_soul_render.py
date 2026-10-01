#!/usr/bin/env python3
"""명부 에이전트 하나의 출근 본문(머리 한 줄 + SOUL.md + 선별 기억)을 문자열로 만드는 것만 담당한다.

세션 시작 훅(claude-sessionstart-agent-soul.sh)의 파이썬 heredoc 을 그대로 옮겼다 — 서브에이전트 훅
(SubagentStart, @agent-<slug>)도 같은 본문을 넣어야 해서 한 곳에 둔다. 동작은 옮기기 전과 같다.
  넣지 않음(None)  명부를 못 읽음 · 명부에 없는 id · 은퇴자
  상한             SOUL.md · MEMORY.md 각 cap 바이트, UTF-8 글자 중간에서 끊지 않고 잘림 줄에 원문 경로
  기억             핀 → 이번 과제(task_hint) 관련 → 최근. DB·선별이 안 되면 MEMORY.md 파일 그대로
경고는 stderr 에 "[agent-soul WARN] …" 로 — 훅이 로그에 옮긴다.
계획: docs/exec-plans/active/2026-09-28-agent-mention-bridge.md 목표 4

공개: render_soul · main
"""

import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from hermes_agent_summaries import render_agent_summaries  # C-29 — 나와 나눈 대화 요약
except ImportError:  # 헬퍼 미복사 — 대화 구획 없이 출근한다
    def render_agent_summaries(project, agent_id):
        return ""


def _warn(msg: str) -> None:
    print(f"[agent-soul WARN] {msg}", file=sys.stderr)


def _find_agent(project: str, agent_id: str):
    """명부의 그 에이전트. 못 읽거나 없으면 경고 후 None."""
    try:
        roster = json.load(open(os.path.join(project, ".hermes", "agents.json"), encoding="utf-8"))
    except (OSError, ValueError) as exc:
        _warn(f"명부를 읽지 못해 정체성을 넣지 않습니다: {exc}")
        return None
    agents = roster.get("agents", roster) if isinstance(roster, dict) else roster
    for a in (agents.values() if isinstance(agents, dict) else agents):
        if isinstance(a, dict) and a.get("agent_id") == agent_id:
            return a
    _warn(f"명부에 없는 id, 정체성을 넣지 않습니다: {agent_id}")
    return None


def _cut(data: bytes, cap: int, source: str) -> str:
    cut = data[:cap].decode("utf-8", "ignore")
    return cut + f"\n[…잘림 {len(data) - len(cut.encode('utf-8'))} B — 원문 {source}]\n"


def _clipped(path: str, cap: int, project: str):
    try:
        data = open(path, "rb").read()
    except OSError:
        return None
    if len(data) <= cap:
        return data.decode("utf-8", "replace")
    return _cut(data, cap, os.path.relpath(path, project))


def _selected_memory(project: str, agent: dict, task_hint: str, scripts_dir: str):
    """DB 에서 선별한 기억 글자. DB 가 없거나 선별이 비면 None(파일로 폴백)."""
    db_path = os.path.join(project, ".hermes", "state.db")
    if not os.path.isfile(db_path):
        return None
    try:
        sys.path.insert(0, scripts_dir or os.path.join(project, "scripts"))
        from hermes_memory_select import select_memories, render_selection
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        try:
            sel = select_memories(con, agent["agent_id"], task_hint)
        finally:
            con.close()
        return render_selection(sel, agent.get("name", agent["agent_id"])) if sel["total"] else None
    except Exception as exc:  # noqa: BLE001 — 선별 실패는 파일 주입으로 폴백
        _warn(f"기억 선별 실패, MEMORY.md 파일로 대신: {exc}")
        return None


# 기억 층(사용자 결정 2026-09-28, 계획 hermes-chat 목표 5): 공통(CLAUDE.md·프로젝트 기억 — 공식이 이미 싣는다)이 바탕이고
# 같은 주제는 이 에이전트의 기억이 덮는다. 공통 층에는 about 키가 없어 기계로 비교할 수 없으므로 본문에 글로 드러낸다.
# ⚠️ 덮는 것은 기억·선호까지다 — CLAUDE.md 의 규칙·금지를 에이전트 기억이 무력화하는 통로가 되면 안 된다.
_LAYER_NOTE = ("(공통 기억 — CLAUDE.md·프로젝트 기억 — 이 바탕이고, 같은 주제의 기억·선호가 다르면 아래 이 에이전트의 기억을 따른다. "
               "CLAUDE.md 의 규칙·금지는 덮지 못한다.)")


def _recall_hint(agent: dict) -> str:
    """기억 찾기 안내 — 실린 것은 최근 것뿐이고 옛 대화·다른 방의 일은 recall 로 찾는다(계획 2026-10-01-agent-recall 목표 6).
    호출명(slug)은 선택 항목이라 없으면 id 를 박는다 — recall 은 호출명·이름·id 를 다 받는다.
    낱말은 한 번에 여러 개 — 실측에서 낱말마다 호출을 따로 해 한 질문에 약 4,100 토큰을 썼다(recall 은 맞는 낱말 수로 순위를 매긴다)."""
    who = agent.get("slug") or agent["agent_id"]
    return ("\n--- 기억 찾기 ---\n(여기 실린 것은 최근 것뿐이다. 옛 대화·다른 방에서 한 일은 지어내지 말고 먼저 찾는다: "
            f'python3 scripts/hermes-agent.py recall {who} "<낱말을 한 번에 여러 개>")\n')    # 끝 줄바꿈 — 다른 구획과 같다(훅이 감싼 본문과 글자가 같아야 한다)


def render_soul(project: str, agent_id: str, soul_cap: int = 4096, memory_cap: int = 4096,
                task_hint: str = "", scripts_dir: str = ""):
    """출근 본문 문자열, 넣지 않는 경우 None."""
    agent = _find_agent(project, agent_id)
    if agent is None or agent.get("status") == "retired":
        return None                                   # 은퇴자는 주입에서 빠진다 — 조용히
    agent_dir = os.path.join(project, ".hermes", "agents", agent_id)
    out = [f"[헤르메스 출근] {agent.get('name', '?')} (agent:{agent_id}) — 아래는 이 에이전트의 정체성(SOUL.md)과 "
           "기억(MEMORY.md)이다. 정체성은 사람 승인으로만 고친다."]
    body = _clipped(os.path.join(agent_dir, "SOUL.md"), soul_cap, project)
    if body is not None:
        out.append(f"\n--- SOUL.md ---\n{body.rstrip()}\n")
    mem_text = _selected_memory(project, agent, task_hint, scripts_dir)
    if mem_text is None:
        mem_text = _clipped(os.path.join(agent_dir, "MEMORY.md"), memory_cap, project)
    elif len(mem_text.encode("utf-8")) > memory_cap:
        mem_text = _cut(mem_text.encode("utf-8"), memory_cap, f".hermes/agents/{agent_id}/MEMORY.md")
    if mem_text is not None:
        out.append(f"\n--- MEMORY.md ---\n{_LAYER_NOTE}\n{mem_text.rstrip()}\n")
    conversation = render_agent_summaries(project, agent_id)
    if conversation:
        out.append(conversation)              # 방·@ 호출에서 나눈 대화(C-29) — 어디서 불리든 같은 기억
    out.append(_recall_hint(agent))
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    """훅용: <project> <agent_id> — 본문을 stdout 에. 캡·과제·스크립트 위치는 환경변수(SOUL_CAP 등)."""
    project, agent_id = (argv or sys.argv[1:])[:2]
    text = render_soul(project, agent_id, int(os.environ.get("SOUL_CAP", "4096")),
                       int(os.environ.get("MEMORY_CAP", "4096")), os.environ.get("HERMES_TASK_HINT", ""),
                       os.environ.get("HERMES_SCRIPTS_DIR", ""))
    if text is not None:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
