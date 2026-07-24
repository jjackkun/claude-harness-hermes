#!/usr/bin/env python3
"""그물망 승격 게이트 — 스킬 .md 본문이 전역 그물망에 올라가도 되는지 판정.

허용리스트·fail-closed: 두 단계 중 하나라도 불확실하면 승격하지 않는다.
  stage1 — 값싼 정규식 탈락 필터(신원/맥락 마커). 마스킹으로 일반화되지 않는
           것(사람·장소·기계-로컬 경로)은 스킬 전체를 로컬에 남긴다.
  stage2 — claude 일반성 분류. 실패·비활성 시 탈락(보수적).
통과분은 최종 redact() 스크럽으로 자격증명 토큰만 가린다.

redact 와 패턴 집합이 다르다: 게이트는 신원/맥락(직함·사번·경로·연락처)을
'탈락' 신호로 공격적으로 잡고, redact 는 토큰/시크릿을 '마스킹'한다.
"""

import os
import re
import shutil
import subprocess

from hermes_redact import redact

# 사람 지칭이 분명한 한국어 직함. bare 님/씨는 과탐(고객님·선생님)이라 제외 —
# 사전 확장은 튜닝 이연 항목(설계 문서 '미결 항목').
_TITLE_RE = re.compile(
    r"(차장|과장|부장|대리|팀장|실장|본부장|센터장|주임|사원|"
    r"대표이사|부사장|사장|상무|전무|이사)"
)
# 사번: 라벨(사번/employee id/emp no) 동반 시.
_EMP_ID_RE = re.compile(r"(?i)(사번|employee[_-]?id|emp[_-]?no)\s*[:=]?\s*\S+")
# 절대경로 — 기계-로컬이라 그물망에서 무의미하고 준-민감.
_ABS_PATH_RE = re.compile(r"(/(?:home|Users)/\S+|[A-Za-z]:\\\S+)")
# 연락처류 PII — 마스킹이 아니라 탈락(맥락이 특정 개인을 가리킴).
_EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
_PHONE_RE = re.compile(r"\b01[016789][- ]?\d{3,4}[- ]?\d{4}\b")
_RRN_RE = re.compile(r"\b\d{6}-[1-4]\d{6}\b")

_IDENTITY_RULES = [
    (_TITLE_RE, "korean-title"),
    (_EMP_ID_RE, "employee-id"),
    (_ABS_PATH_RE, "absolute-path"),
    (_EMAIL_RE, "pii"),
    (_PHONE_RE, "pii"),
    (_RRN_RE, "pii"),
]


def stage1_reject(text):
    """신원/맥락 마커가 있으면 (True, 사유). 없으면 (False, "clean").

    빈 입력·비문자열은 보수적으로 탈락(승격할 게 없음).
    """
    if not text or not isinstance(text, str):
        return True, "empty"
    for pattern, reason in _IDENTITY_RULES:
        if pattern.search(text):
            return True, reason
    return False, "clean"
