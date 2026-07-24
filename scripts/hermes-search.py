#!/usr/bin/env python3
"""헤르메스 FTS5 스킬 검색 스크립트.

UserPromptSubmit Hook에서 호출.
사용자 입력에서 키워드를 추출하고 관련 스킬을 검색해 반환한다.

검색 전략 (2단계):
  1단계 — FTS5 키워드 검색 (빠름, 무료)
  2단계 — claude -p 뉘앙스 판단 (1단계 결과 없을 때만, claude CLI 필요.
           --no-fallback 지정 시 건너뜀 — 훅 경로(예: 도중 주입)에서 지연 방지 목적)

검색 풀:
  1. [project]/.hermes/skills/   ← 헤르메스 자동 생성 스킬 (평면 .md 포함)
  2. [project]/.claude/skills/   ← 하네스 설치 스킬 (skill_index 등록된 것)
  3. ~/.hermes/mesh/skills/      ← 그물망(전역 2차 소스) — 사용자의 다른 컴퓨터에서 축적된 지식

주의: stdout 은 프롬프트에 주입되므로 진단 로그는 전부 stderr 로만 출력한다.

사용법:
  python3 hermes-search.py --db PATH --query TEXT [--skills-dir PATH] [--global-skills-dir PATH]
    [--max N] [--session-id ID] [--no-fallback] [--once-per-session] [--source {prompt,assist}]

  --once-per-session  이 세션에 이미 주입된 스킬은 출처(prompt/assist) 무관하게 결과에서 제외
  --source assist      주입 출처를 assist 로 기록. 세션당 주입 상한(ASSIST_MAX_PER_SESSION,
                        기본 3, 환경변수 HERMES_ASSIST_MAX_PER_SESSION 로 조정)을 적용한다
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


def _ensure_injection_source_column(con) -> None:
    """구 스키마(source 없음) DB 자가수리 — 재설치 없이 드리프트 복구 (Part B, 멱등)."""
    cols = [r[1] for r in con.execute("PRAGMA table_info(skill_injection)")]
    if "source" not in cols:
        con.execute("ALTER TABLE skill_injection ADD COLUMN source TEXT DEFAULT 'prompt'")
        _log("skill_injection.source 컬럼 자가수리 (구 스키마 마이그레이션)")


# assist 경로 세션 상한 (설계 §4.4):
# UserPromptSubmit 경로는 "턴당" 최대 3개(--max 3)를 주입한다.
# assist 경로 "전체"가 프롬프트 경로 한 턴 분량을 넘지 못하게 같은 값으로 맞춘다.
ASSIST_MAX_PER_SESSION = int(os.environ.get("HERMES_ASSIST_MAX_PER_SESSION", "3"))

# 그물망 최소 보장 슬롯 수 (설계 §Part C — 그물망은 "큐레이트된 소량"):
# db/dir 결과가 --max 를 다 채워도 그물망 결과가 존재하면 최소 1자리는 반드시 배정한다.
# 로컬 결과를 전부 밀어내는 상한이 아니라, 그물망이 완전히 굶주리지 않게 하는 하한선이다.
MESH_MIN_RESERVED_SLOTS = 1


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
        _ensure_injection_source_column(con)
        con.commit()  # ALTER 를 이 경로에서도 즉시 반영 — INSERT 경로의 커밋을 기다리지 않는다.
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


def _select_injections(deduped: list, max_n: int) -> list:
    """중복 제거된 (텍스트, 경로, 그물망여부) 후보에서 max_n 개를 뽑는다.

    그물망 결과가 있으면 MESH_MIN_RESERVED_SLOTS 만큼 자리를 보장받아
    로컬(db/dir) 결과에 밀려 전량 굶주리지 않는다.
    단, max_n == 1 인 경우는 예외: 로컬 결과가 하나라도 있으면 그물망이 그
    유일한 자리를 차지하지 않는다 — 예약은 하한선이지 로컬보다 우선하는 게 아니다.
    """
    if max_n <= 0:
        return []

    local = [e for e in deduped if not e[2]]
    mesh = [e for e in deduped if e[2]]

    if not mesh:
        return local[:max_n]

    if max_n == 1:
        return local[:1] if local else mesh[:1]

    reserve = min(MESH_MIN_RESERVED_SLOTS, len(mesh))
    local_budget = max_n - reserve
    selected = local[:local_budget] + mesh[:reserve]

    # 로컬/예약분이 max_n 에 못 미치면(로컬이 적을 때) 남는 슬롯을 그물망으로 채운다 — 할당량 낭비 방지.
    if len(selected) < max_n:
        picked_paths = {p for _, p, _ in selected}
        for entry in local[local_budget:] + mesh[reserve:]:
            if entry[1] in picked_paths:
                continue
            selected.append(entry)
            picked_paths.add(entry[1])
            if len(selected) == max_n:
                break

    return selected


def main():
    parser = argparse.ArgumentParser(description="헤르메스 FTS5 스킬 검색")
    parser.add_argument("--db", required=True, help="state.db 경로")
    parser.add_argument("--query", required=True, help="사용자 입력 텍스트")
    parser.add_argument("--skills-dir", default="", help="추가 스킬 디렉토리")
    parser.add_argument("--global-skills-dir", default="",
                        help="그물망 스킬 디렉토리(~/.hermes/mesh/skills) — 전역 2차 소스")
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

    # 그물망(전역 2차 소스) 결과는 별도로 추적한다 — 출력 라벨과 할당량 예약(finding 1/4)에 필요.
    mesh_results = []
    if args.global_skills_dir and os.path.isdir(args.global_skills_dir):
        mesh_results = search_skills_dir(args.global_skills_dir, keywords, args.max)

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
    mesh_results = [r for r in mesh_results if r["path"] not in _dead]

    # 이미 이 세션에 주입된 스킬 제외 (훅 경로 전용) — 빈 집합이면 필터는 무해하다.
    _already = injected_paths(args.db, args.session_id) if args.once_per_session else set()
    db_results = [r for r in db_results if r["path"] not in _already]
    dir_results = [r for r in dir_results if r["path"] not in _already]
    mesh_results = [r for r in mesh_results if r["path"] not in _already]

    # 2단계 — FTS5 결과 없으면 Haiku fallback
    haiku_results = []
    if not db_results and not dir_results and not mesh_results and not args.no_fallback:
        skills_dirs = [hermes_skills_dir]
        if args.skills_dir:
            skills_dirs.append(args.skills_dir)
        if args.global_skills_dir:
            skills_dirs.append(args.global_skills_dir)
        haiku_results = haiku_fallback(args.query, skills_dirs, args.max)
        haiku_results = [r for r in haiku_results if r["path"] not in _already]

    # 결과 후보 (프롬프트 주입용) — (텍스트, 경로, 그물망여부) 3-튜플.
    # 순서: db → 로컬 dir-scan → 그물망 → haiku. db가 dir-scan 쌍둥이보다 먼저 오므로
    # 뒤의 중복 제거 단계에서 db 항목이 우선(선점) 살아남는다.
    candidates = []

    for r in db_results:
        snippet = read_skill_snippet(r["path"])
        if snippet:
            candidates.append((f"[헤르메스 규칙 — {os.path.basename(r['path'])}]\n{snippet}", r["path"], False))

    for r in dir_results:
        snippet = read_skill_snippet(r["path"])
        if snippet:
            name = r.get("name", os.path.basename(r["path"]))
            candidates.append((f"[헤르메스 규칙 — {name}]\n{snippet}", r["path"], False))

    for r in mesh_results:
        snippet = read_skill_snippet(r["path"])
        if snippet:
            name = r.get("name", os.path.basename(r["path"]))
            # 그물망 출처는 라벨로 구분한다 — Phase 2 PII/비밀 승격 게이트 이전이라
            # 출처 불명확 시 검증되지 않은 내용이 프롬프트에 섞여 들어간 것처럼 보일 수 있다.
            candidates.append((f"[헤르메스 규칙(그물망) — {name}]\n{snippet}", r["path"], True))

    for r in haiku_results:
        snippet = read_skill_snippet(r["path"])
        if snippet:
            candidates.append((f"[헤르메스 규칙(뉘앙스/claude-p) — {r['name']}]\n{snippet}", r["path"], False))

    # 경로 기준 중복 제거 — 같은 스킬이 search_db 와 search_skills_dir 양쪽에서
    # 매칭돼도(동일 파일을 skill_index 와 dir-scan 이 이중 스캔) 한 자리만 차지하고 한 번만 출력한다.
    # 최초 등장(db 우선) 순서를 보존한다.
    deduped = []
    _seen_paths = set()
    for entry in candidates:
        path = entry[1]
        if path in _seen_paths:
            continue
        _seen_paths.add(path)
        deduped.append(entry)

    injections = _select_injections(deduped, args.max)

    if not injections:
        sys.exit(0)

    print("\n--- [Hermes 관련 규칙] ---")
    for inj, _path, _is_mesh in injections:
        print(inj)
        print()
    print("---")

    # 주입 기록 — used_count(인덱스 매칭분)·원장(skill_injection) 모두 실제로 출력된
    # injections 와 일치시킨다(dedup·할당량 예약 이후 상태). 세션ID 는 원장 기록에만 필요.
    if os.path.isfile(args.db):
        try:
            con = connect_db(args.db)
            printed_paths = {p for _inj, p, _is_mesh in injections}
            # 인덱스 매칭분 used_count 증가 — 실제로 출력된 db 매칭 스킬만(하위호환 — 세션ID 무관)
            for r in db_results:
                if r["path"] not in printed_paths:
                    continue
                con.execute(
                    "UPDATE skill_index SET used_count = used_count + 1 WHERE skill_path=?",
                    (r["path"],),
                )
            # 주입 원장 기록 — 실제 프롬프트에 주입된 스킬(injections)만. deduped 결과라 재중복 제거 불필요.
            if args.session_id:
                _ensure_injection_source_column(con)
                for _inj, p, _is_mesh in injections:
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
