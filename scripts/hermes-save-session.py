#!/usr/bin/env python3
"""헤르메스 세션 저장 스크립트.

Stop Hook에서 호출. Claude Code transcript를 읽어
session_history(FTS5)와 pattern_count 테이블에 저장한다.

같은 session_id 로 재저장하면 이전 행을 교체한다 (매 턴 누적 방지).
패턴 집계는 세션당 1회만 반영된다 (pattern_session 테이블로 보장).

사용법:
  python3 hermes-save-session.py --db PATH --transcript PATH \
      [--project-id ID] [--session-id ID]
"""

import argparse
import json
import os
import re
import sqlite3
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_redact import redact  # noqa: E402  (민감정보 마스킹 공유 헬퍼)


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1).

    훅들이 병렬로 같은 DB를 만질 수 있으므로 잠금 대기를 보장한다.
    (hermes 스크립트들은 독립 배포되므로 각 파일에 동일 함수를 복제한다)
    """
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def load_transcript(path: str) -> list:
    if not os.path.isfile(path):
        return []
    messages = []
    try:
        with open(path, "r", encoding="utf-8") as f:
            first_char = f.read(1)
            f.seek(0)
            if first_char == "[":
                data = json.load(f)
                if isinstance(data, list):
                    return data
                return data.get("messages", [])
            else:
                # JSONL: Claude Code transcript 형식
                # 각 줄: {"type": "user"|"assistant", "message": {"role": ..., "content": ...}}
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                        t = obj.get("type")
                        if t in ("user", "assistant") and "message" in obj:
                            messages.append(obj["message"])
                    except json.JSONDecodeError:
                        continue
    except Exception as e:
        print(f"[hermes] transcript 읽기 실패: {e}", file=sys.stderr)
        return []
    return messages


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

# ── B신호(객관적 실수 신호) 탐지 — tool_use/tool_result 블록 전용 스캔 ──────────
# extract_patterns 는 text 만 읽어 tool 블록을 무시하므로 B신호는 별도 스캔이 필요하다.
# 탐지는 순수 정규식(모델 호출 0). 채점은 결정화 단계의 별도 Haiku 만 — 자기채점 분리.

_BUILD_CMD_RE = re.compile(
    r"\b(pytest|jest|vitest|mocha|tsc|ruff|mypy"
    r"|go\s+test|go\s+build|cargo\s+test|cargo\s+build|make"
    r"|npm\s+(?:run\s+)?(?:test|build)"
    r"|pnpm\s+(?:run\s+)?(?:test|build)"
    r"|yarn\s+(?:run\s+)?(?:test|build))\b"
)
# 실패 시그니처 — is_error 플래그가 1차 신호, 이 시그니처는 보수적 보강용(대소문자 구분)
_FAIL_SIG_RE = re.compile(
    r"(FAILED|✗|Traceback|npm ERR|error\[E|error TS\d+)"
)
_SIGNAL_FILE_RE = re.compile(
    r"\b[\w./-]+\.(?:py|ts|tsx|js|jsx|mjs|svelte|vue|go|rs|sh|java|kt)\b"
)
_ERR_CODE_RE = re.compile(r"\b([A-Z]{2,}\d{3,})\b|error\[(E\d+)\]")
_GIT_UNDO_RE = re.compile(r"git\s+(?:revert\b|reset\s+--hard\b|checkout\s+--(?=\s|$)|restore\b)")


def _result_text(block: dict) -> str:
    """tool_result 블록에서 출력 텍스트를 추출한다 (str 또는 text 블록 리스트)."""
    c = block.get("content", "")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return " ".join(
            p.get("text", "") for p in c if isinstance(p, dict) and "text" in p
        )
    return ""


def _bash_commands(messages: list) -> dict:
    """assistant tool_use 중 Bash 명령을 {tool_use_id: command} 로 모은다."""
    cmds: dict = {}
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for blk in content:
            if not isinstance(blk, dict):
                continue
            if blk.get("type") == "tool_use" and str(blk.get("name", "")).lower() == "bash":
                cmd = (blk.get("input") or {}).get("command", "")
                if blk.get("id"):
                    cmds[blk["id"]] = cmd
    return cmds


def _derive_locus(text: str, cmd: str) -> str:
    """실패 위치 키를 도출한다. 파일 경로는 basename 으로 정규화(라인번호 제거)."""
    fm = _SIGNAL_FILE_RE.search(text)
    if fm:
        return os.path.basename(fm.group(0))
    cm = _ERR_CODE_RE.search(text)
    if cm:
        return cm.group(1) or cm.group(2)
    fmc = _SIGNAL_FILE_RE.search(cmd)
    if fmc:
        return os.path.basename(fmc.group(0))
    tm = _BUILD_CMD_RE.search(cmd)
    return re.sub(r"\s+", "-", tm.group(1)) if tm else "build"


def detect_objective_signals(messages: list) -> list:
    """tool_use/tool_result 블록에서 객관적 실수 신호(B신호)를 탐지한다.

    Returns: [(pattern_key, context_line), ...] — 세션 내 중복 키는 1개로 합친다.
    """
    cmds = _bash_commands(messages)
    seen: set = set()
    results: list = []

    # ① 테스트/빌드 실패 — 직전 Bash 명령이 빌드/테스트 계열이고 결과가 실패일 때
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for blk in content:
            if not isinstance(blk, dict) or blk.get("type") != "tool_result":
                continue
            cmd = cmds.get(blk.get("tool_use_id"), "")
            if not _BUILD_CMD_RE.search(cmd):
                continue
            text = _result_text(blk)
            # 비정상 종료(is_error)만으로 실패로 간주한다 — 출력이 'passed' 여도 exit≠0 은 실패.
            if not (blk.get("is_error") or _FAIL_SIG_RE.search(text)):
                continue
            key = f"test-fail:{_derive_locus(text, cmd)}"
            if key in seen:
                continue
            seen.add(key)
            first_line = next((ln.strip() for ln in text.splitlines() if ln.strip()), "")
            results.append((key, f"{cmd[:60]} 실패: {first_line[:120]}"))

    # ② git revert/reset — 사용자가 AI 작업을 되돌린 무언의 불만 신호
    for cmd in cmds.values():
        if not _GIT_UNDO_RE.search(cmd):
            continue
        fm = _SIGNAL_FILE_RE.search(cmd)
        # 파일 인자가 없으면(예: git revert <sha>, git reset --hard) revert:HEAD 버킷으로 모은다 — 의도된 catch-all
        target = os.path.basename(fm.group(0)) if fm else "HEAD"
        key = f"revert:{target}"
        if key in seen:
            continue
        seen.add(key)
        results.append((key, f"git 되돌림: {cmd[:80]}"))

    return results


def record_signal_context(db_path: str, signals: list, project_id: str, session_id: str) -> None:
    """B신호 맥락을 session_history(role='tool')에 기록해 결정화 증거를 보강한다.

    save_session 이 같은 session_id 행을 먼저 DELETE+INSERT 하므로, 그 뒤에 호출되면
    재저장 때마다 자연히 교체되어 중복이 쌓이지 않는다 (idempotent).
    """
    con = connect_db(db_path)
    con.isolation_level = None
    cur = con.cursor()
    ts = datetime.now().isoformat()
    try:
        cur.execute("BEGIN IMMEDIATE")
        for key, ctx in signals:
            content = redact(f"[B신호] {key} :: {ctx}".strip())
            cur.execute(
                "INSERT INTO session_history (content, role, timestamp, project_id, session_id) "
                "VALUES (?, ?, ?, ?, ?)",
                (content, "tool", ts, project_id, session_id),
            )
        cur.execute("COMMIT")
    except Exception as e:
        try:
            cur.execute("ROLLBACK")
        except sqlite3.OperationalError:
            pass
        print(f"[hermes] B신호 맥락 기록 실패: {e}", file=sys.stderr)
    finally:
        con.close()


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


def save_session(db_path: str, messages: list, project_id: str, session_id: str):
    """세션 저장. 같은 session_id 재저장 시 이전 행을 교체한다 (C2)."""
    con = connect_db(db_path)
    con.isolation_level = None  # 명시적 트랜잭션 제어
    cur = con.cursor()

    # 매 턴 Stop 훅이 전체 transcript 를 다시 보내므로,
    # 누적 INSERT 대신 같은 세션의 이전 행을 지우고 최신 1벌만 유지한다.
    # Stop 훅이 연속 발화해 두 프로세스가 겹쳐도 DELETE+INSERT 가 인터리빙되지
    # 않도록 BEGIN IMMEDIATE 로 쓰기 락을 선점한 단일 트랜잭션으로 묶는다.
    inserted = 0
    try:
        cur.execute("BEGIN IMMEDIATE")
        cur.execute("DELETE FROM session_history WHERE session_id = ?", (session_id,))

        ts = datetime.now().isoformat()
        for msg in messages:
            if not isinstance(msg, dict):
                continue
            role = msg.get("role", "")
            if role not in ("user", "assistant", "tool"):
                continue
            raw = msg.get("content", "")
            if isinstance(raw, list):
                content = " ".join(
                    p.get("text", "") for p in raw if isinstance(p, dict) and "text" in p
                )
            else:
                content = str(raw)
            content = content.strip()
            if not content:
                continue
            content = redact(content)  # 원문 적재 전 민감정보 마스킹

            cur.execute(
                "INSERT INTO session_history (content, role, timestamp, project_id, session_id) "
                "VALUES (?, ?, ?, ?, ?)",
                (content, role, ts, project_id, session_id),
            )
            inserted += 1
        cur.execute("COMMIT")
    except Exception:
        try:
            cur.execute("ROLLBACK")
        except sqlite3.OperationalError:
            pass
        raise
    finally:
        con.close()
    print(f"[hermes] session saved: {inserted} messages → {db_path}")
    return inserted


def update_patterns(db_path: str, patterns: list, session_id: str) -> list:
    """pattern_count 업데이트. 결정화 임계값(3) 도달 패턴 목록 반환.

    pattern_session 테이블로 (패턴, 세션) 쌍을 기록해
    같은 세션의 재저장으로 카운트가 중복 증가하지 않도록 한다 (C2).
    """
    con = connect_db(db_path)
    cur = con.cursor()
    cur.execute(
        "CREATE TABLE IF NOT EXISTS pattern_session ("
        "  pattern_key TEXT NOT NULL,"
        "  session_id  TEXT NOT NULL,"
        "  PRIMARY KEY (pattern_key, session_id)"
        ")"
    )
    crystallize_targets = []

    for key in patterns:
        marked = cur.execute(
            "INSERT OR IGNORE INTO pattern_session (pattern_key, session_id) "
            "VALUES (?, ?)",
            (key, session_id),
        )
        if marked.rowcount == 0:
            # 같은 세션에서 이미 집계됨 — 재저장으로 인한 중복 증가 방지
            continue

        cur.execute(
            "INSERT INTO pattern_count (pattern_key, count, last_seen) "
            "VALUES (?, 1, CURRENT_TIMESTAMP) "
            "ON CONFLICT(pattern_key) DO UPDATE SET "
            "count = count + 1, last_seen = CURRENT_TIMESTAMP "
            "WHERE crystallized = 0",
            (key,),
        )
        row = cur.execute(
            "SELECT count FROM pattern_count WHERE pattern_key=? AND crystallized=0",
            (key,),
        ).fetchone()
        if row and row[0] >= 3:
            crystallize_targets.append(key)

    con.commit()
    con.close()
    return crystallize_targets


def main():
    parser = argparse.ArgumentParser(description="헤르메스 세션 저장")
    parser.add_argument("--db", required=True, help="state.db 경로")
    parser.add_argument("--transcript", required=True, help="transcript JSON 경로")
    parser.add_argument("--project-id", default="", help="프로젝트 식별자")
    parser.add_argument("--session-id", default="", help="세션 ID")
    args = parser.parse_args()

    if not os.path.isfile(args.db):
        print(f"[hermes] DB not found: {args.db}", file=sys.stderr)
        sys.exit(1)

    messages = load_transcript(args.transcript)
    if not messages:
        print("[hermes] transcript empty or not found — skipped")
        sys.exit(0)

    project_id = args.project_id or os.path.basename(os.path.dirname(args.db))
    # session_id 부재 시 transcript 경로 기반으로 안정적인 ID 를 만든다
    # (타임스탬프를 쓰면 매 턴 새 세션으로 저장돼 DB가 폭증한다 — C2)
    session_id = args.session_id or os.path.splitext(
        os.path.basename(args.transcript)
    )[0]

    save_session(args.db, messages, project_id, session_id)

    patterns = extract_patterns(messages, args.db)
    b_signals = detect_objective_signals(messages)
    b_keys = [k for k, _ in b_signals]
    if b_signals:
        record_signal_context(args.db, b_signals, project_id, session_id)
    crystallize = update_patterns(args.db, patterns + b_keys, session_id)

    if crystallize:
        print(f"[hermes] CRYSTALLIZE:{','.join(crystallize)}")
    else:
        print("[hermes] no crystallization needed")

    evolution_hints = extract_evolution_hints(messages)
    for kw, feedback in evolution_hints:
        print(f"[hermes] EVOLVE:{kw}|{feedback}")


if __name__ == "__main__":
    main()
