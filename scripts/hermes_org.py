#!/usr/bin/env python3
"""`organization.yaml` 스키마 검증·`unit_id` 부여·담당 매칭만 담당한다. 파싱은 hermes_yaml_subset.

조직은 세 축이다(C-09). 값은 소우주가 정하고 틀만 공장이 고정한다:
  discipline  어떤 일을 하는가            평면 목록, 비울 수 있다
  rank        누가 누구를 지시·승인하는가  위에서 아래 순. 맨 위 `human` 은 **기계가 고정**
  unit        어느 단위 소속인가           2단 맵 {이름: {unit_id, code}}. unit_id 는 불변 UUIDv7

담당 매칭(C-11): 요청의 축 값과 **더 많은 축이 맞는** 에이전트가 이긴다(CODEOWNERS·CSS 와 같은
원리). 없으면 "문의"(사람에게). 문장을 축 값으로 판별하는 모델 호출은 두지 않는다.
계획: docs/exec-plans/active/2026-09-15-agent-identity.md 목표 3·4

공개 함수 5개: OrgError · load_org · validate_org · ensure_unit_ids · match_agents
"""

import os

from hermes_uuid7 import uuid7_str
from hermes_yaml_subset import YamlSubsetError, dump, parse

HUMAN_RANK = "human"
_AXES = ("discipline", "rank", "unit")
_ORG_FILE = ".hermes/organization.yaml"


class OrgError(ValueError):
    """스키마 위반 — 어느 축이 왜 틀렸는지 함께 알린다."""


def load_org(project: str) -> dict:
    """조직 파일을 읽어 검증까지 마친 dict. 없으면 빈 조직(축 세 개 모두 비움)."""
    path = os.path.join(project, _ORG_FILE)
    if not os.path.isfile(path):
        return validate_org({"discipline": [], "rank": [], "unit": {}})
    try:
        with open(path, encoding="utf-8") as fh:
            data = parse(fh.read())
    except YamlSubsetError as exc:
        raise OrgError(f"{_ORG_FILE}: {exc}") from exc
    return validate_org(data)


def _as_list(value, axis: str) -> list:
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        raise OrgError(f"{axis} 는 문자열 목록이어야 한다")
    if len(set(value)) != len(value):
        raise OrgError(f"{axis} 에 중복 값이 있다")
    return list(value)


def validate_org(data: dict) -> dict:
    """스키마를 검사하고 정규화한 dict 를 돌려준다. 맨 위 rank 는 언제나 `human`."""
    unknown = sorted(set(data) - set(_AXES))
    if unknown:
        raise OrgError(f"모르는 축: {', '.join(unknown)} (허용: discipline · rank · unit)")
    out = {"discipline": _as_list(data.get("discipline"), "discipline")}
    rank = _as_list(data.get("rank"), "rank")
    if HUMAN_RANK in rank[1:]:
        raise OrgError(f"rank 맨 위가 아닌 자리에 '{HUMAN_RANK}' 가 있다 — 사람은 언제나 맨 위다")
    out["rank"] = [HUMAN_RANK] + [r for r in rank if r != HUMAN_RANK]
    units = data.get("unit") or {}
    if not isinstance(units, dict):
        raise OrgError("unit 은 {이름: {unit_id, code}} 맵이어야 한다")
    out["unit"] = {name: _validate_unit(name, spec) for name, spec in units.items()}
    return out


def _validate_unit(name: str, spec) -> dict:
    if spec is None:
        spec = {}
    if not isinstance(spec, dict):
        raise OrgError(f"unit '{name}' 의 값은 맵이어야 한다")
    extra = sorted(set(spec) - {"unit_id", "code"})
    if extra:
        raise OrgError(f"unit '{name}' 에 모르는 칸: {', '.join(extra)}")
    code = spec.get("code") or []
    if not isinstance(code, list) or not all(isinstance(c, str) for c in code):
        raise OrgError(f"unit '{name}' 의 code 는 경로 glob 목록이어야 한다")
    return {"unit_id": spec.get("unit_id") or None, "code": list(code)}


def ensure_unit_ids(project: str) -> int:
    """`unit_id` 가 비어 있는 단위에 UUIDv7 을 부여해 파일에 써 넣는다. 부여한 수를 돌려준다.

    이름을 바꿔도 id 가 같아 그 단위의 스킬·이력이 끊기지 않는다.
    """
    path = os.path.join(project, _ORG_FILE)
    if not os.path.isfile(path):
        return 0
    with open(path, encoding="utf-8") as fh:
        org = validate_org(parse(fh.read()))
    missing = [spec for spec in org["unit"].values() if not spec["unit_id"]]
    for spec in missing:
        spec["unit_id"] = uuid7_str()
    if missing:
        _write_org(path, org)
    return len(missing)


def _write_org(path: str, org: dict) -> None:
    """검증된 조직을 파일로. human 은 기계가 붙이므로 적지 않고, 빈 칸은 뺀다."""
    written = {"discipline": org["discipline"],
               "rank": [r for r in org["rank"] if r != HUMAN_RANK],
               "unit": {n: {k: v for k, v in s.items() if v} for n, s in org["unit"].items()}}
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(dump(written, {"rank": "위에서 아래 순. 맨 위 human 은 기계가 붙인다"}))
    os.replace(tmp, path)


def _score(agent: dict, asked: dict):
    """요청 축과 얼마나 맞는가. 어긋나는 축이 하나라도 있으면 None(후보 아님)."""
    org = agent.get("org") or {}
    hits = 0
    for axis, want in asked.items():
        have = org.get(axis)
        if have and have != want:
            return None
        hits += 1 if have == want else 0
    return hits or None


def match_agents(agents: list, want: dict) -> dict:
    """요청 축 값(want: {discipline, unit, rank 중 일부})에 맞는 에이전트를 고른다.

    반환 {"agents": [...], "ask": bool}. 더 많은 축이 맞는 쪽이 앞이고, 하나도 없으면 ask=True.
    은퇴(retired)는 후보에서 뺀다(목표 15).
    """
    asked = {k: v for k, v in (want or {}).items() if k in _AXES and v}
    scored = _candidates(agents, asked) if asked else []
    if not scored:
        return {"agents": [], "ask": True}
    top = max(score for score, _ in scored)
    return {"agents": [a for score, a in scored if score == top], "ask": False}


def _candidates(agents: list, asked: dict) -> list:
    """(점수, 에이전트) 목록 — 은퇴자와 어긋나는 후보는 뺀다."""
    out = []
    for agent in agents:
        if agent.get("status") == "retired":
            continue
        score = _score(agent, asked)
        if score:
            out.append((score, agent))
    return out
