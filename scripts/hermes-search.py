#!/usr/bin/env python3
"""헤르메스 FTS5 스킬 검색 스크립트.

UserPromptSubmit Hook에서 호출.
사용자 입력에서 키워드를 추출하고 관련 스킬을 검색해 반환한다.

검색 전략 (2단계):
  1단계 — FTS5 키워드 검색 (빠름, 무료)
  2단계 — claude -p 뉘앙스 판단 (1단계 결과 없을 때만, claude CLI 필요)

검색 풀:
  1. [project]/.hermes/skills/   ← 헤르메스 자동 생성 스킬 (평면 .md 포함)
  2. [project]/.claude/skills/   ← 하네스 설치 스킬 (skill_index 등록된 것)

주의: stdout 은 프롬프트에 주입되므로 진단 로그는 전부 stderr 로만 출력한다.

사용법:
  python3 hermes-search.py --db PATH --query TEXT [--skills-dir PATH] [--max N]
"""

import argparse
import os
import re
import shutil
import sqlite3
import subprocess
import sys


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1)."""
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def _log(msg: str) -> None:
    """stderr 진단 로그 — stdout 오염 금지 (M2)."""
    print(f"[hermes-search] {msg}", file=sys.stderr)


# assist 경로 세션 상한 (설계 §4.4):
# UserPromptSubmit 경로는 "턴당" 최대 3개(--max 3)를 주입한다.
# assist 경로 "전체"가 프롬프트 경로 한 턴 분량을 넘지 못하게 같은 값으로 맞춘다.
ASSIST_MAX_PER_SESSION = int(os.environ.get("HERMES_ASSIST_MAX_PER_SESSION", "3"))


STOP_WORDS = {
    "이거", "저거", "그거", "해줘", "해", "줘", "좀", "혹시", "그냥",
    "the", "a", "an", "is", "are", "this", "that", "for", "and", "or",
    "to", "in", "of", "with", "it", "be", "do", "how", "what", "can",
}


def extract_keywords(query: str) -> list:
    """사용자 입력에서 유의미한 키워드를 추출한다."""
    query = query.lower()
    tokens = re.findall(r"[a-z0-9가-힣_\-]+", query)
    return [t for t in tokens if t not in STOP_WORDS and len(t) >= 2]


def injected_paths(db_path: str, session_id: str) -> set:
    """이 세션에서 이미 주입된 skill_path 집합.

    출처 무관 — 프롬프트 경로로 들어간 스킬도 이미 세션 컨텍스트에 있으므로 재주입하지 않는다.
    """
    if not (os.path.isfile(db_path) and session_id):
        return set()
    try:
        con = connect_db(db_path)
        rows = con.execute(
            "SELECT DISTINCT skill_path FROM skill_injection WHERE session_id=?",
            (session_id,),
        ).fetchall()
        con.close()
        return {r[0] for r in rows}
    except Exception as e:
        _log(f"주입 이력 조회 실패: {e}")
        return set()


def assist_quota_exhausted(db_path: str, session_id: str) -> bool:
    """assist 경로 세션 상한 도달 여부. 조회 실패 시 False (비차단)."""
    if not (os.path.isfile(db_path) and session_id):
        return False
    try:
        con = connect_db(db_path)
        n = con.execute(
            "SELECT COUNT(*) FROM skill_injection WHERE session_id=? AND source='assist'",
            (session_id,),
        ).fetchone()[0]
        con.close()
        return n >= ASSIST_MAX_PER_SESSION
    except Exception as e:
        _log(f"assist 상한 조회 실패: {e}")
        return False


def search_db(db_path: str, keywords: list, max_results: int) -> list:
    """skill_index 에서 관련 스킬을 검색한다.

    관련도(질의 키워드 매칭 수) 우선 → 도움/사용 통계는 보조 정렬.
    매칭 수를 1차 키로 두면 갓 등록된(used=0) 스킬도 관련도가 높으면 상위 노출돼,
    used_count 만으로 정렬할 때 신규 스킬이 LIMIT 밖으로 굶던 콜드스타트를 구제한다(②).
    """
    if not os.path.isfile(db_path) or not keywords:
        return []

    kws = [kw.lower() for kw in keywords[:5]]
    try:
        con = connect_db(db_path)
        rows = con.execute(
            "SELECT skill_path, keywords, COALESCE(helpful_count,0), COALESCE(used_count,0) "
            "FROM skill_index WHERE COALESCE(state,'active') != 'tombstoned'"
        ).fetchall()
        con.close()
    except Exception as e:
        _log(f"DB 검색 실패: {e}")
        return []

    scored = []
    for path, kwfield, helpful, used in rows:
        hay = (kwfield or "").lower()
        matched = [kw for kw in kws if kw in hay]
        if not matched:
            continue
        # 정렬 키: (매칭수, 도움수, 사용수) 내림차순
        scored.append(((len(matched), helpful, used), path, kwfield, matched[0]))

    scored.sort(key=lambda x: x[0], reverse=True)
    return [
        {"path": path, "keywords": kwfield, "matched": first}
        for _, path, kwfield, first in scored[:max_results]
    ]


def _iter_skill_files(skills_dir: str):
    """스킬 디렉토리에서 (이름, SKILL.md 경로) 쌍을 순회한다.

    M4 — 폴더형 스킬(<name>/SKILL.md)과 헤르메스 자동 생성 평면 .md 둘 다 포함.
    """
    try:
        entries = list(os.scandir(skills_dir))
    except OSError as e:
        _log(f"스킬 디렉토리 열기 실패({skills_dir}): {e}")
        return
    for entry in entries:
        if entry.is_dir():
            skill_md = os.path.join(entry.path, "SKILL.md")
            if os.path.isfile(skill_md):
                yield entry.name, skill_md
        elif entry.is_file() and entry.name.endswith(".md"):
            yield entry.name[:-3], entry.path


def search_skills_dir(skills_dir: str, keywords: list, max_results: int) -> list:
    """스킬 디렉토리를 직접 탐색해 키워드 매칭 스킬을 찾는다."""
    if not os.path.isdir(skills_dir) or not keywords:
        return []

    results = []
    for name, skill_md in _iter_skill_files(skills_dir):
        try:
            with open(skill_md, "r", encoding="utf-8") as f:
                content = f.read().lower()
        except Exception as e:
            _log(f"스킬 읽기 실패({skill_md}): {e}")
            continue

        for kw in keywords:
            if kw in content and name not in [r["name"] for r in results]:
                results.append({"name": name, "path": skill_md, "matched": kw})
                break

    return results[:max_results]


def _extract_description(skill_md: str) -> str:
    """SKILL.md frontmatter 의 description, 없으면 첫 제목 줄을 반환한다."""
    title = ""
    try:
        with open(skill_md, "r", encoding="utf-8") as f:
            in_frontmatter = False
            for line in f:
                line = line.rstrip()
                if line == "---":
                    in_frontmatter = not in_frontmatter
                    continue
                if in_frontmatter and line.startswith("description:"):
                    return line[len("description:"):].strip()
                if not title and line.startswith("# "):
                    title = line[2:].strip()
    except Exception as e:
        _log(f"description 추출 실패({skill_md}): {e}")
    return title


def collect_all_skills(skills_dirs: list) -> list:
    """모든 스킬 디렉토리에서 스킬 이름과 description을 수집한다.

    M4 — 평면 .md 스킬도 포함 (description 없으면 제목 줄 사용).
    """
    skills = []
    seen = set()
    for skills_dir in skills_dirs:
        if not os.path.isdir(skills_dir):
            continue
        for name, skill_md in _iter_skill_files(skills_dir):
            if name in seen:
                continue
            description = _extract_description(skill_md)
            if description:
                seen.add(name)
                skills.append({"name": name, "path": skill_md, "description": description})
    return skills


def haiku_fallback(query: str, skills_dirs: list, max_results: int) -> list:
    """FTS5 미스 시 claude -p로 뉘앙스 기반 스킬을 찾는다."""
    if not shutil.which("claude"):
        return []

    skills = collect_all_skills(skills_dirs)
    if not skills:
        return []

    skill_list = "\n".join([f"- {s['name']}: {s['description']}" for s in skills])
    prompt = (
        f'사용자 메시지: "{query}"\n\n'
        f"아래 스킬 목록에서 이 메시지와 관련된 스킬 이름만 골라줘.\n"
        f"관련 없으면 아무것도 반환하지 마. 있으면 쉼표로 구분해서 이름만 반환해.\n\n"
        f"{skill_list}"
    )

    try:
        result = subprocess.run(
            ["claude", "-p", prompt],
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "HERMES_DISABLED": "1"},
        )
        if result.returncode != 0:
            stderr_tail = (result.stderr or "").strip()[-300:]
            _log(f"claude -p 실패: rc={result.returncode} stderr={stderr_tail}")
            return []
        text = result.stdout.strip()
        if not text:
            return []
    except subprocess.TimeoutExpired:
        _log("claude -p timeout")
        return []
    except Exception as e:
        _log(f"claude fallback 오류: {e}")
        return []

    matched_names = [n.strip() for n in text.split(",")]
    results = []
    skill_map = {s["name"]: s for s in skills}
    for name in matched_names:
        if name in skill_map and len(results) < max_results:
            results.append({"name": name, "path": skill_map[name]["path"], "matched": "claude-p"})
    return results


def read_skill_snippet(skill_path: str, max_lines: int = 10) -> str:
    """스킬 파일에서 핵심 내용만 추출한다."""
    if not os.path.isfile(skill_path):
        return ""
    try:
        with open(skill_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        snippet = []
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("<!--") or not stripped:
                continue
            snippet.append(stripped)
            if len(snippet) >= max_lines:
                break
        return "\n".join(snippet)
    except Exception as e:
        _log(f"스킬 스니펫 읽기 실패({skill_path}): {e}")
        return ""


def main():
    parser = argparse.ArgumentParser(description="헤르메스 FTS5 스킬 검색")
    parser.add_argument("--db", required=True, help="state.db 경로")
    parser.add_argument("--query", required=True, help="사용자 입력 텍스트")
    parser.add_argument("--skills-dir", default="", help="추가 스킬 디렉토리")
    parser.add_argument("--max", type=int, default=3, help="최대 결과 수")
    parser.add_argument("--session-id", default="", help="주입 원장 기록용 세션 ID")
    parser.add_argument("--no-fallback", action="store_true",
                        help="claude -p 뉘앙스 폴백 비활성 — 훅 경로 지연 방지")
    parser.add_argument("--once-per-session", action="store_true",
                        help="이 세션에 이미 주입된 스킬은 제외")
    parser.add_argument("--source", default="prompt", choices=["prompt", "assist"],
                        help="주입 출처 — 원장 기록 및 assist 세션 상한 적용")
    args = parser.parse_args()

    # assist 경로 세션 상한 — 초과 시 검색조차 하지 않는다.
    if args.source == "assist" and assist_quota_exhausted(args.db, args.session_id):
        sys.exit(0)

    keywords = extract_keywords(args.query)

    # 1단계 — FTS5 키워드 검색
    db_results = search_db(args.db, keywords, args.max)

    hermes_skills_dir = os.path.join(os.path.dirname(args.db), "skills")
    dir_results = search_skills_dir(hermes_skills_dir, keywords, args.max)

    if args.skills_dir and os.path.isdir(args.skills_dir):
        dir_results += search_skills_dir(args.skills_dir, keywords, args.max)

    # 톰브스톤 스킬은 평면 dir-scan 결과에서도 제외
    def _tombstoned_paths(db):
        if not os.path.isfile(db):
            return set()
        try:
            con = connect_db(db)
            rows = con.execute(
                "SELECT skill_path FROM skill_index WHERE state='tombstoned'"
            ).fetchall()
            con.close()
            return {r[0] for r in rows}
        except Exception as e:
            _log(f"톰브스톤 조회 실패: {e}")
            return set()

    _dead = _tombstoned_paths(args.db)
    dir_results = [r for r in dir_results if r["path"] not in _dead]

    # 이미 이 세션에 주입된 스킬 제외 (훅 경로 전용) — 빈 집합이면 필터는 무해하다.
    _already = injected_paths(args.db, args.session_id) if args.once_per_session else set()
    db_results = [r for r in db_results if r["path"] not in _already]
    dir_results = [r for r in dir_results if r["path"] not in _already]

    # 2단계 — FTS5 결과 없으면 Haiku fallback
    haiku_results = []
    if not db_results and not dir_results and not args.no_fallback:
        skills_dirs = [hermes_skills_dir]
        if args.skills_dir:
            skills_dirs.append(args.skills_dir)
        haiku_results = haiku_fallback(args.query, skills_dirs, args.max)
        haiku_results = [r for r in haiku_results if r["path"] not in _already]

    # 결과 출력 (프롬프트 주입용) — (텍스트, 경로) 쌍. 실제 주입분만 원장에 기록하기 위함(M1).
    injections = []

    for r in db_results:
        snippet = read_skill_snippet(r["path"])
        if snippet:
            injections.append((f"[헤르메스 규칙 — {os.path.basename(r['path'])}]\n{snippet}", r["path"]))

    for r in dir_results:
        snippet = read_skill_snippet(r["path"])
        if snippet:
            name = r.get("name", os.path.basename(r["path"]))
            injections.append((f"[헤르메스 규칙 — {name}]\n{snippet}", r["path"]))

    for r in haiku_results:
        snippet = read_skill_snippet(r["path"])
        if snippet:
            injections.append((f"[헤르메스 규칙(뉘앙스/claude-p) — {r['name']}]\n{snippet}", r["path"]))

    if not injections:
        sys.exit(0)

    print("\n--- [Hermes 관련 규칙] ---")
    for inj, _path in injections[:args.max]:
        print(inj)
        print()
    print("---")

    # 주입 기록 — used_count(인덱스 매칭분)는 세션ID 무관하게 항상,
    # 원장(skill_injection)은 세션ID 가 있을 때만 기록한다.
    if os.path.isfile(args.db):
        try:
            con = connect_db(args.db)
            # 인덱스 매칭분 used_count 증가 (하위호환 — 세션ID 무관)
            for r in db_results:
                con.execute(
                    "UPDATE skill_index SET used_count = used_count + 1 WHERE skill_path=?",
                    (r["path"],),
                )
            # 주입 원장 기록 — 실제 프롬프트에 주입된 스킬(injections[:max])만, 중복 제거(M1·M3).
            if args.session_id:
                seen = set()
                for _inj, p in injections[:args.max]:
                    if p in seen:
                        continue
                    seen.add(p)
                    con.execute(
                        "INSERT INTO skill_injection (session_id, skill_path, source) "
                        "VALUES (?, ?, ?)",
                        (args.session_id, p, args.source),
                    )
            con.commit()
            con.close()
        except Exception as e:
            _log(f"원장/used_count 기록 실패: {e}")


if __name__ == "__main__":
    main()
