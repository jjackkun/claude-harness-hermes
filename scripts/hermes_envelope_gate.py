#!/usr/bin/env python3
"""봉투 금지 내용 게이트만 담당한다 — 기억·대화 원문·티켓 번호·파일 경로·사람이 읽는 이름(P-04).

이슈는 소우주 밖(공개 GitHub)으로 나간다. 공장 저장소가 공개라 봉투 본문이 공개 게시물이다.
그래서 사내 정보가 새는 새 경로를 열지 않도록, 배달 전에 이런 내용을 **기계가 막는다**.
사람이 읽는 이름은 명부(agents.json)·조직(organization.yaml)·저장소 폴더 이름에서 모아 대조한다.
계획: docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 7·8

공개 함수 2개: forbidden_names · check_forbidden
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_mesh_gate import stage1_reject  # noqa: E402  (직함·사번·경로·연락처 신원 마커)

# 티켓 번호: #1234 · JIRA-456 · 자연어("이슈 4521", "ticket 4521").
_TICKET = re.compile(
    r"(?:#\d{2,}|\b[A-Z][A-Z0-9]{1,9}-\d+\b|(?i:ticket|issue|이슈|티켓)\s*#?\s*\d{2,})")
# 파일 경로: 절대경로, 확장자 있는 상대경로(src/…/Login.tsx), 또는 확장자 없는 다단 경로가
# 알려진 최상위 폴더로 시작하는 것(backend/app/execution 류 — 이 프로젝트가 R1 격리로 자주 언급).
_KNOWN_TOP = (r"once|scheduled|realtime|shared|backend|frontend|src|docs|app|lib|"
              r"scripts|tests|components|pages|api|utils|assets|presets")
_PATH = re.compile(
    r"(?:/(?:home|Users|var|etc|opt)/\S+|[A-Za-z]:\\\S+"
    r"|[\w.-]+/[\w./-]*\.\w{1,6}\b"
    rf"|\b(?:{_KNOWN_TOP})/[\w-]+(?:/[\w-]+)*)")
# 대화 원문 마커: 화자 라벨.
_RAW = re.compile(r"(?im)^\s*(?:User|Human|Assistant|사용자|나|상대)\s*:")


def forbidden_names(project: str) -> set:
    """소우주 밖으로 나가면 안 되는 사람이 읽는 이름 — 명부·조직·저장소 폴더에서 모은다."""
    names = set()
    base = os.path.basename(os.path.abspath(project))
    if base:
        names.add(base)                      # 저장소 폴더 이름(예: zeroday-frontend)
    _collect_roster_names(project, names)
    _collect_unit_names(project, names)
    return {n for n in names if len(n) >= 2}


def _collect_roster_names(project: str, names: set) -> None:
    try:
        with open(os.path.join(project, ".hermes", "agents.json"), encoding="utf-8") as fh:
            for agent in json.load(fh).get("agents", []):
                if agent.get("name"):
                    names.add(agent["name"])
    except (OSError, ValueError):
        pass


def _collect_unit_names(project: str, names: set) -> None:
    try:
        sys.path.insert(0, os.path.join(project, "scripts"))
        from hermes_org import load_org
        names.update(load_org(project).get("unit", {}).keys())
    except Exception:
        pass


def check_forbidden(project: str, text: str) -> tuple:
    """봉투에 실릴 텍스트를 검사한다. 통과면 (True, "clean"), 아니면 (False, 사유).

    사유: ticket · path · raw · name · <신원 마커>(mesh_gate stage1). 하나라도 걸리면 배달 거부.
    """
    body = text or ""
    if _TICKET.search(body):
        return False, "ticket"
    if _PATH.search(body):
        return False, "path"
    if _RAW.search(body):
        return False, "raw"
    rejected, reason = stage1_reject(body)     # 직함·사번·절대경로·연락처(기억·맥락 마커)
    if rejected and reason != "empty":
        return False, reason
    low = body.lower()
    for name in forbidden_names(project):
        if name.lower() in low:
            return False, "name"
    return True, "clean"
