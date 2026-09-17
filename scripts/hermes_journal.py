#!/usr/bin/env python3
"""작업 이력 한 건을 검증해 넣고, 행위자를 환경·훅 입력에서 정한다.

결과는 세 층이다(RV-09):
  claimed  — 에이전트가 주장한 것. 입력으로 받는다.
  verified — 기계가 확인한 것. **에이전트 입력을 믿지 않고 여기서 계산한다.**
  accepted — 사람이 받아들인 것. 이 모듈은 쓰지 않는다(사람 명령으로만).
계획: docs/exec-plans/active/2026-09-15-universe-id-journal.md 목표 4·5·7
"""

import os
import sqlite3
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_redact import redact  # noqa: E402
from hermes_journal_schema import (  # noqa: E402
    FREE_TEXT, JournalRejected, ensure_schema, schema_disabled, validate,
)
from hermes_universe import universe_id  # noqa: E402
from hermes_uuid7 import uuid7_str  # noqa: E402

_DEFAULT_AGENT = "agent:main"


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def resolve_actor(hook_input: dict = None) -> tuple:
    """(actor, requested_by) 를 정한다 — 사람이 적어 넣는 값이 아니라 환경에서 읽는다.

    순서: 환경변수(러너·cron 이 넣는다) → 훅 입력의 하위 에이전트 → 기본 main.
    지시자(requested_by)는 러너가 넣은 값, 없으면 git user.name 인 사람.
    """
    hook_input = hook_input or {}
    actor = os.environ.get("HERMES_ACTOR") or _summoned_actor()
    if not actor:
        agent_id = hook_input.get("agent_id")
        actor = f"agent:{agent_id}" if agent_id else _DEFAULT_AGENT
    requested_by = os.environ.get("HERMES_REQUESTED_BY") or _git_user()
    return actor, requested_by


def _summoned_actor():
    """소환된 세션(HERMES_SUMMON_NONCE)이면 시작 훅의 판정을 따른다(RV-06, 계획 4 목표 6).

    판정이 ok 가 아니면 `system:unverified-session` — 세션은 계속되지만 이력에는 출처 불명으로
    남는다. 판정 파일이 없어도(훅이 안 돌았어도) 믿지 않는다.
    """
    nonce = os.environ.get("HERMES_SUMMON_NONCE")
    if not nonce:
        return None
    project = os.environ.get("HERMES_PROJECT_DIR") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        from hermes_summons import read_verdict
        verdict = read_verdict(project, nonce)
    except Exception:                      # noqa: BLE001 — 모듈 부재도 "믿지 않음"
        verdict = "unverified:no-module"
    if verdict == "ok" and os.environ.get("HERMES_AGENT_ID"):
        return f"agent:{os.environ['HERMES_AGENT_ID']}"
    return "system:unverified-session"


def _git_user() -> str:
    import subprocess
    try:
        name = subprocess.run(
            ["git", "config", "user.name"], capture_output=True, text=True, timeout=5
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        name = ""
    return f"human:{name}" if name else "system:unknown"


def machine_verified(evidence: dict, claimed: str = None) -> str:
    """기계가 확인할 수 있는 것만으로 verified 를 정한다.

    지금 확인 가능한 것은 셋뿐이다: 종료 코드 · 커밋 존재 · 게이트 판정(evidence.reason).
    아무것도 없으면 'none' — done_when 형식이 정해지는 계획 4 전까지는 이것이 정상이다.
    """
    evidence = evidence or {}
    if "exit_code" in evidence:
        try:
            return "pass" if int(evidence["exit_code"]) == 0 else "fail"
        except (TypeError, ValueError):
            return "none"
    if evidence.get("commit"):
        return "pass"
    if evidence.get("reason") in ("gate-pass", "gate-fail"):
        return "pass" if evidence["reason"] == "gate-pass" else "fail"
    return "none"


def emit(db_path: str, project_path: str, event: dict, hook_input: dict = None) -> str:
    """이벤트 한 건을 기록하고 event_id 를 돌려준다. 거부되면 JournalRejected."""
    con = sqlite3.connect(db_path)
    try:
        if schema_disabled(con):
            return ""  # rollback 상태 — 훅이 조용히 건너뛴다(목표 12)
        ensure_schema(con)
        row = dict(event)
        row.setdefault("event_id", uuid7_str())
        row.setdefault("ts", _now())
        row.setdefault("universe_id", universe_id(project_path))
        row.setdefault("task_id", row["event_id"])
        # 행위자는 주어졌으면 존중하고, 지시자는 비어 있으면 언제나 환경에서 채운다
        # (하위 에이전트 이벤트는 actor 를 스스로 알지만 지시자는 모른다).
        actor, requested = resolve_actor(hook_input)
        row["actor"] = row.get("actor") or actor
        row["requested_by"] = row.get("requested_by") or requested
        # verified 는 입력을 믿지 않는다 — 기계가 다시 계산해 덮어쓴다(RV-09).
        row["verified"] = machine_verified(event.get("evidence"), row.get("claimed"))
        row.pop("accepted", None)   # 사람만 쓴다
        # 자유 글 칸은 저장 **전** 마스킹한다(work-journal.md §7 "기록 전 마스킹"). 값 대조(.env)는
        # 프로젝트 경로가 있어야 하므로 스키마가 아니라 여기서 — 스키마는 형식만 본다.
        for field in FREE_TEXT:
            if row.get(field) is not None:
                row[field] = redact(str(row[field]), project_path)
        checked = validate(row)
        con.execute(
            "INSERT INTO journal_events ({}) VALUES ({})".format(
                ", ".join(checked), ", ".join("?" * len(checked))
            ),
            tuple(checked.values()),
        )
        con.commit()
        return checked["event_id"]
    finally:
        con.close()


__all__ = ["emit", "resolve_actor", "machine_verified", "JournalRejected"]
