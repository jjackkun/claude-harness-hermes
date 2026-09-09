#!/usr/bin/env python3
"""키워드 토큰화와 희소성(IDF) 채점.

이 모듈의 책임은 **채점 하나**다. DB 도 파일도 건드리지 않는다.

왜 IDF 인가:
  `hermes_skills.extract_keywords` 는 스킬 문서의 2글자 이상 토큰을 전부 키워드로
  넣는다. 불용어 필터가 없어 zeroday 에서는 `확인` 이 전체 스킬의 67%, `api` 42%,
  `먼저` 35% 에 붙었다. 매칭 수만 세면 이런 말 한 번 맞은 것과 `basebutton`(5개
  스킬에만 있음) 한 번 맞은 것이 동점이 되어, 그 질문을 위해 만들어진 스킬이 밀린다.

왜 흔한 말을 **지우지** 않는가:
  한때 문서빈도가 높은 키워드를 인덱스에서 지우는 방향을 시도했다가 되돌렸다.
  집중된 코퍼스에서는 그 프로젝트의 **가장 중요한 어휘가 곧 빈출 어휘**다 —
  zeroday 에서 `swagger`(172개 스킬)를 지우자 "스웨거 동기화 해줘" 가 0건이 됐다.
  IDF 는 흔한 말의 기여를 0 에 수렴시켜 같은 효과를 재현율 손실 없이 낸다.
  근거: docs/exec-plans/active/2026-09-09-hermes-skill-lifecycle.md §7

왜 불용어 목록이 아닌가:
  목록을 손으로 적으면 그것이 곧 도메인 어휘 하드코딩이다(같은 계획서 목표 3 이
  없애려는 바로 그것). IDF 는 각 프로젝트의 자기 코퍼스에서 계산되므로 어휘를
  하나도 박지 않는다.
"""

import collections
import math
import re

_SPLIT_RE = re.compile(r"[,\s]+")


def split_keywords(field: object) -> list:
    """키워드 문자열·문서 본문을 토큰 목록으로. 순서를 보존한다."""
    if not isinstance(field, str):
        return []
    return [t for t in _SPLIT_RE.split(field.lower()) if t]


def document_frequency(token_sets) -> collections.Counter:
    """토큰 집합들의 문서빈도."""
    df = collections.Counter()
    for tokens in token_sets:
        for token in tokens:
            df[token] += 1
    return df


def idf_score(matched: list, df: collections.Counter, total: int) -> float:
    """매칭된 키워드의 희소성 합. 드문 키워드일수록 크다.

    매칭이 많을수록 합도 커지므로 예전의 "매칭 수" 정렬을 포함한다.
    """
    if total <= 0:
        return 0.0
    return sum(math.log(total / df[token]) for token in matched if df.get(token))
