#!/usr/bin/env python3
"""커밋 대상 텍스트에서 자격증명·개인정보를 탐지해 차단하는 책임만 진다.

근거: docs/design-docs/core-beliefs.md#p9 — 자격증명·개인정보를 평문으로 두지 않는다.
git 히스토리는 되돌릴 수 없으므로 *들어가기 전에* 막는 것이 유일한 방어다.

`hermes_redact.py` 와 역할이 다르다: 저쪽은 DB·LLM 입력 경계에서 **치환**하고,
이쪽은 커밋 경계에서 **차단**한다. 치환은 조용히 지나가도 되지만 차단은 사람을
멈춰 세워야 하므로, 감도를 더 높게 잡고 오탐을 면제 규칙으로 관리한다.

정답지(`.env` 실제 값) 대조는 `hermes_secret_values` 를 **공유**한다 — 복제하지
않는다. 복제본만 고치고 원본을 두면 원본을 쓰는 경로가 계속 뚫려 있게 된다.

★ 다만 **무엇을 정답지에 올릴지는 층마다 다르다.** 마스킹은 아이디까지 가려도
손해가 없지만, 차단은 아이디 때문에 오탐이 나면 **커밋이 통째로 막힌다.**
그래서 값은 공유하고 **선별은 각자 한다** (`SECRET_NAME_RE` 참조).

사용:
    python3 check-secrets.py            # 스테이징된 파일 검사 (pre-commit)
    python3 check-secrets.py --all      # 추적 대상 전체 검사
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

# 정답지 모듈은 훅 디렉터리(.git/hooks/) 또는 프로젝트 scripts/ 에 있다.
# 없으면 형태 규칙만으로 동작한다 — 차단기가 죽는 것보다 낫다.
for _cand in (os.path.dirname(os.path.abspath(__file__)),
              os.path.join(os.getcwd(), "scripts")):
    if _cand not in sys.path:
        sys.path.append(_cand)
try:
    from hermes_secret_values import load_secret_values
except ImportError:
    load_secret_values = None

# 검사에서 제외할 경로. 원본 자료 보관소는 gitignore 로도 막혀 있으나 이중 방어.
EXCLUDE_RE = re.compile(
    r"(^|/)(node_modules|\.venv|venv|dist|build|__pycache__|\.svelte-kit)(/|$)"
    r"|^docs/temp/"
    r"|(^|/)check-secrets\.py$"        # 자기 자신의 패턴에 걸리지 않도록
    r"|(^|/)hermes_redact\.py$"        # 동일 패턴을 담은 자매 모듈
    # ── 아래는 **가짜 자격증명이 들어 있는 것이 정상**인 구역이다 ────────────────
    # 진짜를 닮지 않으면 규칙을 검사할 수도, 무엇을 하지 말라고 가르칠 수도 없다.
    # ⚠️ 면제 구역에는 **진짜 값을 절대 넣지 않는다.**
    #
    # 면제는 경로로 한다 — 값 어휘(`abc123`, `secret123`, …)를 자리표시자로 넓히면
    # 그 어휘가 모든 파일에서 통하게 되어 탐지기 자체가 무뎌진다. 경로 면제는 어디가
    # 면제됐는지 목록으로 남고, 소비 프로젝트에 없는 경로는 그냥 no-op 이다.
    r"|^tests/"                        # 테스트 fixture (비밀 형태를 일부러 만든다)
    r"|^assets/(rules|skills)/"        # 교육용 예제 문서 ("이렇게 하지 마라")
    r"|^docs/superpowers/specs/"       # 설계 문서 (관측된 유출 형태를 그대로 인용)
)

# 값의 *모양*으로 탐지하는 규칙. 라벨이 없어도 잡힌다.
SHAPE_RULES: list[tuple[str, re.Pattern[str]]] = [
    ("RRN", re.compile(r"\b\d{6}-[1-4]\d{6}\b")),
    ("CARD", re.compile(r"\b\d{4}[ -]\d{4}[ -]\d{4}[ -]\d{4}\b")),
    ("PHONE", re.compile(r"\b01[016789][- ]?\d{3,4}[- ]?\d{4}\b")),
    ("GITHUB_PAT", re.compile(r"\bghp_[A-Za-z0-9]{36}\b")),
    ("GITHUB_PAT", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{22,}")),
    ("GITHUB_TOKEN", re.compile(r"\b(?:gho|ghs|ghu|ghr)_[A-Za-z0-9]{36}\b")),
    ("LLM_KEY", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}")),
    ("AWS_KEY", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("GOOGLE_KEY", re.compile(r"\bAIza[0-9A-Za-z_-]{35}")),
    ("SLACK_TOKEN", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}")),
    ("PRIVATE_KEY", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("BEARER", re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{16,}")),
]

# 라벨=값 규칙. 값이 ASCII 자격증명처럼 보일 때만 잡는다.
#
# 라벨 앞에 \b 를 두지 않는다. `UNIPASSAPIKEY=...` 처럼 접두어가 붙어 한 단어가 된
# 경우를 놓치기 때문이다. 실제로 이 구멍 때문에 API 키를 탐지하지 못했다.
KV_LABELS = (
    r"password|passwd|pwd|secret|api[_-]?key|access[_-]?key|secret[_-]?key|"
    r"token|credential|비밀번호|암호"
)
# 값의 첫 글자를 영숫자로 제한하지 않는다. `!Passw0rd` 처럼 특수문자로 시작하는
# 비밀번호를 놓치기 때문이다.
SECRET_VALUE = r"[A-Za-z0-9!@#$%^&*_+\-][A-Za-z0-9!@#$%^&*()._+\-/=]{5,}"
# ★ 여는 따옴표를 건너뛴다. 이것이 없어서 **소스에 하드코딩된 비밀의 가장 흔한 형태**를
# 통째로 놓치고 있었다 — `password = "Hunter2!xyz"` 가 탐지되지 않았다.
KV_RULE = ("CREDENTIAL",
           re.compile(rf"(?i)({KV_LABELS})(\s*[:=]\s*)[\"']?({SECRET_VALUE})"))

# .env 형식 전용. UPPER_SNAKE 이름이 KEY/TOKEN/SECRET/PASSWORD/PW/CRED 로 끝나면 값을 본다.
# 이름 자체가 강한 신호이므로 값 패턴은 느슨하게(공백 아닌 4자 이상) 둔다.
ENV_RULE = (
    "ENV_SECRET",
    re.compile(
        r"^\s*([A-Z][A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD|PW|CRED))"
        r"\s*=\s*(\S{4,})"),
)

# 값 자리가 **코드 식**이면 리터럴이 아니다 — 코드지 비밀이 아니다.
#   token = _CSRF_META.search(page)       ← 실제로 걸렸던 오탐
#   secret_key = os.environ["SECRET_KEY"] ← 오히려 권장되는 형태다
#   PRIVATE-TOKEN: $GITLAB_API_TOKEN      ← CI 의 변수 참조. 이것도 리터럴이 아니다
#
# ⚠️ 좁게 유지한다. 값 자리가 코드라고 **구문으로** 단정할 수 있는 형태만 면제한다.
# 진짜 하드코딩 비밀은 `token = "Hunter2xyz!"` 이지 `token = f(x)` 가 아니다.
CODE_EXPR_RE = re.compile(
    rf"(?i)({KV_LABELS})\s*[:=]\s*(?:"
    r"[A-Za-z_][\w.]*[(\[]"                 # 호출·첨자: _CSRF.search(p), env["K"]
    # 설정·요청 객체에서 꺼내 쓰는 형태. ⚠️ 일반 점 경로(`\w+(\.\w+)+`)로 넓히면
    # `Hunter2.xyz` 같은 진짜 비밀번호까지 면제된다 — 알려진 루트로만 좁힌다.
    r"|(?:process\.env|import\.meta\.env|os\.environ|self|this|config|settings"
    r"|req|request|ctx|context|opts|options|props|state|data)\.\w+"
    # 타입 표기. `password: string)` 은 함수 시그니처지 비밀이 아니다.
    r"|(?:string|number|boolean|any|object|str|int|bool|none|null|undefined)\b"
    r"|[\"']?\$"                            # 변수 참조: $GITLAB_API_TOKEN
    # 맨 이름 참조. 따옴표가 없으므로 리터럴이 아니라 **식별자**다.
    #   password=PASSWORD)      시험 상수 참조
    #   token=refresh_plain     지역 변수 참조
    # ⚠️ 좁게 유지한다 — ALL_CAPS 이거나 밑줄이 든 이름만. 그래야 `Hunter2`
    #    같은 진짜 비밀이 면제되지 않는다.
    # ⚠️ (?-i:) 로 대소문자를 구분한다. 이 정규식 전체에 (?i) 가 걸려 있어
    #    그냥 두면 `password = Hunter2xyz` 같은 진짜 비밀까지 면제된다(실측).
    r"|(?-i:[A-Z][A-Z0-9_]{2,})(?=[\s),;\]]|$)"
    r"|(?-i:[a-z_][a-z0-9_]*_[a-z0-9_]*)(?=[\s),;\]]|$)"
    r")"
)

# 마스킹된 자리표시자는 위반이 아니다.
PLACEHOLDER_RE = re.compile(
    r"REDACTED|\*{3,}|x{4,}|XXXX|<[^>]{1,40}>|\$\{[^}]+\}|"
    # `your-api-key-here` 처럼 중간에 낱말이 끼는 자리표시자도 받는다.
    r"your[-_](?:[a-z]+[-_])*(?:token|key|password|secret)|"
    r"example|dummy|placeholder|changeme",
    re.IGNORECASE,
)


def staged_files() -> list[str]:
    out = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
        capture_output=True, text=True, check=True,
    ).stdout
    return [f for f in out.splitlines() if f]


def tracked_files() -> list[str]:
    out = subprocess.run(
        ["git", "ls-files"], capture_output=True, text=True, check=True
    ).stdout
    return [f for f in out.splitlines() if f]


def read_text(path: str) -> str | None:
    """텍스트 파일이면 내용을, 바이너리·읽기 실패면 None 을 반환한다."""
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError:
        return None
    if b"\x00" in raw[:8192]:
        return None
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return None


def _exempt_spans(line: str) -> list[tuple[int, int]]:
    """자리표시자가 차지한 구간 목록.

    ★면제 규칙은 탐지 단위와 같은 폭이어야 한다. 예전에는 자리표시자가 한 번이라도
    보이면 **줄 전체**를 건너뛰었다. 한 줄이 1.6만 자인 jsonl 에서는 `example` 한 번에
    그 줄의 진짜 비밀이 통째로 면제된다 — 실제로 이 구멍으로 평문 자격증명이 통과했다.
    """
    return [m.span() for m in PLACEHOLDER_RE.finditer(line)]


def _is_exempt(span: tuple[int, int], exempt: list[tuple[int, int]]) -> bool:
    """탐지 구간이 자리표시자 구간과 겹치면 면제한다."""
    start, end = span
    return any(start < e and s < end for s, e in exempt)


def scan(path: str, text: str, secret_values: dict) -> list[tuple[int, str, str]]:
    """(줄번호, 종류, 발췌) 목록을 반환한다."""
    hits: list[tuple[int, str, str]] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        exempt = _exempt_spans(line)

        def record(kind: str, span: tuple[int, int], excerpt: str):
            if not _is_exempt(span, exempt):
                hits.append((lineno, kind, excerpt))

        # 값 기반 — `.env` 실재 값. 딱지가 없어도, 형태가 낯설어도 잡힌다.
        for key, value in secret_values.items():
            idx = line.find(value)
            if idx >= 0:
                record("ENV_VALUE", (idx, idx + len(value)), f"{key}=<일치>")

        for kind, pattern in SHAPE_RULES:
            m = pattern.search(line)
            if m:
                record(kind, m.span(), m.group(0)[:24])

        kind, pattern = KV_RULE
        m = pattern.search(line)
        if m and not CODE_EXPR_RE.search(line):
            record(kind, m.span(), f"{m.group(1)}={m.group(3)[:12]}")

        kind, pattern = ENV_RULE
        m = pattern.search(line)
        if m:
            record(kind, m.span(), f"{m.group(1)}={m.group(2)[:12]}")
    return hits


#: 정답지에 올릴 변수 이름. `ENV_RULE` 과 같은 어휘를 쓴다 —
#: 두 곳이 갈리면 한쪽만 막는 구멍이 다시 생긴다.
SECRET_NAME_RE = re.compile(r"(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD|PW|CRED)$")


def _secret_values() -> dict:
    """정답지 조회. 모듈이 없거나 실패해도 차단기는 계속 돈다.

    ⚠️ **아이디류는 뺀다.** `hermes_secret_values` 는 *마스킹* 용 정답지라
    아이디도 담는다 — LLM 입력에서 가리는 것은 옳다. 그러나 **차단**에서는 다르다.

    실제로 겪은 일: 어느 프로젝트의 `*_ID` 값이 그 머신의 사용자명과 같아
    **모든 경로 문자열**(`/home/<사용자>/…`)에 걸렸다. 결과가 오탐으로 뒤덮여
    커밋이 통째로 막혔고, 그 상태의 차단기는 *"끄고 싶은 것"* 이 된다.

    아이디는 비밀이 아니다. 사고 기록·설정 문서가 계정을 명시해야 할 때도 있다.
    **막을 것은 비밀번호·키·토큰이다.**

    근거: terminal-shipping docs/audits/2026-08-18-etrans-secret-leak.md §3-1
    """
    if load_secret_values is None:
        return {}
    try:
        values = load_secret_values(os.getcwd())
    except Exception:
        return {}
    return {k: v for k, v in values.items() if SECRET_NAME_RE.search(k)}


def main() -> int:
    files = tracked_files() if "--all" in sys.argv else staged_files()
    targets = [f for f in files if not EXCLUDE_RE.search(f)]
    secret_values = _secret_values()

    violations: list[tuple[str, int, str, str]] = []
    for path in targets:
        text = read_text(path)
        if text is None:
            continue
        for lineno, kind, excerpt in scan(path, text, secret_values):
            violations.append((path, lineno, kind, excerpt))

    if not violations:
        return 0

    print("", file=sys.stderr)
    print("[P9] 자격증명·개인정보로 보이는 값이 커밋 대상에 있다.", file=sys.stderr)
    for path, lineno, kind, excerpt in violations:
        print(f"  {path}:{lineno}  {kind}  {excerpt}", file=sys.stderr)
    print("", file=sys.stderr)
    print(
        "  → 해당 파일을 커밋 대상에서 빼거나(git restore --staged) 값을 마스킹하라.\n"
        "    git 히스토리는 되돌릴 수 없다. --no-verify 우회 금지.\n"
        "    오탐이면 check-secrets.py 의 EXCLUDE_RE 또는 PLACEHOLDER_RE 를 고쳐라.\n"
        "  근거: docs/design-docs/core-beliefs.md#p9",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
