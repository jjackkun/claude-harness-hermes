#!/usr/bin/env python3
"""인계 봉투 — 스키마·검증·만료 판정·되돌아오는 네 이벤트 기록.

넘길 때는 봉투에 `goal` 과 `done_when` 을 **반드시** 적는다(H-02). 받는 쪽은 봉투 검사 후
시작한다: 둘 중 하나가 비거나 `done_when` 형식이 틀리거나 `inputs` 에 참조가 아닌 값이 있으면
기계가 막는다 — 원문 붙여넣기가 여기서 걸린다.

되돌아오는 방식 넷: task.finished(완료) · handoff.declined(거절) · handoff.question(되묻기) ·
handoff.expired(만료). 넷 다 작업 이력 이벤트로 남는다.
만료는 시간 데몬이 아니라 **세션 시작 훅**이 돌린다(RV-08): 기한이 지났는데 task.started 도
handoff.question 도 없는 봉투에 handoff.expired 를 붙인다.
계획: docs/exec-plans/active/2026-09-15-agent-identity.md 목표 10·11

공개 함수 5개: HandoffError · validate_envelope · open_handoff · resolve · check_expired
"""

import os
import re
import sqlite3
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_done_when import is_valid  # noqa: E402
from hermes_journal import emit  # noqa: E402
from hermes_journal_views import thread  # noqa: E402
from hermes_uuid7 import uuid7_str  # noqa: E402
from hermes_handoff_kind import REFUSABLE, derive_kind  # noqa: E402

# inputs 참조 형식: 파일 경로(원문 아님) 또는 이벤트 id(UUID). 그 밖 문자열은 거부한다.
_UUID = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
_PATH = re.compile(r"^[\w./~-]+$")
_RETURN_KINDS = {"finished": "task.finished", "declined": "handoff.declined",
                 "question": "handoff.question", "expired": "handoff.expired",
                 "blocked": "task.finished"}     # 규칙 위반 지시를 되돌림(RV-07) — 거절이 아니다
_RULE_REASON = re.compile(r"^rule:[A-Za-z0-9._-]+$")


class HandoffError(ValueError):
    """봉투가 규칙을 어겼다 — 어느 칸이 왜 안 되는지 함께 알린다."""


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _check_input_ref(ref: str) -> None:
    if not (_UUID.match(ref) or (_PATH.match(ref) and "\n" not in ref)):
        raise HandoffError(f"inputs 는 참조(파일 경로·이벤트 id)만 — 원문으로 보인다: {ref[:40]}")


def validate_envelope(envelope: dict) -> dict:
    """봉투 검사(기계). 통과하면 정규화한 dict, 아니면 HandoffError."""
    goal = _check_goal(envelope)
    done_when = _check_done_when(envelope)
    inputs = _check_inputs(envelope)
    return {"goal": goal, "done_when": done_when, "inputs": inputs,
            "constraints": (envelope.get("constraints") or "").strip() or None,
            "expires_at": envelope.get("expires_at")}     # 선택 — 없으면 만료 없음


def _check_goal(envelope: dict) -> str:
    goal = (envelope.get("goal") or "").strip()
    if not goal:
        raise HandoffError("goal 은 비울 수 없다 (무엇을 원하는가 한 문장)")
    if "\n" in goal:
        raise HandoffError("goal 은 한 줄이어야 한다")
    return goal


def _check_done_when(envelope: dict) -> str:
    done_when = (envelope.get("done_when") or "").strip()
    if not done_when:
        raise HandoffError("done_when 은 비울 수 없다 — 없으면 성공을 검증할 수 없다")
    if not is_valid(done_when):
        raise HandoffError(f"done_when 형식이 아니다: {done_when} "
                           "(test:·file:·gate:·commit:·manual)")
    return done_when


def _check_inputs(envelope: dict) -> list:
    inputs = envelope.get("inputs") or []
    if not isinstance(inputs, list):
        raise HandoffError("inputs 는 참조 목록이어야 한다")
    for ref in inputs:
        _check_input_ref(str(ref))
    return [str(r) for r in inputs]


