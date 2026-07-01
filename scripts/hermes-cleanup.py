#!/usr/bin/env python3
"""헤르메스 DB junk 정리 스크립트.

기존 DB에 쌓인 junk 를 정리한다 (C3):
  (a) 불용어·2글자 이하 한글 등 junk 패턴 행 삭제 (pattern_count / pattern_session)
  (b) 대응하는 junk 스킬 .md 파일 + skill_index 행 삭제
  (c) session_history 중복 세션 압축 — 같은 대화의 중복 저장 제거
  (d) VACUUM (--apply 시)

기본은 --dry-run (변경 없이 보고만). 실제 적용은 --apply.

사용법:
  python3 hermes-cleanup.py --db PATH [--apply] [--skills-dir PATH]
"""

import argparse
import hashlib
import os
import re
import sqlite3
import sys


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1)."""
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


# hermes-save-session.py 의 불용어와 동일 기준 (스크립트 독립 배포 — 복제 허용)
_STOPWORDS_EN = {
    "that", "this", "with", "from", "have", "will", "your", "they", "what",
    "when", "where", "which", "then", "there", "these", "those", "just",
    "been", "also", "more", "some", "than", "into", "over", "after", "most",
    "other", "used", "each", "only", "true", "false", "null", "none",
    "them", "their", "because", "about", "before", "both", "many", "much",
    "very", "same", "such", "here", "while", "does", "doesn", "didn",
    "should", "would", "could", "must", "might", "shall", "cannot", "wont",
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
    "있습니다", "없습니다", "합니다", "됩니다", "것입니다", "그리고", "하지만",
    "그런데", "따라서", "때문에", "입니다", "했습니다", "됐습니다", "있었습니다",
    "않습니다", "습니다", "겠습니다", "주세요", "해주세요", "해줘요", "바랍니다",
    "그래서", "그러면", "그러나", "그리고요", "아니라", "아니고", "아니면",
    "이라서", "이라고", "라고요", "처럼요",
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

_HANGUL_ONLY_RE = re.compile(r"^[가-힣]+$")
# 한글 서술형 어미/조사로 끝나는 문장 조각 (save-session 의 필터와 동일 기준)
_KO_VERBAL_SUFFIX_RE = re.compile(
    r"(합니다|입니다|습니다|됩니다|하세요|해주세요|할게요|했어요|해요|에서|으로|이라는)$"
)


def is_definite_junk(key: str) -> bool:
    """확실한 junk: 빈 키 / 불용어 / 한글 서술형 어미 조각 / 2글자 이하 한글.

    ASCII 짧은 토큰에는 길이 기준을 적용하지 않는다 — jq, gh, uv 같은
    실존 도구명이 짧다는 이유로 결정화된 스킬 파일까지 지워지면 안 되기
    때문 (파일 삭제는 이 기준만 사용). 한글 1~2글자(오류, 내가, 에서)는
    도구명일 수 없으므로 junk 로 본다.
    """
    key = key.strip()
    if not key:
        return True
    low = key.lower()
    if low in _STOPWORDS_EN or key in _STOPWORDS_KO:
        return True
    if _HANGUL_ONLY_RE.match(key):
        if len(key) <= 2 or _KO_VERBAL_SUFFIX_RE.search(key):
            return True
    return False


def is_junk_pattern(key: str) -> bool:
    """미결정화 패턴 행의 junk 판별: 확실한 junk + 2글자 이하."""
    return is_definite_junk(key) or len(key.strip()) <= 2


def find_junk_patterns(con: sqlite3.Connection) -> list:
    """삭제 대상 패턴 키 수집. crystallized 상태별로 기준이 다르다:

    - crystallized=-1 (SKIP 거부 마킹): 절대 삭제 안 함 — 행 자체가 재시도 방어막
    - crystallized=1  (결정화 완료): 확실한 junk(불용어 등)일 때만 — 정상 스킬 보호
    - crystallized=0  (대기): 길이 기준까지 포함한 넓은 junk 기준
    """
    rows = con.execute("SELECT pattern_key, crystallized FROM pattern_count").fetchall()
    junk = []
    for key, crystallized in rows:
        if crystallized == -1:
            continue
        if crystallized == 1:
            if is_definite_junk(key):
                junk.append(key)
        elif is_junk_pattern(key):
            junk.append(key)
    return junk


def clean_patterns(con: sqlite3.Connection, junk_keys: list, apply: bool) -> None:
    """(a) junk 패턴 행 삭제."""
    print(f"== (a) junk 패턴: {len(junk_keys)}개")
    for key in junk_keys:
        print(f"   - {key}")
    if not apply or not junk_keys:
        return
    con.executemany(
        "DELETE FROM pattern_count WHERE pattern_key=?", [(k,) for k in junk_keys]
    )
    # pattern_session 테이블이 있으면 같이 정리
    try:
        con.executemany(
            "DELETE FROM pattern_session WHERE pattern_key=?", [(k,) for k in junk_keys]
        )
    except sqlite3.OperationalError:
        pass  # 구버전 DB — pattern_session 없음
    con.commit()


def clean_junk_skills(
    con: sqlite3.Connection, junk_keys: list, skills_dir: str, apply: bool
) -> None:
    """(b) junk 패턴에 대응하는 스킬 .md + skill_index 행 삭제."""
    # 파일 삭제는 되돌릴 수 없으므로 확실한 junk 기준만 사용 (길이 기준 제외)
    targets = []
    for key in junk_keys:
        if not is_definite_junk(key):
            continue
        md_path = os.path.join(skills_dir, f"{key}.md")
        if os.path.isfile(md_path):
            targets.append((key, md_path))

    # skill_index 에 등록됐지만 키 자체가 확실한 junk 인 항목도 수집
    try:
        rows = con.execute("SELECT skill_path FROM skill_index WHERE scope='local'").fetchall()
        for (skill_path,) in rows:
            base = os.path.basename(skill_path)
            if not base.endswith(".md"):
                continue
            key = base[:-3]
            if is_definite_junk(key) and (key, skill_path) not in targets:
                targets.append((key, skill_path))
    except sqlite3.OperationalError as e:
        print(f"[hermes-cleanup] skill_index 조회 실패: {e}", file=sys.stderr)

    print(f"== (b) junk 스킬 파일: {len(targets)}개")
    for key, md_path in targets:
        exists = "" if os.path.isfile(md_path) else " (파일 없음 — index 행만)"
        print(f"   - {md_path}{exists}")

    if not apply:
        return
    for key, md_path in targets:
        if os.path.isfile(md_path):
            try:
                os.remove(md_path)
            except OSError as e:
                print(f"[hermes-cleanup] 파일 삭제 실패({md_path}): {e}", file=sys.stderr)
        con.execute("DELETE FROM skill_index WHERE skill_path=?", (md_path,))
    con.commit()


def find_duplicate_sessions(con: sqlite3.Connection) -> list:
    """(c) 같은 대화가 다른 session_id 로 중복 저장된 세션을 찾는다.

    세션의 앞 5개 메시지 내용 해시가 같으면 같은 대화로 본다.
    가장 행이 많은(=가장 최신 상태) 세션 1개만 남기고 나머지를 삭제 대상으로 반환.
    """
    rows = con.execute(
        "SELECT session_id, project_id, content FROM session_history "
        "WHERE role IN ('user','assistant') "
        "ORDER BY session_id, rowid"
    ).fetchall()

    sessions: dict = {}  # session_id -> {"project": ..., "heads": [...], "count": n}
    for session_id, project_id, content in rows:
        info = sessions.setdefault(
            session_id, {"project": project_id, "heads": [], "count": 0}
        )
        info["count"] += 1
        if len(info["heads"]) < 5:
            info["heads"].append((content or "")[:200])

    groups: dict = {}  # (project, fingerprint) -> [session_id, ...]
    for sid, info in sessions.items():
        fp = hashlib.sha256("\x1e".join(info["heads"]).encode("utf-8")).hexdigest()
        groups.setdefault((info["project"], fp), []).append(sid)

    to_delete = []
    for (_, _), sids in groups.items():
        if len(sids) < 2:
            continue
        # 행 수 최대 → 동률이면 session_id 사전순 최대(최신) 유지
        keep = max(sids, key=lambda s: (sessions[s]["count"], s))
        to_delete.extend([(s, sessions[s]["count"]) for s in sids if s != keep])
    return to_delete


def clean_duplicate_sessions(con: sqlite3.Connection, apply: bool) -> None:
    dups = find_duplicate_sessions(con)
    total_rows = sum(c for _, c in dups)
    print(f"== (c) 중복 세션: {len(dups)}개 (행 {total_rows}개)")
    for sid, count in dups[:30]:
        print(f"   - {sid} ({count}행)")
    if len(dups) > 30:
        print(f"   ... 외 {len(dups) - 30}개")
    if not apply or not dups:
        return
    con.executemany(
        "DELETE FROM session_history WHERE session_id=?", [(s,) for s, _ in dups]
    )
    con.commit()


def main() -> None:
    parser = argparse.ArgumentParser(description="헤르메스 DB junk 정리")
    parser.add_argument("--db", required=True, help="정리할 state.db 경로 (어떤 DB든 가능)")
    parser.add_argument("--apply", action="store_true",
                        help="실제 적용 (기본은 dry-run 보고만)")
    parser.add_argument("--skills-dir", default="",
                        help="스킬 디렉토리 (기본: DB 옆 skills/)")
    args = parser.parse_args()

    if not os.path.isfile(args.db):
        print(f"[hermes-cleanup] DB not found: {args.db}", file=sys.stderr)
        sys.exit(1)

    skills_dir = args.skills_dir or os.path.join(os.path.dirname(os.path.abspath(args.db)), "skills")
    mode = "APPLY" if args.apply else "DRY-RUN"
    print(f"[hermes-cleanup] {mode} — db={args.db} skills={skills_dir}")

    con = connect_db(args.db)
    try:
        junk_keys = find_junk_patterns(con)
        clean_patterns(con, junk_keys, args.apply)
        clean_junk_skills(con, junk_keys, skills_dir, args.apply)
        clean_duplicate_sessions(con, args.apply)
    finally:
        con.close()

    # (d) FTS5 optimize + VACUUM — 별도 연결 (트랜잭션 밖에서 실행해야 함)
    # FTS5 는 행 삭제 후에도 인덱스 세그먼트를 정리하지 않아 'optimize' 없이는
    # VACUUM 만으로 용량이 회수되지 않는다 (실측: 604MB → 190MB → optimize 후 8.9MB).
    if args.apply:
        try:
            con = sqlite3.connect(args.db, timeout=5.0)
            con.execute("PRAGMA busy_timeout = 5000")
            fts_tables = [
                r[0]
                for r in con.execute(
                    "SELECT name FROM sqlite_master "
                    "WHERE type='table' AND sql LIKE '%USING fts5%'"
                ).fetchall()
            ]
            for t in fts_tables:
                try:
                    con.execute(f"INSERT INTO \"{t}\"(\"{t}\") VALUES('optimize')")
                    con.commit()
                except sqlite3.OperationalError as e:
                    print(f"[hermes-cleanup] FTS5 optimize 실패({t}): {e}", file=sys.stderr)
            con.execute("VACUUM")
            con.close()
            print("== (d) FTS5 optimize + VACUUM 완료")
        except sqlite3.OperationalError as e:
            print(f"[hermes-cleanup] VACUUM 실패: {e}", file=sys.stderr)
    else:
        print("== (d) FTS5 optimize + VACUUM 은 --apply 시 실행")

    print(f"[hermes-cleanup] {mode} 완료")


if __name__ == "__main__":
    main()
