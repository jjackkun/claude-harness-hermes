#!/usr/bin/env python3
"""스킬 수익률 판정 — 주입 증거로 도움 없는 스킬을 고르고, 일반 코드 단어 키를 결정화 전에 거른다.

zeroday-frontend 실측(2026-09-18, 스킬 1,095 · 주입 3,471): 단일 영단어 키(`array`·`shared`·`index`·`postgres`)
167개가 주입의 75% 를 차지하며 도움률 3.9%, 2+토큰 구절은 99.6%. 세 파일이 각 775회 주입되고 도움 2회 —
본문은 유용한데 키가 압축 요약 속 흔한 코드 단어로 뽑혀 제목이 됐고, 그 제목이 거의 모든 프롬프트에 매칭됐다.

두 장치:
  - low_yield_skills(con): 주입 ≥ MIN_INJECTIONS 이고 도움률 ≤ MAX_HELPFUL_RATE 인 스킬. 둘 다 만족해야 한다 —
    새 스킬(주입 적음)은 보호한다. 50회면 5% 기대 도움이 2.5회라 우연히 0 이 나올 확률 (0.95)^50 ≈ 7.7%.
  - is_generic_key(key): 단일 ASCII 토큰이 일반 코드 단어 목록에 있으면 참. 목록 밖 단일 토큰(`noticemanagementpage`)은
    거부하지 않는다 — 실측 도움률 85%.

어휘·이벤트로만 판정한다(R3). 표준 라이브러리만 import 한다(.deprc tier 0).
공개 함수 2개: low_yield_skills · is_generic_key
계획: docs/exec-plans/completed/2026-09-18-skill-yield-junk.md
"""
import re
import sqlite3

MIN_INJECTIONS = 50
MAX_HELPFUL_RATE = 0.05

# 압축 요약·코드에 흔히 나와 패턴 키로 잘못 뽑히는 단어. 규칙 주제일 수 없는 것만 넣는다.
GENERIC_CODE_WORDS = frozenset("""
array shared index docs doc src lib dist build public assets static utils util helpers helper common core
config configs settings main app apps module modules component components page pages view views
data file files type types list string number object function class method value values item items
test tests spec mock fixture fixtures temp tmp cache log logs error errors result results
postgres mysql sqlite redis node npm pnpm yarn python js ts json yaml html css
""".split())

_TOKEN_SEP = re.compile(r"[-_\s]")


def is_generic_key(key: str) -> bool:
    """단일 ASCII 토큰이면서 일반 코드 단어면 참. 구절(구분자 포함)·한글은 거짓."""
    k = (key or "").strip().lower()
    if not k or _TOKEN_SEP.search(k) or not k.isascii():
        return False
    return k in GENERIC_CODE_WORDS


def _has_table(con: sqlite3.Connection, name: str) -> bool:
    return con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)).fetchone() is not None


def low_yield_skills(con: sqlite3.Connection, min_injections: int = MIN_INJECTIONS,
                     max_helpful_rate: float = MAX_HELPFUL_RATE) -> list:
    """[{skill_path, injected, helpful, rate}] — 주입 충분·도움 희박한 로컬 스킬. 표가 없으면 []."""
    if not (_has_table(con, "skill_injection") and _has_table(con, "skill_index")):
        return []
    rows = con.execute(
        "SELECT i.skill_path, COUNT(*) AS injected, "
        "SUM(CASE WHEN i.correlated THEN 1 ELSE 0 END) AS helpful "
        "FROM skill_injection i JOIN skill_index s ON s.skill_path = i.skill_path "
        "WHERE s.scope = 'local' GROUP BY i.skill_path").fetchall()
    out = []
    for path, injected, helpful in rows:
        helpful = helpful or 0
        rate = helpful / injected if injected else 0.0
        if injected >= min_injections and rate <= max_helpful_rate:
            out.append({"skill_path": path, "injected": injected, "helpful": helpful, "rate": rate})
    return sorted(out, key=lambda r: -r["injected"])
