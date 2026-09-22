#!/usr/bin/env python3
"""사람 발화 묶음을 마스킹해 `claude -p`(haiku)에 보내고, 7면 관찰로 받아 검증한다.

이 모듈의 책임은 추출 하나다. DB 를 쓰지 않는다 — 저장은 hermes_persona_store.

왜 인용을 기계가 다시 대조하는가:
  모델은 그럴듯한 성향을 지어낼 수 있다. 관찰마다 붙은 인용(quote)이 그 번호의 발화 안에
  **글자 그대로** 있어야만 받는다. 지어낸 성향이 매 세션 주입되면 되돌리기 어렵다.
  근거: docs/exec-plans/completed/2026-09-22-user-persona-distill-plan.md 목표 2 · §6
"""

import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_redact import redact  # noqa: E402  (비밀값·연락처·주소 마스킹 공유 헬퍼)

# 요약기(hermes-summarize.py)와 같은 모델·입력 상한 — 같은 구독 CLI 비용 곡선 안에 둔다.
_MODEL = "claude-haiku-4-5-20251001"
# 요약기의 60초로는 모자랐다: 프롬프트 4,961자 묶음이 90.4초·79.1초(2026-09-22 실측).
# 실측 최댓값의 2배(여유 계수)로 둔다.
_CALL_TIMEOUT_SEC = 180
BATCH_MAX_CHARS = 6000
# 사람 발화 p90 이 89자(2026-09-22 실측 4,485개). 그보다 긴 것은 붙여 넣은 글이라 앞부분만 둔다.
UTTERANCE_MAX_CHARS = 500

_FACETS = {
    "communication": "말투·답변 형식에 대한 선호",
    "coding_style": "코드를 쓰는 방식에 대한 선호",
    "stack": "쓰는 언어·도구·환경 선택",
    "workflow": "일을 진행하는 순서·방식(커밋·검증·질문 빈도 등)",
    "environment": "작업 환경(OS·WSL·장비·경로)",
    "directives": "명시적으로 내린 지시·규칙",
    "anti_preferences": "싫어하거나 하지 말라고 한 것",
}
_TIERS = {
    "t0": "명시적 지시 — '항상 ~해', '~하지 마' 처럼 규칙으로 말함",
    "t1": "교정·중단 — 방금 한 일을 고치라거나 멈추라고 함",
    "t2": "습관 — 지시는 아니지만 되풀이되는 방식",
}
_KEY_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,39}$")


def build_batches(utterances: list) -> list:
    """발화를 마스킹·절단해 입력 상한 안의 묶음들로 나눈다."""
    batches, current, size = [], [], 0
    for utt in utterances:
        text = redact(utt["text"])[:UTTERANCE_MAX_CHARS]
        if current and size + len(text) > BATCH_MAX_CHARS:
            batches.append(current)
            current, size = [], 0
        current.append({**utt, "text": text})
        size += len(text)
    if current:
        batches.append(current)
    return batches


def build_prompt(batch: list, known_keys: list) -> str:
    """관찰 추출 지시문. known_keys = [(면, 키, 문장), ...] — 같은 성향엔 같은 키를 쓰게 한다."""
    facets = "\n".join(f"- {k}: {v}" for k, v in _FACETS.items())
    tiers = "\n".join(f"- {k}: {v}" for k, v in _TIERS.items())
    keys = "\n".join(f"- {f}/{k}: {s}" for f, k, s in known_keys) or "(아직 없음)"
    lines = "\n".join(f"[{i}] {u['text']}" for i, u in enumerate(batch, start=1))
    return (
        "아래는 한 사용자가 코딩 에이전트에게 친 말들이다. 이 사람의 **지속적인 성향**만 뽑아라.\n"
        "그 자리의 작업 지시(\"이 파일 고쳐\")는 성향이 아니다. 성향이 없으면 빈 배열 [] 을 내라.\n\n"
        f"면(facet):\n{facets}\n\n등급(tier):\n{tiers}\n\n"
        f"이미 있는 성향 — 같은 성향이면 이 키를 그대로 다시 써라:\n{keys}\n\n"
        "규칙: quote 는 해당 번호의 발화에서 **글자 그대로 복사한 짧은 구절**이어야 한다. 지어내지 마라.\n"
        "key 는 영문 소문자·숫자·하이픈 2~40자. statement 는 한국어 한 문장.\n"
        'JSON 배열만 출력하라: [{"n": 번호, "facet": "...", "key": "...", '
        '"statement": "...", "quote": "...", "tier": "t0|t1|t2"}]\n\n'
        f"발화:\n{lines}\n"
    )


