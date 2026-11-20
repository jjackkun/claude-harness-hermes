#!/usr/bin/env python3
"""아직 판정하지 않은 문장들을 haiku 한 번으로 "개인적 · 업무 무관" 인지 가려 판정 표에 적는 것만 담당한다.

요약은 요약 호출이 함께 가린다(hermes-summarize) — 여기는 기억 본문 · 이력의 교훈·결정 · 스킬 본문처럼
요약 호출을 거치지 않는 문장용이다. 구독 CLI 경유(R3). 게이트는 이것을 부르지 않는다(게이트는 모델을 안 부른다).
판정에 실패한 묶음은 반으로 나눠 다시 묻는다. 끝내 판정하지 못한 문장은 **판정 기록 없이** 둔다 — 기록이 없으면
내보내기·게이트가 막으므로 안전은 같고, 다음 내보내기 때 다시 판정된다. (처음엔 실패 = 대기였는데, 실측에서 묶음 하나
115문장이 통째로 사람 확인 대기로 쌓였다 — 2026-09-28, 이 공장 저장소.)
상한: 한 번 판정에 호출 _MAX_CALLS 번 · _MAX_SECONDS 초까지. 시간 초과는 나눠도 빨라지지 않으므로 나누지 않는다.
실패 이유와 남긴 수는 stderr 로 남긴다(세션 끝 훅이 hooks.log 로 모은다). 2026-11-20 drh-cloth-shop: 153문장 3묶음에서
호출이 계속 실패하면 반으로 나누기를 거듭해 303번(최악 303분)을 불렀다 — 내보내기가 두 번 연속 200초 넘게 멈춰 보였다.
계획: docs/exec-plans/completed/2026-09-28-carry-agent-knowledge.md 목표 2

공개: RULE · judge_and_mark
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_machine_prompt import machine_prompt_cmd  # noqa: E402  (기계 프롬프트는 도구 없이)
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
_MAX_CALLS = 6                         # 한 번 판정의 호출 상한 — 정상이면 묶음 수(보통 1~3)면 끝난다
_MAX_SECONDS = 300                     # 한 번 판정의 시간 상한 — 세션 끝 훅을 5분 넘게 붙잡지 않는다
_BATCH_CHARS = 6000                    # 한 번에 보내는 글자 수 — 요약 호출의 델타 상한과 같다(hermes-summarize delta[:6000])


def _ask(texts: list) -> tuple:
    """(표시된 번호 집합, "ok") 또는 (None, 실패 이유: nocli · timeout · exit · parse)."""
    if not shutil.which("claude"):
        return None, "nocli"
    items = "\n".join(f"{i}. {t}" for i, t in enumerate(texts))
    try:
        out = subprocess.run(machine_prompt_cmd(_MODEL),
                             input=_PROMPT.format(rule=RULE, items=items), capture_output=True, text=True,
                             timeout=_TIMEOUT, env={**os.environ, "HERMES_DISABLED": "1"})
    except subprocess.TimeoutExpired:
        return None, "timeout"
    except (subprocess.SubprocessError, OSError):
        return None, "exit"
    if out.returncode != 0:
        return None, "exit"
    try:
        body = re.sub(r"^```[a-z]*\n|\n```$", "", out.stdout.strip())
        flagged = json.loads(body).get("flagged")
        return ({int(i) for i in flagged}, "ok") if isinstance(flagged, list) else (None, "parse")
    except (ValueError, TypeError, AttributeError):
        return None, "parse"


class _Budget:
    """호출 수 · 시간 상한과 실패 이유를 센다."""

    def __init__(self):
        self.calls, self.started, self.failures = 0, time.monotonic(), {}

    def take(self) -> bool:
        if self.calls >= _MAX_CALLS or time.monotonic() - self.started >= _MAX_SECONDS:
            return False
        self.calls += 1
        return True

    def failed(self, why: str) -> None:
        self.failures[why] = self.failures.get(why, 0) + 1


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


def _judge_batch(con, batch: list, budget: _Budget) -> int:
    """한 묶음을 판정해 적는다. 형식 오류면 반씩 나눠 다시(예산 안에서). 판정한 수(못 한 문장은 기록 없이 남는다)."""
    if not budget.take():
        return 0
    flagged, why = _ask([t for _, _, t in batch])
    if flagged is None:
        budget.failed(why)
        if why in ("timeout", "nocli") or len(batch) == 1:
            return 0   # 시간 초과는 나눠도 빨라지지 않는다 — 다음 내보내기 때 다시
        half = len(batch) // 2
        return _judge_batch(con, batch[:half], budget) + _judge_batch(con, batch[half:], budget)
    for i, (kind, ref, text) in enumerate(batch):
        mark(con, kind, ref, text, "pending" if i in flagged else "clean")
    con.commit()
    return len(batch)


def judge_and_mark(con, items: list) -> int:
    """items = [(kind, ref, text)]. 판정 기록이 없는 문장만 판정한다. 판정한 수를 돌려준다."""
    seen, fresh = set(), []
    for k, r, t in items:
        if str(t).strip() and t not in seen and status_of(con, t) is None:
            seen.add(t)
            fresh.append((k, r, t))
    budget = _Budget()
    judged = sum(_judge_batch(con, batch, budget) for batch in _batches(fresh))
    if budget.failures or judged < len(fresh):
        print(f"[hermes-privacy-judge] 판정 {judged} · 남김 {len(fresh) - judged} · 호출 {budget.calls}"
              f" · 실패 {budget.failures} (다음 내보내기 때 다시)", file=sys.stderr)
    return judged