def open_handoff(db: str, project: str, to_agent: str, envelope: dict,
                 parent_task_id: str = None, by: str = None) -> str:
    """봉투를 검증해 task.assigned 를 남긴다. handoff_id(=task_id)를 돌려준다.

    `by` 는 **신뢰된 호출자**만 넘긴다(러너·훅이 `resolve_actor()` 로 계산한 값). 사용자 입력을
    그대로 넘기면 보내는 쪽을 꾸며 지시를 협업·요청으로 바꿔 거절 가능하게 만들 수 있다(리뷰 LOW).
    """
    env = validate_envelope(envelope)
    frm = by or "agent:main"
    kind, certain = derive_kind(project, frm, to_agent)          # 기계가 정한다(handoff-contract §2)
    env["kind"] = kind if certain else f"{kind}(미상)"
    env["to"] = to_agent
    env["return_to"] = (envelope.get("return_to") or frm).strip()   # 기본은 from
    handoff_id = uuid7_str()
    emit(db, project, {
        "kind": "task.assigned", "task_id": handoff_id, "parent_task_id": parent_task_id,
        "actor": frm, "requested_by": frm,
        "intent": env["goal"],
        "decision": _assign_decision(env),
        "evidence": {"reason": "handoff", "files": env["inputs"][:50]},
    })
    return handoff_id


def _assign_decision(env: dict) -> str:
    """done_when · kind · return_to · (있으면) 만료·constraints 를 한 줄 decision 칸에 담는다 —
    evidence 허용목록 밖을 피한다. constraints 는 자유 글이라 emit 이 저장 전 마스킹한다."""
    parts = [f"done_when={env['done_when']}", f"kind={env['kind']}", f"to={env['to']}", f"return_to={env['return_to']}"]
    if env.get("expires_at"):
        parts.append(f"expires_at={env['expires_at']}")
    if env.get("constraints"):
        parts.append(f"constraints={env['constraints']}")
    return " ".join(parts)


def _kind_of(db: str, handoff_id: str) -> str:
    """봉투의 kind(지시·협업·요청). `(미상)` 표시는 뗀다 — 미상은 요청으로 다룬다."""
    m = re.search(r"kind=([^\s(]+)", _assign_row(db, handoff_id) or "")
    return m.group(1) if m else "요청"


def _assign_row(db: str, handoff_id: str) -> str:
    con = sqlite3.connect(db)
    try:
        row = con.execute(
            "SELECT decision FROM journal_events WHERE task_id=? AND kind='task.assigned' "
            "ORDER BY ts LIMIT 1", (handoff_id,)).fetchone()
    finally:
        con.close()
    return row[0] if row else ""


def resolve(db: str, project: str, handoff_id: str, how: str, actor: str,
            reason: str = None, done_when: str = None, cause: str = None) -> str:
    """되돌아오는 네 방식 중 하나를 이벤트로 남긴다.

    how: finished · declined · question · expired. finished 는 done_when 을 기계가 재
    verified 를 채운다(기록기가 evidence 로 계산). 나머지는 사유를 intent 에 남긴다.
    """
    if how not in _RETURN_KINDS:
        raise HandoffError(f"모르는 반환 방식: {how} (finished·declined·question·expired·blocked)")
    event = {"kind": _RETURN_KINDS[how], "task_id": handoff_id, "actor": actor}
    if how == "blocked":
        event.update(_blocked_fields(reason))
    elif how == "finished":
        event.update(_finished_fields(db, project, handoff_id, done_when))
    else:
        event.update(_return_fields(db, handoff_id, how, reason, cause))
    return emit(db, project, event)


def _return_fields(db: str, handoff_id: str, how: str, reason: str, cause: str) -> dict:
    """declined · question · expired 의 공통 칸. 거절 가능 여부·2차 되묻기 승격·만료 원인을 여기서 정한다."""
    if how == "declined":
        _check_refusable(db, handoff_id, reason)
    out = {"intent": (reason or "").strip()[:200] or f"handoff {how}"}
    if how in ("declined", "question"):
        out["claimed"] = "blocked"
    if how == "question" and _question_count(db, handoff_id) >= 1:
        # 같은 봉투의 두 번째 되묻기는 사람에게 올라간다(handoff-contract.md "되묻기 남용", K-1) —
        # 어려운 일을 받으면 되묻고 미루는 길을 막는다. 보기(escalations)가 이 표시를 읽는다.
        out["decision"] = "escalate=human"
    if how == "expired":
        out["evidence"] = {"reason": f"expired:{cause or 'unstarted'}"}   # 기계 판정(목표 4)
    return out


def _question_count(db: str, handoff_id: str) -> int:
    con = sqlite3.connect(db)
    try:
        return con.execute("SELECT count(*) FROM journal_events WHERE task_id=? AND kind='handoff.question'",
                           (handoff_id,)).fetchone()[0]
    finally:
        con.close()


def _blocked_fields(reason: str) -> dict:
    """규칙 위반 지시를 되돌린다 — 거절이 아니라 "막힘". 사유는 rule:<이름> 꼴만(RV-07)."""
    if not _RULE_REASON.match(reason or ""):
        raise HandoffError("blocked 는 사유가 rule:<이름> 꼴이어야 한다 (예: rule:R-secret)")
    return {"claimed": "blocked", "evidence": {"reason": reason}, "intent": f"규칙 위반으로 막힘 {reason}"}