def _json_array(output: str):
    """응답에서 JSON 배열을 꺼낸다. 모델이 앞뒤에 설명 글·코드 울타리를 붙이는 일이 있어
    (2026-09-22 실측: rc=0 인데 해석 실패 1/2) 첫 `[` 부터 마지막 `]` 까지를 다시 읽는다."""
    text = re.sub(r"^```[a-z]*\s*|\s*```$", "", output.strip())
    candidates = [text]
    start, end = text.find("["), text.rfind("]")
    if 0 <= start < end:
        candidates.append(text[start:end + 1])
    for candidate in candidates:
        try:
            items = json.loads(candidate)
        except (json.JSONDecodeError, ValueError):
            continue
        if isinstance(items, list):
            return items
    return None


def _fields_ok(item: dict) -> bool:
    """면·등급은 정해진 값, 키는 형식, 문장은 비어 있지 않아야 한다."""
    return bool(item.get("facet") in _FACETS and item.get("tier") in _TIERS
                and _KEY_RE.match(str(item.get("key") or "").strip())
                and str(item.get("statement") or "").strip())


def _check_item(item, batch: list):
    """항목 하나가 조건을 모두 지키면 그 발화를, 아니면 None."""
    if not isinstance(item, dict) or not _fields_ok(item):
        return None
    n = item.get("n")
    if not isinstance(n, int) or not 1 <= n <= len(batch):
        return None
    utt = batch[n - 1]
    quote = str(item.get("quote") or "").strip()
    # 인용이 그 발화 안에 글자 그대로 있어야 한다 — 지어낸 성향을 막는 핵심 대조.
    return utt if quote and quote in utt["text"] else None


def parse_observations(output: str, batch: list):
    """모델 응답을 검증된 관찰 목록으로. 조건을 어긴 항목만 버린다.

    응답 자체가 JSON 배열이 아니면 None — "성향 없음(빈 목록)" 과 구분해야
    호출이 망가진 묶음의 워터마크를 넘기지 않는다(넘기면 그 발화는 다시 안 읽힌다).
    """
    items = _json_array(output or "")
    if items is None:
        return None
    observations = []
    for item in items:
        utt = _check_item(item, batch)
        if utt is None:
            continue
        observations.append({
            "facet": item["facet"], "key": item["key"].strip(),
            "statement": item["statement"].strip(), "quote": item["quote"].strip(),
            "tier": item["tier"],
            "source_path": utt.get("source_path"), "line": utt.get("line"),
            "session_id": utt.get("session_id"), "observed_at": utt.get("timestamp"),
        })
    return observations


def extract_observations(batch: list, known_keys: list, run=subprocess.run):
    """묶음 하나를 모델에 보내 검증된 관찰을 돌려준다. 1회 재시도 뒤에도 실패면 None."""
    prompt = build_prompt(batch, known_keys)
    for _ in range(2):
        try:
            result = run(
                [os.environ.get("HERMES_CLAUDE_BIN", "claude"), "-p", prompt, "--model", _MODEL],
                capture_output=True, text=True, timeout=_CALL_TIMEOUT_SEC,
                env={**os.environ, "HERMES_DISABLED": "1"},
            )
        # 예외 문자열에는 명령 인자(= 사람 발화가 든 프롬프트)가 통째로 실린다 — 종류만 남긴다.
        except subprocess.TimeoutExpired:
            print(f"[hermes-persona] claude timeout ({_CALL_TIMEOUT_SEC}초)", file=sys.stderr)
            continue
        except OSError as e:
            print(f"[hermes-persona] claude 실행 불가: {type(e).__name__}", file=sys.stderr)
            continue
        if result.returncode != 0 or not (result.stdout or "").strip():
            print(f"[hermes-persona] claude rc={result.returncode}", file=sys.stderr)
            continue
        observations = parse_observations(result.stdout, batch)
        if observations is not None:
            return observations
        print("[hermes-persona] 응답이 JSON 배열이 아니다 — 재시도", file=sys.stderr)
    return None
