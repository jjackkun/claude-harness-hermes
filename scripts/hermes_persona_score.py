#!/usr/bin/env python3
"""성향 관찰의 점수·세 갈래 판정·합치기 분류. 계산만 한다 — DB·LLM 을 건드리지 않는다.

원칙: **스스로 정할 수 있는 것은 묻지 않는다**(2026-09-22 사용자). 판정은 셋이다.
  auto — 사람이 직접 말한 지시(t0)가 2세션 이상 되풀이됐고 점수가 활성 문턱 이상 → 묻지 않고 활성
  ask  — 추론(t1·t2)으로 2세션 이상 + 후보 문턱 이상 → 승인 때 한 번에 묶어 질문
  hold — 그 밖(1세션뿐·식었음) → 묻지 않고 쌓기만
가중치·문턱·감쇠는 OpenHuman `agent/learning/stability_detector.rs` 의 값을 출발점으로 둔다(코드는 옮기지 않음, GPL).
근거: docs/exec-plans/completed/2026-09-22-user-persona-distill-plan.md §6
"""

import difflib
import math
from datetime import datetime

ACTIVE_SCORE = 1.5      # OpenHuman Active 문턱
CANDIDATE_SCORE = 0.7   # OpenHuman Provisional 문턱
_TIER_WEIGHT = {"t0": 2.0, "t1": 1.0, "t2": 1.0}   # 명시적 지시는 2배(OpenHuman)
# exp(-Δt/감쇠일) 의 감쇠일. 정체성에 가까운 면은 느리게, 말투·방식은 빠르게 식는다(OpenHuman 90일/14일).
_DECAY_DAYS = {"stack": 90.0, "environment": 90.0}
_DEFAULT_DECAY_DAYS = 14.0
_MIN_SESSIONS = 2
# 합치기 문턱 — 2026-09-22 실측(키 29개): 유사 쌍 0.86 하나와 나머지 ≤ 0.50 사이의 틈에 둔다.
_MERGE_AUTO = 0.8
_MERGE_ASK = 0.6


def _age_days(obs: dict, now: datetime):
    try:
        seen = datetime.fromisoformat(str(obs.get("observed_at")).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None   # 언제인지 모르면 최근성도 모른다 — 점수에 넣지 않는다
    return max((now - seen).total_seconds() / 86400.0, 0.0)


def score_key(observations: list, now: datetime) -> float:
    """한 성향의 점수. 세션마다 가장 강한 관찰 하나만 센다 — 한 자리의 되풀이는 반복이 아니다."""
    best_per_session = {}
    for obs in observations:
        age = _age_days(obs, now)
        if age is None:
            continue
        decay = _DECAY_DAYS.get(obs.get("facet"), _DEFAULT_DECAY_DAYS)
        weight = _TIER_WEIGHT.get(obs.get("tier"), 0.0) * math.exp(-age / decay)
        sid = obs.get("session_id")
        best_per_session[sid] = max(best_per_session.get(sid, 0.0), weight)
    return sum(best_per_session.values())


def classify_key(observations: list, now: datetime) -> str:
    """auto · ask · hold 중 하나."""
    sessions = {o.get("session_id") for o in observations if _age_days(o, now) is not None}
    if len(sessions) < _MIN_SESSIONS:
        return "hold"
    score = score_key(observations, now)
    if any(o.get("tier") == "t0" for o in observations) and score >= ACTIVE_SCORE:
        return "auto"
    return "ask" if score >= CANDIDATE_SCORE else "hold"


def merge_pairs(keys: list) -> list:
    """같은 면 안에서 합칠 쌍 [(면/키, 면/키, auto|ask)]. 문턱 아래 쌍은 돌려주지 않는다(별개 성향)."""
    labels = sorted({f"{facet}/{key}" for facet, key, _statement in keys})
    pairs = []
    for i, a in enumerate(labels):
        for b in labels[i + 1:]:
            facet_a, key_a = a.split("/", 1)
            facet_b, key_b = b.split("/", 1)
            if facet_a != facet_b:
                continue
            prefix = key_a.startswith(key_b) or key_b.startswith(key_a)
            ratio = difflib.SequenceMatcher(None, key_a, key_b).ratio()
            if prefix or ratio >= _MERGE_AUTO:
                pairs.append((a, b, "auto"))
            elif ratio >= _MERGE_ASK:
                pairs.append((a, b, "ask"))
    return pairs
