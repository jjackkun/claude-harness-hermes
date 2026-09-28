#!/usr/bin/env python3
"""아직 판정하지 않은 문장들을 haiku 한 번으로 "개인적 · 업무 무관" 인지 가려 판정 표에 적는 것만 담당한다.

요약은 요약 호출이 함께 가린다(hermes-summarize) — 여기는 기억 본문 · 이력의 교훈·결정 · 스킬 본문처럼
요약 호출을 거치지 않는 문장용이다. 구독 CLI 경유(R3). 게이트는 이것을 부르지 않는다(게이트는 모델을 안 부른다).
판정에 실패하면 받은 문장을 **모두 검토 대기**로 둔다 — 조용히 올라가는 쪽이 더 위험하다.
계획: docs/exec-plans/active/2026-09-28-carry-agent-knowledge.md 목표 2

공개: RULE · judge_and_mark
"""

import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_privacy_pending import mark, status_of  # noqa: E402

RULE = ("개인적인 내용(건강·가족·감정·사생활·특정인에 대한 평가)이나 업무와 무관한 잡담이면 표시한다. "
        "업무 결정·사실·할 일·기술 내용은 표시하지 않는다.")
_PROMPT = """\
아래 번호 붙은 문장마다 저장소에 올려도 되는지 가려라. {rule}
JSON 만 출력한다: {{"flagged": [표시할 번호들]}}

{items}
"""
_MODEL = "claude-haiku-4-5-20251001"   # 요약 호출과 같은 모델(hermes-summarize)
_TIMEOUT = 60                          # 요약 호출과 같은 한도(hermes-summarize)
_BATCH_CHARS = 6000                    # 한 번에 보내는 글자 수 — 요약 호출의 델타 상한과 같다(hermes-summarize delta[:6000])


def _ask(texts: list):
    """표시된 번호 집합, 실패하면 None."""
    if not shutil.which("claude"):
        return None
    items = "\n".join(f"{i}. {t}" for i, t in enumerate(texts))
    try:
        out = subprocess.run(["claude", "-p", "--model", _MODEL],
                             input=_PROMPT.format(rule=RULE, items=items), capture_output=True, text=True,
                             timeout=_TIMEOUT, env={**os.environ, "HERMES_DISABLED": "1"})
        if out.returncode != 0:
            return None
        body = re.sub(r"^```[a-z]*\n|\n```$", "", out.stdout.strip())
        flagged = json.loads(body).get("flagged")
        return {int(i) for i in flagged} if isinstance(flagged, list) else None
    except (subprocess.SubprocessError, OSError, ValueError, TypeError, AttributeError):
        return None


def _batches(fresh: list) -> list:
    """글자 수 상한으로 나눈다. 상한보다 긴 문장 하나는 혼자 한 묶음(자르면 뒤쪽을 못 본다)."""
    out, cur, size = [], [], 0
    for item in fresh:
        n = len(str(item[2]))
        if cur and size + n > _BATCH_CHARS:
            out.append(cur)
            cur, size = [], 0
        cur.append(item)
        size += n
    return out + ([cur] if cur else [])


def judge_and_mark(con, items: list) -> int:
    """items = [(kind, ref, text)]. 이미 판정한 문장은 건너뛴다. 새로 판정한 수를 돌려준다."""
    seen, fresh = set(), []
    for k, r, t in items:
        if str(t).strip() and t not in seen and status_of(con, t) is None:
            seen.add(t)
            fresh.append((k, r, t))
    for batch in _batches(fresh):
        flagged = _ask([t for _, _, t in batch])
        for i, (kind, ref, text) in enumerate(batch):
            mark(con, kind, ref, text, "pending" if flagged is None or i in flagged else "clean")
        con.commit()
    return len(fresh)
