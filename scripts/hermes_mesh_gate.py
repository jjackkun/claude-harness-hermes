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
    if not isinstance(text, str) or not text.strip():
        return True, "empty"
    for pattern, reason in _IDENTITY_RULES:
        if pattern.search(text):
            return True, reason
    return False, "clean"


# 프롬프트에 실을 본문 상한 — 결정화 스킬은 짧지만(관측 최대 ~130자) 방어적
# 상한을 둔다. 판정에는 앞부분으로 충분하고, 과금·지연을 억제한다.
_MAX_PROMPT_BODY = 4000
_GATE_MODEL = "claude-haiku-4-5-20251001"
_PROMPT_TMPL = (
    "다음은 코딩 세션에서 결정화된 스킬 문서다. 이 지식이 특정 개인이나 특정 "
    "프로젝트에만 종속되는지, 아니면 프로젝트를 초월해 재사용 가능한 일반 지식인지 "
    "판정하라. 답은 GENERAL 또는 SPECIFIC 한 단어로만 출력하라.\n\n"
    "--- 스킬 ---\n{body}\n--- 끝 ---"
)


def stage2_is_general(text, *, timeout=120):
    """claude 로 일반성을 판정한다. GENERAL 이면 True, 그 외 전부 False(fail-closed).

    사용자 전역 opt-out(HERMES_DISABLED)·claude 부재·오류·타임아웃 → 모두 탈락.
    """
    if os.environ.get("HERMES_DISABLED"):
        return False
    if not shutil.which("claude"):
        return False
    prompt = _PROMPT_TMPL.format(body=(text or "")[:_MAX_PROMPT_BODY])
    try:
        result = subprocess.run(
            ["claude", "-p", prompt, "--model", _GATE_MODEL],
            capture_output=True, text=True, timeout=timeout,
            env={**os.environ, "HERMES_DISABLED": "1"},
        )
    except (subprocess.TimeoutExpired, OSError):
        return False
    if result.returncode != 0:
        return False
    return result.stdout.strip().upper().startswith("GENERAL")


def mesh_gate(text, *, timeout=120):
    """스킬 본문의 승격 여부를 판정한다. (passed, reason, scrubbed) 반환.

    통과분만 scrubbed(redact 적용본)를 돌려준다 — 토큰류 자격증명을 최종 마스킹.
    허용리스트: stage1 통과 AND stage2 GENERAL 일 때만 승격.
    """
    rejected, reason = stage1_reject(text)
    if rejected:
        return False, reason, None
    if not stage2_is_general(text, timeout=timeout):
        return False, "not-general", None
    return True, "general", redact(text)
