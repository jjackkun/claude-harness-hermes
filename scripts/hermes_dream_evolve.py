#!/usr/bin/env python3
"""교정 요약에서 진화 대상을 고르고 진화를 실행한다.

hermes-dream.py 에서 분리했다(R-size 500줄 초과가 계기). dream 은 "무엇을 언제
돌릴지" 를 조율하고, 이 파일은 "어느 스킬을 어떤 피드백으로 고칠지" 를 정한다.

대상 어휘를 코드에 박지 않는 것이 이 파일의 핵심이다 — 박으면 그 목록에 없는
도메인에서는 진화가 영원히 0이 된다(novel-bc 실측 0%).
근거: docs/exec-plans/active/2026-09-09-hermes-skill-lifecycle.md 목표 3
"""

import os
import re
import sqlite3
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_keywords import document_frequency, split_keywords  # noqa: E402


def _log(msg: str) -> None:
    """진단은 stderr 로만 낸다."""
    print(f"[hermes-dream] {msg}", file=sys.stderr)


_CORRECTION_RE = re.compile(r"(말고|대신|바꿔|수정|틀려|잘못|아니라|아니고)")

# 한 번의 dream 이 띄울 진화 서브세션 상한. 예전에는 상한이 없었고, 코드에 박혀
# 있던 패키지·도구 이름 목록이 사실상 상한 노릇을 하고 있었다. 목록을 걷어내면
# 그 우연한 제동이 사라지므로 명시적으로 건다.
# 근거(실측 2026-09-09): 교정 문장은 활동일당 중앙 3건(zeroday 38일·novel-bc 5일·
# terminal-shipping 6일), 90분위 11·9·2. 진화 한 건은 최대 300초 서브세션이라
# 5 건이면 한 번의 dream 이 약 25분으로 묶인다. 상한에 걸려 버려지는 것은
# **가장 덜 구체적인** 힌트이고, 버렸다는 사실은 로그로 남긴다(조용한 손실 금지).
EVOLVE_MAX = int(os.environ.get("HERMES_DREAM_EVOLVE_MAX", "5"))


def skill_name_frequency(con) -> dict:
    """스킬 **이름**에 쓰인 토큰과 그 토큰의 문서빈도.

    진화 대상을 고를 어휘를 그 프로젝트 자신에게서 얻는다. 기술어 목록을 코드에
    박으면 그 목록에 없는 도메인(소설·물류 등)에서는 진화가 영원히 0이다 —
    novel-bc 실측 진화율 0% 가 그 형태였다.

    후보를 본문 키워드 전체가 아니라 **이름 토큰**으로 좁히는 이유: 진화는 스킬
    파일을 승인도 백업도 없이 덮어쓴다(`hermes-evolve-skill.py`). 잘못 고른
    키워드는 멀쩡한 스킬을 망치므로 재현율보다 정밀도가 비싸다. 본문 전체를 쓰면
    `작업의` `2건` 같은 말이 뽑혔고, 이름으로 좁히니 `kiosk` `백엔드` `유니패스`
    처럼 실제 주제어가 나왔다(실측 2026-09-09).
    """
    try:
        rows = con.execute("SELECT skill_path, keywords FROM skill_index").fetchall()
    except sqlite3.OperationalError as e:
        if "no such table" not in str(e):
            raise
        _log(f"skill_index 없음 — 진화 힌트 수집 건너뜀: {e}")
        return {}

    df = document_frequency(set(split_keywords(kwfield)) for _p, kwfield in rows)
    names = set()
    for skill_path, _kwfield in rows:
        base = os.path.basename(skill_path)
        slug = os.path.basename(os.path.dirname(skill_path)) if base == "SKILL.md" else base[:-3]
        names.update(split_keywords(slug.replace("-", " ").replace("_", " ")))
    # 숫자만인 토큰은 이름의 일련번호일 뿐 주제가 아니다(`r-struct-3` 의 `3`).
    return {t: df[t] for t in names if t in df and not t.isdigit()}


def _correction_items(summaries):
    """요약 슬롯에서 교정으로 읽히는 문장만 흘려보낸다."""
    for s in summaries:
        for k in ("open", "next", "decisions"):
            for item in (s["slots"].get(k) or []):
                if isinstance(item, str) and _CORRECTION_RE.search(item):
                    yield item

def collect_evolution_hints(summaries, name_df: dict) -> list:
    """교정 문장에서 진화 대상 키워드를 뽑는다. 구체적인 것부터 EVOLVE_MAX 개.

    한 문장에서 고르는 키워드는 스킬 이름에 쓰인 토큰 중 **가장 드문 것** 하나다.
    드물수록 가리키는 스킬이 좁아진다 — 흔한 말을 고르면 아무 스킬이나 진화시킨다.
    """
    if not name_df:
        return []
    scored, seen = [], set()
    for item in _correction_items(summaries):
        candidates = [(name_df[t], t) for t in split_keywords(item) if t in name_df]
        if not candidates:
            continue
        freq, kw = min(candidates)
        # 키워드로 중복을 제거한다. 같은 스킬을 한 번의 dream 에서 두 번 진화시킬 수
        # 없고(24시간 쿨다운), 두 번째는 슬롯만 축낸다.
        if kw in seen:
            continue
        seen.add(kw)
        scored.append((freq, kw, item[:200]))

    scored.sort(key=lambda x: x[0])  # 드문 것(=구체적인 것) 먼저
    if len(scored) > EVOLVE_MAX:
        _log(f"진화 힌트 {len(scored)}건 중 상한 {EVOLVE_MAX}건만 진행 — "
             f"나머지 {len(scored) - EVOLVE_MAX}건은 덜 구체적인 순으로 제외")
    return [(kw, feedback) for _freq, kw, feedback in scored[:EVOLVE_MAX]]


def run_evolve(hints, db, scripts_dir) -> int:
    n = 0
    for kw, feedback in hints:
        try:
            result = subprocess.run(
                ["python3", os.path.join(scripts_dir, "hermes-evolve-skill.py"),
                 "--db", db, "--keyword", kw, "--feedback", feedback],
                capture_output=True, text=True, timeout=300,
                env={**os.environ, "HERMES_DISABLED": "1"},
            )
            if "EVOLVED:" in result.stdout:
                n += 1
        except Exception as e:
            _log(f"evolve 오류({kw}): {e}")
    return n
