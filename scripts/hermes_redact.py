#!/usr/bin/env python3
"""헤르메스 민감정보 마스킹 모듈.

세션 저장(session_history)·롤링 요약(summarize)처럼 대화 텍스트가 DB나
LLM 으로 들어가기 직전 경계에서 호출한다. 탐지된 비밀을 [REDACTED:TYPE]
토큰으로 비가역 치환한다 — 원본 평문은 어디에도 보관하지 않는다.

과마스킹(한글 산문 훼손)을 막기 위해 라벨=값 형태는 값이 'ASCII 비밀처럼
보일 때'만 가린다.

사용법:
    from hermes_redact import redact
    safe = redact(raw_text)
"""

import re

# 라벨=값에서 가릴 값: ASCII 자격증명처럼 보이는 토큰만 (한글 단어 제외).
_SECRET_VALUE = r"[A-Za-z0-9][A-Za-z0-9!@#$%^&*()._+\-/=]{3,}"

# 라벨=값 규칙이 인식하는 비밀 라벨.
_KV_LABELS = (
    r"password|passwd|pwd|secret|api[_-]?key|access[_-]?key|secret[_-]?key|"
    r"token|auth|credential|비밀번호|암호|토큰|계정|account|주소|address"
)

# 형태 기반 규칙 (값 자체의 모양으로 탐지). 라벨=값보다 먼저 적용한다.
_RULES = [
    # 이메일
    (re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+"), "[REDACTED:EMAIL]"),
    # 주민등록번호 (6자리-[1-4]+6자리)
    (re.compile(r"\b\d{6}-[1-4]\d{6}\b"), "[REDACTED:RRN]"),
    # 신용카드 (4-4-4-4, 공백/하이픈 구분)
    (re.compile(r"\b\d{4}[ -]\d{4}[ -]\d{4}[ -]\d{4}\b"), "[REDACTED:CARD]"),
    # 한국 휴대전화
    (re.compile(r"\b01[016789][- ]?\d{3,4}[- ]?\d{4}\b"), "[REDACTED:PHONE]"),
    # 공급자 접두 토큰
    (re.compile(r"\bghp_[A-Za-z0-9]{36}\b"), "[REDACTED:TOKEN]"),       # GitHub PAT
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{22,}"), "[REDACTED:TOKEN]"),
    (re.compile(r"\b(?:gho|ghs|ghu|ghr)_[A-Za-z0-9]{36}\b"), "[REDACTED:TOKEN]"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"), "[REDACTED:TOKEN]"),       # OpenAI/Anthropic
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "[REDACTED:TOKEN]"),         # AWS access key id
    (re.compile(r"\bAIza[0-9A-Za-z_-]{35}"), "[REDACTED:TOKEN]"),      # Google API
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"), "[REDACTED:TOKEN]"),  # Slack
    # 한국 도로명 주소 (시/도 + 시/군/구 + 로/길 + 번호)
    (re.compile(
        r"[가-힣]{2,}(?:특별시|광역시|특별자치시|특별자치도|시|도)\s*"
        r"[가-힣]{1,}(?:시|군|구)\s*[가-힣0-9]{1,}(?:로|길)\s*\d+(?:-\d+)?"
        r"(?:\s*\d+동)?(?:\s*\d+호)?"), "[REDACTED:ADDRESS]"),
    # Authorization: Bearer <token> — 라벨은 보존, 토큰만 치환
    (re.compile(r"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]{8,}"), r"\1 [REDACTED:TOKEN]"),
]

# 라벨=값 규칙: 구분자는 콜론/등호 또는 한글 조사(은/는/이/가). 값만 치환.
_KV_RE = re.compile(
    rf"(?i)\b({_KV_LABELS})(\s*[:=]\s*|[은는이가]\s*)({_SECRET_VALUE})"
)


def _mask_kv(m: "re.Match") -> str:
    return f"{m.group(1)}{m.group(2)}[REDACTED:SECRET]"


def redact(text):
    """텍스트 내 민감정보를 [REDACTED:TYPE] 토큰으로 비가역 치환한다.

    str 이 아니면(예: None) 입력을 그대로 돌려준다 — 호출부 경계에서 안전.
    """
    if not text or not isinstance(text, str):
        return text
    out = text
    for pattern, repl in _RULES:
        out = pattern.sub(repl, out)
    out = _KV_RE.sub(_mask_kv, out)
    return out
