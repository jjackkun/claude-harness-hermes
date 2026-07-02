"""헤르메스 세션 저장 — 패턴/토큰 추출.

hermes-save-session.py 에서 분리된 모듈.
대화에서 반복되는 토큰(스킬 결정화 후보)과 스킬 수정 힌트를 추출한다.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_save_session_storage import connect_db  # noqa: E402

# C3 — 불용어 대폭 확장: 일반 단어가 스킬로 결정화되는 것을 차단한다.
_STOPWORDS_EN = {
    # 기능어/대명사/한정사
    "that", "this", "with", "from", "have", "will", "your", "they", "what",
    "when", "where", "which", "then", "there", "these", "those", "just",
    "been", "also", "more", "some", "than", "into", "over", "after", "most",
    "other", "used", "each", "only", "true", "false", "null", "none",
    "them", "their", "because", "about", "before", "both", "many", "much",
    "very", "same", "such", "here", "while", "does", "doesn", "didn",
    "should", "would", "could", "must", "might", "shall", "cannot", "wont",
    # 개발 대화 빈출 일반어
    "code", "file", "files", "path", "data", "type", "name", "value",
    "line", "lines", "text", "item", "list", "user", "time", "page",
    "size", "string", "return", "print", "import", "class", "function",
    "method", "please", "check", "checked", "error", "errors", "warn",
    "warning", "fixed", "fixes", "make", "makes", "made", "need", "needs",
    "needed", "want", "wants", "wanted", "using", "uses", "runs",
    "running", "test", "tests", "testing", "update", "updated", "updates",
    "change", "changed", "changes", "create", "created", "creates",
    "delete", "deleted", "remove", "removed", "added", "adding", "still",
    "like", "good", "well", "work", "works", "working", "worked", "look",
    "looks", "looking", "find", "found", "show", "shows", "showing",
    "read", "write", "issue", "issues", "problem", "problems", "result",
    "results", "output", "input", "start", "started", "stop", "stopped",
    "done", "okay", "sure", "thanks", "thank", "know", "think", "first",
    "last", "next", "actually", "already", "again", "right", "wrong",
    "instead", "however", "without", "inside", "outside", "every",
}
_STOPWORDS_KO = {
    # 어미/접속/대명사 (3자 이상 — 2자 이하 한글은 길이 필터로 일괄 제외)
    "있습니다", "없습니다", "합니다", "됩니다", "것입니다", "그리고", "하지만",
    "그런데", "따라서", "때문에", "입니다", "했습니다", "됐습니다", "있었습니다",
    "않습니다", "습니다", "겠습니다", "주세요", "해주세요", "해줘요", "바랍니다",
    "그래서", "그러면", "그러나", "그리고요", "아니라", "아니고", "아니면",
    "이라서", "이라고", "라고요", "처럼요",
    # 일반 동사/부사/명사
    "확인해", "수정해", "추가해", "삭제해", "만들어", "바꿔줘", "고쳐줘",
    "해야지", "해야죠", "해야해", "하는데", "했는데", "되는데", "있는데",
    "없는데", "같은데", "인데요", "건데요", "그렇게", "이렇게", "저렇게",
    "어떻게", "어떤지", "무엇을", "무엇이", "여기서", "거기서", "저기서",
    "이거를", "그거를", "이것을", "그것을", "이제는", "지금은", "현재는",
    "기존에", "전체적", "관련된", "필요한", "가능한", "다음과", "아래와",
    "위에서", "아래서", "부분을", "부분이", "내용을", "내용이", "작업을",
    "작업이", "파일을", "파일이", "코드를", "코드가", "실행해", "실행이",
    "결과를", "결과가", "진행해", "진행이", "완료됨", "완료했", "문제가",
    "문제를", "사용해", "사용하", "생성해", "생성된", "변경해", "변경된",
    "설정을", "설정이", "정리해", "처리해", "적용해", "제거해", "시작해",
    "종료해", "다시요", "계속해", "모두다", "우리가", "제대로", "일단은",
    "우선은", "혹시나", "정말로", "진짜로", "너무나", "많이요", "조금만",
}

# C3 — 한글 서술형 어미로 끝나는 토큰은 일반 문장 조각이므로 제외
_KO_VERBAL_SUFFIX_RE = re.compile(
    r"(합니다|입니다|습니다|됩니다|하세요|해주세요|할게요|했어요|해요|에서|으로|이라는)$"
)

# C3 — 기술 토큰 판별: kebab-case / snake_case / camelCase / 파일 확장자
_CAMEL_RE = re.compile(r"[a-z][A-Z]")
_FILE_TOKEN_RE = re.compile(
    r"\b[\w.-]+\.(?:py|ts|tsx|js|jsx|mjs|svelte|vue|go|rs|sh|md|json|ya?ml"
    r"|toml|sql|css|html|conf|env|lock)\b"
)


def _is_technical_token(token: str) -> bool:
    return "-" in token or "_" in token or bool(_CAMEL_RE.search(token))


def extract_patterns(messages: list, db_path: str = None) -> list:
    """현재 세션 대화에서 의미 있는 토큰을 동적으로 추출하고,
    DB cross-session 빈도로 반복 패턴을 판별한다.

    우선순위: 파일명/경로 > kebab/snake/camelCase 기술 토큰 > 일반 토큰 (C3).
    """
    all_text: list = []
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        if msg.get("role") not in ("user", "assistant"):
            continue
        raw = msg.get("content", "")
        if isinstance(raw, str):
            all_text.append(raw)
        elif isinstance(raw, list):
            all_text.append(" ".join(p.get("text", "") for p in raw if isinstance(p, dict)))

    combined = " ".join(all_text)
    # token_info: key -> [count, is_technical]
    token_info: dict = {}

    def _add(token: str, technical: bool) -> None:
        key = token.lower()
        if key in _STOPWORDS_EN or key in _STOPWORDS_KO:
            return
        info = token_info.setdefault(key, [0, False])
        info[0] += 1
        info[1] = info[1] or technical

    # 파일명/확장자 토큰 — 최우선 기술 토큰
    for m in _FILE_TOKEN_RE.findall(combined):
        _add(m, True)

    # 영문: 4자 이상 (camelCase, kebab-case, snake_case 는 기술 토큰으로 가중)
    for m in re.findall(r"\b[a-zA-Z][a-zA-Z0-9_-]{3,}\b", combined):
        _add(m, _is_technical_token(m))

    # 한글: 3자 이상만 (2글자 이하 일반 단어 — 내가/먼저/오류 등 — 제외, C3)
    # 서술형 어미/조사로 끝나는 문장 조각도 제외
    for m in re.findall(r"[가-힣]{3,}", combined):
        if _KO_VERBAL_SUFFIX_RE.search(m):
            continue
        _add(m, False)

    # 현재 세션에서 2회 이상 등장한 후보 — 기술 토큰 우선, 빈도 내림차순 상위 50개
    candidates = sorted(
        [(k, c, tech) for k, (c, tech) in token_info.items() if c >= 2],
        key=lambda x: (not x[2], -x[1]),
    )[:50]

    if not candidates:
        return []

    if not db_path:
        return [k for k, _, _ in candidates]

    # DB cross-session 빈도 확인 — 2개 이상 세션에서 등장한 것만 패턴으로 인정
    try:
        con = connect_db(db_path)
        results = []
        for token, _, _ in candidates:
            try:
                # FTS5 MATCH 는 하이픈 등을 구문으로 해석하므로 phrase 인용 필수
                row = con.execute(
                    "SELECT COUNT(DISTINCT session_id) FROM session_history "
                    "WHERE session_history MATCH ? AND role IN ('user','assistant')",
                    ('"' + token.replace('"', '""') + '"',),
                ).fetchone()
            except Exception:
                # FTS5 MATCH 실패 시 (특수문자 등) LIKE 폴백
                try:
                    row = con.execute(
                        "SELECT COUNT(DISTINCT session_id) FROM session_history "
                        "WHERE content LIKE ?",
                        (f"%{token}%",),
                    ).fetchone()
                except Exception as e:
                    print(f"[hermes] cross-session 조회 실패({token}): {e}", file=sys.stderr)
                    row = None
            if row and row[0] >= 2:
                results.append(token)
        con.close()
        return results
    except Exception as e:
        print(f"[hermes] cross-session 검증 실패: {e}", file=sys.stderr)
        return [k for k, _, _ in candidates]


def extract_evolution_hints(messages: list) -> list:
    """사용자 피드백에서 스킬 수정 힌트를 감지한다.
    Returns: [(keyword, feedback_snippet), ...]
    """
    feedback_re = re.compile(
        r"(말고|대신|바꿔|수정|틀려|잘못|incorrect|wrong|instead|change\s+to|아니라|아니고)",
        re.IGNORECASE,
    )
    skill_keyword_re = re.compile(
        r"(pnpm|npm|yarn|poetry|pip|docker|fastapi|svelte|postgres|mysql|redis"
        r"|pytest|vitest|eslint|prettier|ruff|mypy|버전|version)",
        re.IGNORECASE,
    )
    hints = []
    seen = set()
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        if msg.get("role") != "user":
            continue
        raw = msg.get("content", "")
        if isinstance(raw, list):
            content = " ".join(
                p.get("text", "") for p in raw if isinstance(p, dict)
            )
        else:
            content = str(raw)
        if feedback_re.search(content) and skill_keyword_re.search(content):
            kw_m = skill_keyword_re.search(content)
            keyword = kw_m.group(1).lower() if kw_m else ""
            snippet = content[:200].replace("\n", " ").strip()
            key = (keyword, snippet[:50])
            if key not in seen:
                seen.add(key)
                hints.append((keyword, snippet))
    return hints
