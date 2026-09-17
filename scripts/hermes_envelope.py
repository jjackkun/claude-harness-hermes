#!/usr/bin/env python3
"""제안 봉투 스키마·`envelope_id`·`outbox` 읽기/쓰기·상태 전이만 담당한다.

소우주는 제안을 자기 안의 보낼 편지함(`.hermes/outbox/<envelope_id>/envelope.json`)에만 쓴다.
배달은 사람이 명령할 때만 `hermes-propose.py --deliver` 가 한다(RV-15). 상태 전이는 하나뿐이다:
`pending → delivered → approved|rejected`. `pending` 에는 마지막 배달 오류 문구를 함께 남긴다
(인증 오류를 오프라인으로 오인하지 않기 위해).

봉투에는 **사람이 읽는 이름을 넣지 않는다** — `universe_id`·`agent_id`·`skill_id` 만(P-04). 이름 거부는
hermes_envelope_gate 가 배달 전에 막는다. 공장 저장소는 PUBLIC 이라 봉투 본문이 공개 게시물이다.
계획: docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 7·8

공개 함수 6개: EnvelopeError · new_envelope · write_envelope · read_envelope · list_envelopes · set_status
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_uuid7 import uuid7_str  # noqa: E402

_STATUSES = ("pending", "delivered", "approved", "rejected")
_KINDS = ("new", "improve", "exclude")
# 봉투에 담기는 칸(설계 3절). 사람이 읽는 이름은 여기 없다 — 기계 id 만.
_FIELDS = ("envelope_id", "kind", "universe_id", "agent_id", "skill_id",
           "base", "body", "diff", "reason", "gate_results", "status", "error", "issue_url")


class EnvelopeError(ValueError):
    """봉투가 규칙을 어겼다."""


def new_envelope(kind: str, universe_id: str, agent_id: str, skill_id: str,
                 body: str, reason: str, gate_results: dict,
                 base: str = None, diff: str = None) -> dict:
    """봉투 dict 를 만든다(status=pending). 소우주 이름·에이전트 이름은 받지 않는다."""
    if kind not in _KINDS:
        raise EnvelopeError(f"모르는 제안 종류: {kind} ({'·'.join(_KINDS)})")
    if not (reason or "").strip():
        raise EnvelopeError("이유(reason)는 비울 수 없다 — 우주 심사의 근거다")
    return {
        "envelope_id": uuid7_str(), "kind": kind,
        "universe_id": universe_id, "agent_id": agent_id, "skill_id": skill_id,
        "base": base, "body": body or "", "diff": diff,
        "reason": reason.strip(), "gate_results": gate_results or {},
        "status": "pending", "error": None, "issue_url": None,
    }


def _outbox_dir(project: str) -> str:
    return os.path.join(project, ".hermes", "outbox")


def write_envelope(project: str, envelope: dict) -> str:
    """봉투를 `.hermes/outbox/<id>/envelope.json` 에 쓴다(원자적). 경로를 돌려준다."""
    eid = envelope.get("envelope_id")
    if not eid:
        raise EnvelopeError("envelope_id 가 없다")
    folder = os.path.join(_outbox_dir(project), eid)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "envelope.json")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({k: envelope.get(k) for k in _FIELDS}, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, path)
    return path


def read_envelope(project: str, envelope_id: str) -> dict:
    """봉투를 읽는다. 없으면 EnvelopeError."""
    path = os.path.join(_outbox_dir(project), envelope_id, "envelope.json")
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError) as exc:
        raise EnvelopeError(f"봉투를 읽을 수 없다: {envelope_id} ({exc})")


def list_envelopes(project: str, status: str = None) -> list:
    """outbox 의 봉투를 (선택적으로 status 로 걸러) 최신순으로 낸다."""
    root = _outbox_dir(project)
    if not os.path.isdir(root):
        return []
    out = []
    for eid in sorted(os.listdir(root), reverse=True):
        try:
            env = read_envelope(project, eid)
        except EnvelopeError:
            continue
        if status is None or env.get("status") == status:
            out.append(env)
    return out


def set_status(project: str, envelope_id: str, status: str, error: str = None,
               issue_url: str = None) -> dict:
    """상태를 바꾼다. 전이는 pending→delivered→approved|rejected 만 허용. error 는 pending 에만 남긴다."""
    if status not in _STATUSES:
        raise EnvelopeError(f"모르는 상태: {status}")
    env = read_envelope(project, envelope_id)
    _check_transition(env.get("status"), status)
    env["status"] = status
    env["error"] = error if status == "pending" else None
    if issue_url:
        env["issue_url"] = issue_url
    write_envelope(project, env)
    return env


_ALLOWED = {"pending": {"pending", "delivered"}, "delivered": {"approved", "rejected"}}


def _check_transition(old: str, new: str) -> None:
    if old == new:
        return
    if new not in _ALLOWED.get(old, set()):
        raise EnvelopeError(f"허용되지 않은 상태 전이: {old} → {new} "
                            "(pending→delivered→approved|rejected)")
