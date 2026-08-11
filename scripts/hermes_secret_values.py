#!/usr/bin/env python3
"""`.env` 에서 마스킹 대상 값 집합을 만드는 책임만 진다.

왜 필요한가 — 형태 추측 마스킹의 한계:
    `hermes_redact.py` 의 라벨=값 규칙은 딱지(`password=`)가 있어야만 가린다.
    그런데 사람이 실제로 주는 형태는 URL 아래 `아이디 | 비번` 처럼 딱지가 없다.
    딱지 어휘를 아무리 늘려도 이 형태는 원리상 못 잡는다.
    정답지(`.env` 실제 값)와 대조하면 형태가 무관해진다.

값은 절대 stdout/stderr 로 출력하지 않는다 — 마스킹하려던 값을 로그로 흘리면
방어가 무의미하다. 진단이 필요하면 키 이름과 개수만 알린다.

사용법:
    from hermes_secret_values import load_secret_values
    values = load_secret_values(project_dir)   # {키 이름: 값}
"""

import os
import re

# 값 길이 하한. 4자 미만은 산문에 흔히 등장해 과마스킹으로 문장을 깨뜨린다.
MIN_VALUE_LEN = 4

# 탐색할 .env 위치 (프로젝트 루트 기준 상대 경로).
ENV_CANDIDATES = (
    ".env",
    ".env.local",
    ".env.production",
    "backend/.env",
    "backend/.env.local",
    "frontend/.env",
    "frontend/.env.local",
)

# 자리표시자는 비밀이 아니다 — 마스킹하면 문서·예제가 깨진다.
_PLACEHOLDER_RE = re.compile(
    r"^(changeme|example|placeholder|dummy|test|none|null|true|false"
    r"|development|production|staging|local|debug|info|warn|error)$"
    r"|your[-_]|xxx|\*{3,}|<[^>]*>|\$\{[^}]+\}",
    re.IGNORECASE,
)

# 순수 숫자(포트·타임아웃·개수)는 비밀이 아니다. `4101` 을 마스킹하면 산문이 깨진다.
_NUMERIC_RE = re.compile(r"^\d+$")

# URL 은 **자격증명이 박혀 있을 때만** 비밀이다.
#   postgresql://user:pw@host/db   → 비밀 (userinfo 존재)
#   https://api.example.com/v1?key=abc → 비밀 (질의문자열에 키가 실릴 수 있다)
#   http://localhost:4101          → 주소일 뿐 — 문서·로그에 그대로 나와야 한다
_URL_RE = re.compile(r"^[a-z][a-z0-9+.\-]*://", re.IGNORECASE)
_URL_HAS_CREDENTIAL_RE = re.compile(r"^[a-z][a-z0-9+.\-]*://[^/@\s]*@", re.IGNORECASE)

# `KEY=VALUE` 한 줄. export 접두와 따옴표를 허용한다.
_ENV_LINE_RE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")

# (project_dir → 값 집합) 캐시. redact() 는 메시지마다 호출되므로
# 매번 파일을 읽으면 세션 저장이 수백 번의 디스크 I/O 로 늘어난다.
_CACHE = {}


def _strip_quotes(raw: str) -> str:
    """값에서 인라인 주석과 감싼 따옴표를 벗긴다."""
    value = raw.strip()
    if value[:1] in ("'", '"') and value[-1:] == value[:1] and len(value) >= 2:
        return value[1:-1]
    # 따옴표가 없을 때만 ` #` 주석을 자른다 (따옴표 안 #은 값의 일부다).
    return value.split(" #", 1)[0].strip()


def _is_maskable(value: str, home: str) -> bool:
    """이 값을 마스킹 대상으로 삼아도 되는가.

    ★`.env` 는 비밀만 담지 않는다 — 포트·URL·모드 같은 **설정값**이 섞여 있다.
    그것까지 가리면 문서와 로그가 깨진다. 실제로 `APP_BASE_URL=http://localhost:4101`
    때문에 정상 문서의 curl 예시가 통째로 마스킹돼 커밋이 막혔다.

    `$HOME` 경로에 포함되는 값은 제외한다 ⚠️ 실제 사례: 계정 ID 가 홈 디렉터리명과
    같아, 무조건 치환하면 `/home/<id>/...` 경로가 전부 깨진다.
    """
    if len(value) < MIN_VALUE_LEN:
        return False
    if _PLACEHOLDER_RE.search(value):
        return False
    if _NUMERIC_RE.match(value):
        return False
    # URL 은 자격증명(userinfo)이나 질의문자열을 품을 때만 비밀로 본다.
    if _URL_RE.match(value) and not _URL_HAS_CREDENTIAL_RE.match(value) and "?" not in value:
        return False
    if home and value in home:
        return False
    return True


def parse_env_text(text: str, home: str = "") -> dict:
    """`.env` 본문에서 마스킹 대상 {키: 값} 을 뽑는다. 파일 I/O 없음 — 테스트 진입점."""
    found = {}
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = _ENV_LINE_RE.match(line)
        if not m:
            continue
        key, value = m.group(1), _strip_quotes(m.group(2))
        if _is_maskable(value, home):
            found[key] = value
    return found


def _resolve_project_dir(project_dir):
    """명시 인자 → CLAUDE_PROJECT_DIR → cwd 순으로 프로젝트 루트를 정한다."""
    if project_dir:
        return project_dir
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def load_secret_values(project_dir=None) -> dict:
    """프로젝트의 `.env` 들에서 마스킹 대상 {키: 값} 을 모은다.

    `.env` 가 하나도 없으면 빈 집합을 돌려준다 — 실패가 아니다. 마스킹은
    값 대조 외에 형태 규칙도 있으므로, 정답지가 없어도 동작해야 한다.
    """
    root = _resolve_project_dir(project_dir)
    if root in _CACHE:
        return _CACHE[root]

    home = os.path.expanduser("~")
    values = {}
    for rel in ENV_CANDIDATES:
        path = os.path.join(root, rel)
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except (OSError, UnicodeDecodeError):
            continue
        values.update(parse_env_text(text, home))

    _CACHE[root] = values
    return values


def clear_cache():
    """캐시를 비운다 — 테스트에서 `.env` 를 바꿔 가며 검증할 때 쓴다."""
    _CACHE.clear()