def _check_refusable(db: str, handoff_id: str, reason: str) -> None:
    """지시는 거절할 수 없다(handoff-contract §1). 협업·요청은 사유가 있어야 거절된다."""
    kind = _kind_of(db, handoff_id)
    if kind not in REFUSABLE:
        raise HandoffError(f"{kind} 는 거절할 수 없다 — 규칙 위반이면 blocked(rule:<이름>)로 되돌린다")
    if not (reason or "").strip():
        raise HandoffError(f"{kind} 거절에는 사유가 필수다")


def _finished_fields(db: str, project: str, handoff_id: str, done_when: str) -> dict:
    from hermes_done_when import verify
    spec = done_when or _done_when_of(db, handoff_id)
    verdict = verify(spec, project) if spec else "none"
    evidence = {"reason": f"gate-{'pass' if verdict == 'pass' else 'fail'}"} \
        if verdict in ("pass", "fail") else {"reason": "manual"}
    return {"claimed": "success", "evidence": evidence}


def _done_when_of(db: str, handoff_id: str) -> str:
    con = sqlite3.connect(db)
    try:
        for e in thread(con, handoff_id):
            if e["kind"] == "task.assigned":
                m = re.search(r"done_when=(\S+)", e.get("decision") or "")
                if m:
                    return m.group(1)
    finally:
        con.close()
    return ""


def check_expired(db: str, project: str) -> int:
    """세션 시작 훅이 부른다(RV-08). 기한 지난 미시작 봉투에 handoff.expired 를 붙인다.

    task.started 또는 handoff.question 이 이미 있으면 만료시키지 않는다. 붙인 수를 돌려준다.
    """
    con = sqlite3.connect(db)
    try:
        rows = con.execute(
            "SELECT task_id, evidence FROM journal_events WHERE kind='task.assigned'").fetchall()
        assigned = {tid for tid, _ in rows}
        started = {e[0] for e in con.execute(
            "SELECT task_id FROM journal_events "
            "WHERE kind IN ('task.started','handoff.question','handoff.expired')")}
        expirable = assigned - started
    finally:
        con.close()
    count = 0
    for handoff_id in sorted(expirable):
        if _is_expired(db, handoff_id):
            cause = _expiry_cause(project, handoff_id)
            resolve(db, project, handoff_id, "expired", "system:claude-stop-journal-gap",
                    reason=f"봉투 기한 초과 — {_CAUSE_TEXT[cause]}", cause=cause)
            count += 1
    return count


_CAUSE_TEXT = {"key-missing": "이 컴퓨터에 열쇠가 없어 받는 쪽이 읽지 못했다",
               "runner-dead": "소환 러너가 시작 기록 없이 죽었다(pending 토큰 잔존)",
               "unstarted": "받는 쪽이 시작하지 않았다"}


def _expiry_cause(project: str, handoff_id: str) -> str:
    """만료 원인의 기계 판정(handoff-contract.md "기록") — 열쇠 없음·러너 죽음은 에이전트 탓이 아니다.
    key-missing: sync.json 은 있는데 ~/.hermes/keys/<universe>/master.key 가 없다.
    runner-dead: .hermes/summons/*.pending 중 이 봉투 id 를 담은 파일이 남아 있다."""
    hermes = os.path.join(project, ".hermes")
    if os.path.isfile(os.path.join(hermes, "sync.json")):
        try:
            from hermes_keys import key_path
            from hermes_universe import universe_id
            if not os.path.isfile(key_path(universe_id(project), "master")):
                return "key-missing"
        except Exception:  # noqa: BLE001 — 열쇠 모듈이 없으면 판정 불가, 다음 원인으로
            pass
    pend = os.path.join(hermes, "summons")
    if os.path.isdir(pend):
        for name in os.listdir(pend):
            if not name.endswith(".pending"):
                continue
            try:
                with open(os.path.join(pend, name), encoding="utf-8", errors="ignore") as fh:
                    if handoff_id in fh.read():
                        return "runner-dead"
            except OSError:
                continue
    return "unstarted"


def _is_expired(db: str, handoff_id: str) -> bool:
    spec = _expires_of(db, handoff_id)
    if not spec:
        return False                          # expires_at 없으면 만료 없음
    return _now() > spec


def _expires_of(db: str, handoff_id: str) -> str:
    """task.assigned 의 decision 칸에서 expires_at=… 을 읽는다. 없으면 빈 문자열."""
    con = sqlite3.connect(db)
    try:
        for e in thread(con, handoff_id):
            if e["kind"] == "task.assigned":
                m = re.search(r"expires_at=(\S+)", e.get("decision") or "")
                return m.group(1) if m else ""
    finally:
        con.close()
    return ""
