#!/usr/bin/env python3
"""소환 러너 — 명부의 에이전트를 골라 1회용 토큰과 함께 `claude -p` 를 띄운다.

  run   <이름|id> --task "…" [--discipline …] [--unit …]   소환 실행(task.assigned → claude -p → task.finished)
  issue <이름|id>                                           토큰만 발급해 nonce 를 출력 (기존 러너용)

id 는 에이전트가 고르지 못한다 — 러너가 명부에서 찾아 넣는다(RV-06). `claude -p` 의 JSON 출력에
usage 가 있으면 evidence.usage 로 남긴다(V-8: 대화형에는 없고 러너 경로에만 있다).
테스트는 HERMES_CLAUDE_BIN 으로 모의 claude 를 꽂는다.
계획: docs/exec-plans/active/2026-09-15-agent-identity.md 목표 5
"""

import argparse
import json
import os
import sqlite3
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_journal import emit  # noqa: E402
from hermes_org import match_agents  # noqa: E402
from hermes_roster import find_agent, load_roster  # noqa: E402
from hermes_summons import issue  # noqa: E402
from hermes_uuid7 import uuid7_str  # noqa: E402


def _human(project: str) -> str:
    try:
        name = subprocess.run(["git", "-C", project, "config", "user.name"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        name = ""
    return os.environ.get("HERMES_REQUESTED_BY") or (f"human:{name}" if name else "system:unknown")


def _pick(project: str, who: str, want: dict) -> tuple:
    """이름·id 로 찾거나, 축 값으로 매칭한다. 은퇴자는 소환할 수 없다.

    (agent, basis) 를 돌려준다 — basis 는 task.assigned 의 decision 에 남는 매칭 근거
    (creation-and-organization.md §3 "매칭 결과는 task.assigned 에 남겨 나중에 대조")."""
    roster = load_roster(project)
    agent = find_agent(roster, who) if who else None
    basis = "match=by-name"
    if agent is None and any(want.values()):
        result = match_agents(roster["agents"], want)
        asked = ",".join(f"{k}:{v}" for k, v in want.items() if v)
        if result["ask"]:
            agent = _headless_fallback(project, roster, want)   # 사람 없는 세션만 main 으로(§5)
            basis = f"match={asked} fallback=main proposal=recorded"
        else:
            agent = result["agents"][0]
            basis = f"match={asked} chosen={agent['name']} among={len(result['agents'])}"
    if agent is None:
        raise SystemExit(f"명부에 없다: {who}")
    if agent["status"] == "retired":
        raise SystemExit(f"은퇴한 에이전트는 소환할 수 없다: {agent['name']}")
    return agent, basis


def _headless_fallback(project: str, roster: dict, want: dict) -> dict:
    """담당이 없을 때: 대화형이면 ask 로 중단(사람이 정한다). 사람 없는 세션(HERMES_HEADLESS=1 —
    hermes-loop-run.sh · hermes-cron-run.sh 가 켠다)이면 main 이 수행하고 "담당 없음" 제안을 남겨
    다음 대화형 세션에서 묻는다(creation-and-organization.md §5, 합의)."""
    if os.environ.get("HERMES_HEADLESS") != "1":
        raise SystemExit("ask: 맞는 담당이 없습니다 — 사람에게 문의하십시오")
    from hermes_owner_memory import no_owner_since, record_proposal
    main = next((a for a in roster["agents"] if a.get("name") == "main"), None)
    if main is None:
        raise SystemExit("ask: 맞는 담당이 없고 main 도 명부에 없습니다")
    if not no_owner_since(project, want):   # 사람이 이미 "담당 두지 않음" 이라 답한 영역은 다시 묻지 않는다(리뷰 MEDIUM)
        record_proposal(project, want, _human(project))
    return main


def cmd_issue(args) -> int:
    project = args.project
    agent, _ = _pick(project, args.who, {})
    con = sqlite3.connect(os.path.join(project, ".hermes", "state.db"))
    nonce = issue(con, project, agent["agent_id"], _human(project))
    con.close()
    print(f"{agent['agent_id']} {nonce}")
    return 0


def cmd_run(args) -> int:
    project = args.project
    db = os.path.join(project, ".hermes", "state.db")
    agent, basis = _pick(project, args.who, {"discipline": args.discipline, "unit": args.unit, "rank": None})
    requested_by = _human(project)
    con = sqlite3.connect(db)
    nonce = issue(con, project, agent["agent_id"], requested_by)
    con.close()
    task_id = uuid7_str()
    emit(db, project, {"kind": "task.assigned", "task_id": task_id,
                       "actor": requested_by, "requested_by": requested_by,
                       "intent": args.task[:200], "decision": basis,
                       "evidence": {"template": (agent.get("template") or "").split("@")[0] or None}})

    env = dict(os.environ, HERMES_AGENT_ID=agent["agent_id"], HERMES_SUMMON_NONCE=nonce,
               HERMES_REQUESTED_BY=requested_by, HERMES_PROJECT_DIR=project)
    prompt = f"[소환] 당신은 {agent['name']} (agent:{agent['agent_id']}) 입니다.\n\n{args.task}"
    cmd = [os.environ.get("HERMES_CLAUDE_BIN", "claude"), "-p", prompt, "--output-format", "json"]
    try:
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=args.timeout, env=env, cwd=project)
        exit_code, out = done.returncode, done.stdout
    except (OSError, subprocess.SubprocessError) as exc:
        exit_code, out = 127, ""
        print(f"[hermes-summon] claude 실행 실패: {exc}", file=sys.stderr)

    evidence = {"exit_code": exit_code, "command": "claude"}
    usage = _usage(out)
    if usage:
        evidence["usage"] = usage
    emit(db, project, {"kind": "task.finished", "task_id": task_id,
                       "actor": f"agent:{agent['agent_id']}", "requested_by": requested_by,
                       "claimed": "success" if exit_code == 0 else "failure", "evidence": evidence})
    print(f"[hermes-summon] {agent['name']} 종료 rc={exit_code} task={task_id}")
    return exit_code


def _usage(out: str):
    try:
        data = json.loads(out)
    except (ValueError, TypeError):
        return None
    usage = data.get("usage") if isinstance(data, dict) else None
    if not isinstance(usage, dict):
        return None
    return {k: v for k, v in usage.items() if isinstance(v, (int, float))}


def main() -> int:
    ap = argparse.ArgumentParser(description="헤르메스 소환 러너")
    ap.add_argument("--project", default=os.getcwd())
    sub = ap.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("issue"); i.add_argument("who")
    r = sub.add_parser("run"); r.add_argument("who", nargs="?")
    r.add_argument("--task", required=True); r.add_argument("--discipline"); r.add_argument("--unit")
    r.add_argument("--timeout", type=int, default=int(os.environ.get("HERMES_SUMMON_TIMEOUT", "1800")))
    args = ap.parse_args()
    return cmd_issue(args) if args.cmd == "issue" else cmd_run(args)


if __name__ == "__main__":
    sys.exit(main())
