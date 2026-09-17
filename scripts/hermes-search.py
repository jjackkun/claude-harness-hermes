#!/usr/bin/env python3
"""헤르메스 스킬 검색 스크립트.

UserPromptSubmit Hook에서 호출.
사용자 입력에서 키워드를 추출하고 관련 스킬을 검색해 반환한다.

검색 전략 (2단계):
  1단계 — skill_index 전수 스캔 + 부분 문자열 매칭 (빠름, 무료. FTS5 미사용)
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
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_skills import iter_skill_files  # noqa: E402  (스킬 파일 순회 공유 헬퍼)
from hermes_keywords import document_frequency, idf_score, split_keywords  # noqa: E402
from hermes_search_fallback import haiku_fallback  # noqa: E402  (claude -p 뉘앙스 폴백)
from hermes_skill_layers import (  # noqa: E402  (스킬 4층 필터 + 주입 순서)
    ensure_layer_columns, inject_order, layer_of_path, skill_visible)
from hermes_skill_render import inject_text  # noqa: E402  (주입 렌더링)
from hermes_skill_extends import parse_extends, resolve_base_path  # noqa: E402  (확장 합성)


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



def _name_bonus(skill_path: str, matched: list, df, total: int) -> float:
    """스킬 이름(파일명 슬러그 또는 상위 폴더명)이 매칭 키워드와 같으면 가산.

    가산값은 **그 키워드의 희소성에 비례**한다. 고정값(+1.0)을 주면 흔한 말일수록
    가산이 본래 신호보다 커져 순위를 뒤집는다 — `api`(42%)의 IDF 는 0.87 이므로
    +1.0 은 그 말 자체보다 큰 힘이 된다. 동점을 가르는 것이 목적이지 덮는 것이
    아니므로, 이름이 곧 주제라는 신호를 그 키워드의 무게만큼만 더한다.
    """
    base = os.path.basename(skill_path)
    slug = os.path.basename(os.path.dirname(skill_path)) if base == "SKILL.md" else base[:-3]
    slug = slug.lower()
    if slug not in matched:
        return 0.0
    return idf_score([slug], df, total)

def resolve_viewer(project: str):
    """지금 세션 에이전트의 (agent_id, unit_id). HERMES_AGENT_ID 없으면 'main'.

    unit_id 는 명부의 그 에이전트 org.unit(이름)을 organization.yaml 의 unit_id 로 옮긴 값.
    명부·조직이 없거나 매핑이 안 되면 unit_id 는 None — 그러면 unit 층은 아무도 못 본다(안전측).
    """
    agent_id = os.environ.get("HERMES_AGENT_ID") or "main"
    unit_id = None
    try:
        from hermes_roster import load_roster, find_agent
        from hermes_org import load_org
        agent = find_agent(load_roster(project), agent_id)
        unit_name = ((agent or {}).get("org") or {}).get("unit")
        if unit_name:
            unit_id = ((load_org(project).get("unit") or {}).get(unit_name) or {}).get("unit_id")
    except Exception as e:
        _log(f"viewer 해석 실패(계속): {e}")
    return agent_id, unit_id


def search_db(db_path: str, keywords: list, max_results: int,
              viewer_agent_id: str = None, viewer_unit_id: str = None) -> list:
    """skill_index 에서 관련 스킬을 검색한다.

    관련도(질의 키워드 매칭 수) 우선 → 도움/사용 통계는 보조 정렬.
    매칭 수를 1차 키로 두면 갓 등록된(used=0) 스킬도 관련도가 높으면 상위 노출돼,
    used_count 만으로 정렬할 때 신규 스킬이 LIMIT 밖으로 굶던 콜드스타트를 구제한다(②).
    주입 필터(RV-12): 소환된 에이전트의 unit·agent 층만 남긴다.
    """
    if not os.path.isfile(db_path) or not keywords:
        return []

    kws = [kw.lower() for kw in keywords[:5]]
    try:
        con = connect_db(db_path)
        ensure_layer_columns(con)     # 층 칸 없는 구 DB 지연 마이그레이션(목표 16)
        rows = con.execute(
            "SELECT skill_path, keywords, COALESCE(helpful_count,0), COALESCE(used_count,0), "
            "layer, unit_id, agent_id "
            "FROM skill_index WHERE COALESCE(state,'active') != 'tombstoned'"
        ).fetchall()
        con.commit()
        con.close()
    except Exception as e:
        _log(f"DB 검색 실패: {e}")
        return []

    # 주입 필터 — 다른 단위·다른 개인의 층은 결과에서 뺀다(RV-12).
    rows = [(p, k, h, u, layer) for p, k, h, u, layer, unit_id, agent_id in rows
            if skill_visible(layer, unit_id, agent_id, viewer_agent_id, viewer_unit_id)]

    # 토큰 일치. 부분 문자열로 보면 두 글자 질의어가 긴 키워드 안에까지 걸려 후보가
    # 폭발한다 — 실측(zeroday, 실제 프롬프트 400건): 후보 중앙값이 부분 문자열 107개
    # 대 토큰 일치 14개, "선별 가능(1~20개)" 프롬프트가 59/400 대 272/400.
    # 근거: docs/exec-plans/active/2026-09-09-hermes-skill-lifecycle.md §7
    haystacks = [(path, set(split_keywords(kwfield)), kwfield, helpful, used, layer)
                 for path, kwfield, helpful, used, layer in rows]
    df = document_frequency(tokens for _p, tokens, _k, _h, _u, _l in haystacks)
    total = len(haystacks)

    scored = []
    for path, tokens, kwfield, helpful, used, layer in haystacks:
        matched = [kw for kw in kws if kw in tokens]
        if not matched:
            continue
        # 매칭 수만 세면 `basebutton`(5개 스킬에만 있음) 한 번 맞은 것과 흔한 말 한 번
        # 맞은 것이 동점이 되어, 정작 그 질문을 위해 만들어진 스킬이 밀린다. 드문
        # 키워드일수록 크게 세는 IDF 로 바꾼다 — 매칭이 많을수록 합도 커지므로
        # 예전의 "매칭 수" 정렬을 포함한다.
        score = idf_score(matched, df, total)
        # 이름이 곧 주제다. 같은 키워드를 가진 스킬이 여럿일 때, 그 키워드를 제목으로
        # 삼은 스킬이 그 질문을 위해 만들어진 것이다 — 동점을 그대로 두면 4위로 밀린다.
        score += _name_bonus(path, matched, df, total)
        # 동점이면 키워드가 적은 스킬을 앞세운다. 질의어 하나만 맞으면 IDF 가 같아
        # 수백 개가 동점이 되는데, 그 키워드가 차지하는 비중이 큰 스킬일수록 그
        # 주제를 실제로 다루는 스킬이다. `hermes-evolve-skill.py` 의 대상 선정과
        # 같은 기준을 쓴다.
        scored.append(((score, helpful, used, -len(tokens)), path, kwfield, matched[0], layer))

    scored.sort(key=lambda x: x[0], reverse=True)     # 점수 → helpful → used 로 뽑고
    picked = inject_order(scored[:max_results], lambda x: x[4])   # 층 순으로 넣는다
    return [
        {"path": path, "keywords": kwfield, "matched": first}
        for _, path, kwfield, first, _layer in picked
    ]


def search_skills_dir(skills_dir: str, keywords: list, max_results: int,
                      project: str = None, viewer_agent_id: str = None,
                      viewer_unit_id: str = None) -> list:
    """스킬 디렉토리를 직접 탐색해 키워드 매칭 스킬을 찾는다.

    project 가 주어지면 색인 전 파일도 층으로 판정해 타 단위·타 개인 스킬을 뺀다(RV-12, 목표 15).
    """
    if not os.path.isdir(skills_dir) or not keywords:
        return []

    kws = [k.lower() for k in keywords]
    docs = []
    seen = set()
    for name, skill_md in iter_skill_files(skills_dir):
        if name in seen:
            continue
        seen.add(name)
        layer = None
        if project is not None:
            layer, unit_id, agent_id = layer_of_path(project, skill_md)
            if not skill_visible(layer, unit_id, agent_id, viewer_agent_id, viewer_unit_id):
                continue
        try:
            with open(skill_md, "r", encoding="utf-8") as f:
                content = f.read()
        except Exception as e:
            _log(f"스킬 읽기 실패({skill_md}): {e}")
            continue

        # 본문 전체 부분 문자열이 아니라 토큰 일치로 본다. 전자는 두 글자만 어딘가
        # 들어 있어도 걸려서, 1,000개가 넘는 결정화 스킬에서는 사실상 무작위였다.
        docs.append((name, skill_md, set(split_keywords(content)), layer))

    # 흔한 말은 **빼지 않고** 점수를 낮춘다. 빼면 그 프로젝트에서 가장 중요한 어휘가
    # 빈출이라는 이유로 사라져 재현율이 무너진다 — zeroday 에서 `swagger`(172개 스킬)를
    # 지우자 "스웨거 동기화 해줘" 가 0건이 됐다. IDF 는 흔한 말의 기여를 0 에 수렴시켜
    # 같은 효과를 재현율 손실 없이 낸다.
    df = document_frequency(tokens for _n, _p, tokens, _l in docs)
    total = max(len(docs), 1)

    scored = []
    for name, skill_md, tokens, layer in docs:
        matched = [kw for kw in kws if kw in tokens]
        if not matched:
            continue
        score = idf_score(matched, df, total)
        scored.append((score + _name_bonus(skill_md, matched, df, total), name, skill_md, matched[0], layer))

    scored.sort(key=lambda x: (-x[0], x[1]))          # 점수 → 이름 으로 뽑고
    picked = inject_order(scored[:max_results], lambda x: x[4])   # 층 순으로 넣는다
    return [
        {"name": name, "path": path, "matched": first}
        for _s, name, path, first, _layer in picked
    ]


def _compose_injection(db_path: str, name: str, path: str, prefix: str):
    """주입 텍스트를 만든다. 확장 파일이면 위 층 본문 뒤에 붙인다(RV-13, 목표 6)."""
    text = inject_text(name, path, prefix)
    if text is None:
        return None
    ext = parse_extends(path)
    if not ext:
        return text
    base = resolve_base_path(db_path, ext[0])
    if not base:
        return text
    base_text = inject_text(os.path.basename(base), base, prefix)
    return f"{base_text}\n[확장] {text}" if base_text else text


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
    # local[local_budget:] 은 항상 비어 있다 — 이 backfill 은 len(local) < local_budget 일 때만
    # 실행되므로 로컬 잔여분이 존재할 수 없다.
    if len(selected) < max_n:
        for entry in mesh[reserve:]:
            selected.append(entry)
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

    # 소환된 에이전트 신원 — 주입 필터(RV-12)에 쓴다. project 는 .hermes 의 부모.
    project = os.path.dirname(os.path.dirname(os.path.abspath(args.db)))
    viewer_agent, viewer_unit = resolve_viewer(project)

    # 1단계 — skill_index 전수 스캔 + 부분 문자열 매칭 (FTS5 미사용)
    db_results = search_db(args.db, keywords, args.max, viewer_agent, viewer_unit)

    hermes_skills_dir = os.path.join(os.path.dirname(args.db), "skills")
    dir_results = search_skills_dir(hermes_skills_dir, keywords, args.max,
                                    project, viewer_agent, viewer_unit)

    if args.skills_dir and os.path.isdir(args.skills_dir):
        dir_results += search_skills_dir(args.skills_dir, keywords, args.max,
                                         project, viewer_agent, viewer_unit)

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

    # 2단계 — FTS5 결과 없으면 Haiku fallback.
    # 배포된 훅은 둘 다 --no-fallback 을 넘기므로 이 경로는 production 에서 꺼져 있다.
    # 손으로 부르는 경우와 시험의 대조군을 위해 남겨 둔다(고아 코드가 아니다).
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
    # (텍스트, 경로, 그물망여부) 후보. 그물망 출처는 라벨로 구분한다 — Phase 2 PII/비밀 승격
    # 게이트 이전이라 출처 불명확 시 검증되지 않은 내용이 섞인 것처럼 보일 수 있다.
    candidates = []

    def _add(results, prefix, is_mesh):
        for r in results:
            name = r.get("name", os.path.basename(r["path"]))
            text = _compose_injection(args.db, name, r["path"], prefix)
            if text:
                candidates.append((text, r["path"], is_mesh))

    _add(db_results, "헤르메스 규칙", False)
    _add(dir_results, "헤르메스 규칙", False)
    _add(mesh_results, "헤르메스 규칙(그물망)", True)
    _add(haiku_results, "헤르메스 규칙(뉘앙스/claude-p)", False)

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
