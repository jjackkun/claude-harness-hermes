#!/usr/bin/env python3
"""관찰 + 판정 + 결정 → "지금 주입할 것 / 물을 것" 과 주입 글.

상태 다섯: approved(사람 승인) · auto(기준을 넘어 묻지 않고 활성) · pending(승인 때 물을 것) ·
hold(쌓기만) · rejected(사람 거부 — 자동 활성이어도 빠진다).
기계 병합(접두어·유사도 ≥ 0.8)은 볼 때마다 다시 계산하고, 사람이 정한 별칭이 먼저다.
근거: docs/exec-plans/completed/2026-09-22-user-persona-distill-plan.md §6
"""

import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hermes_persona_decisions as dec  # noqa: E402
from hermes_persona_score import classify_key, merge_pairs, score_key  # noqa: E402

# SOUL 주입 상한과 같은 값(claude-sessionstart-agent-soul.sh) — 성향도 "이 사람이 누구인가" 를 적은 한 장이다.
INJECT_MAX_BYTES = 4096


def _observations(con) -> dict:
    rows = con.execute(
        "SELECT facet, key, statement, tier, session_id, observed_at FROM persona_observation"
    ).fetchall()
    grouped = defaultdict(list)
    for facet, key, statement, tier, sid, when in rows:
        grouped[f"{facet}/{key}"].append({"facet": facet, "statement": statement, "tier": tier,
                                          "session_id": sid, "observed_at": when})
    return grouped


def _auto_targets(grouped: dict, pinned: set) -> dict:
    """기계 병합 대상: 라벨 → 합쳐 들어갈 라벨. 관찰이 많은 쪽(같으면 짧은 쪽)으로 모은다.

    사람이 손댄 라벨(별칭·승인·거부)은 **흡수만 하고 흡수되지 않는다** — 흡수되면 결정이 원래 라벨에
    남아 합친 뒤 라벨에서 안 보이고, 거부한 성향이 되살아난다(2026-09-22 리뷰 HIGH). 거부한 라벨에
    닮은 새 키가 붙으면 그 키도 거부를 따른다. 양쪽 다 사람 것이면 합치지 않는다."""
    order = lambda x: (-len(grouped[x]), len(x), x)   # noqa: E731  앞설수록 남는 쪽
    edges = {}
    for a, b, verdict in merge_pairs([tuple(label.split("/", 1)) + ("",) for label in grouped]):
        if verdict != "auto" or (a in pinned and b in pinned):
            continue
        keep, drop = sorted((a, b), key=lambda x: (x not in pinned,) + order(x))
        if drop not in edges or (keep not in pinned,) + order(keep) < (edges[drop] not in pinned,) + order(edges[drop]):
            edges[drop] = keep
    # 한 방향(뒤 → 앞)으로만 이어지므로 끝까지 따라가도 돌지 않는다 — A→B→C 면 A 도 C 로.
    def root(label):
        while label in edges:
            label = edges[label]
        return label
    return {label: root(label) for label in edges}


def _human_root(label: str, human: dict) -> str:
    """사람 별칭을 끝까지 따라간다(A→B→C 면 C). 돌면 멈춘다."""
    seen = set()
    while label in human and label not in seen:
        seen.add(label)
        label = human[label]
    return label


def _group_decision(label: str, members: set, decided: dict):
    """대표 라벨의 결정 → 없으면 합쳐진 라벨들의 결정. 거부가 승인보다 앞선다(주입하지 않는 쪽이 안전)."""
    if label in decided:
        return decided[label]
    states = {decided[m] for m in members if m in decided}
    return "rejected" if "rejected" in states else ("approved" if states else None)


def build_view(con, now) -> dict:
    """items(라벨별 상태) · auto_merges · merge_questions."""
    dec.ensure_schema(con)
    grouped, human, decided = _observations(con), dec.aliases(con), dec.decisions(con)
    auto = _auto_targets(grouped, set(human) | set(human.values()) | set(decided))
    merged, members = defaultdict(list), defaultdict(set)
    for label, obs in grouped.items():
        target = _human_root(label, human) if label in human else auto.get(label, label)
        merged[target].extend(obs)
        members[target].add(label)
    items = []
    for label, obs in merged.items():
        verdict = classify_key(obs, now)
        state = (_group_decision(label, members[label], decided)
                 or {"auto": "auto", "ask": "pending"}.get(verdict, "hold"))
        items.append({"label": label, "state": state, "score": score_key(obs, now),
                      "sessions": len({o["session_id"] for o in obs}),
                      "statement": Counter(o["statement"] for o in obs).most_common(1)[0][0]})
    questions = [(a, b) for a, b, v in merge_pairs([tuple(x.split("/", 1)) + ("",) for x in merged])
                 if v == "ask"]
    return {"items": sorted(items, key=lambda i: -i["score"]),
            "auto_merges": sorted(auto.items()), "merge_questions": questions}


def _active(items: list) -> list:
    """주입할 것 — 사람이 승인한 것 먼저(잘릴 때 살아남게), 그다음 자동 활성. 각각 점수순."""
    return [i for i in items if i["state"] == "approved"] + [i for i in items if i["state"] == "auto"]


def _footer(view: dict) -> str:
    pending = sum(1 for i in view["items"] if i["state"] == "pending") + len(view["merge_questions"])
    return f"[persona] 승인 대기 {pending}건 — python3 scripts/hermes-persona.py review" if pending else ""


def _fit(lines: list, active: list, budget: int) -> list:
    """상한 안에서 성향 줄을 채운다. 넘치면 생략 줄 하나로 끝낸다."""
    for n, item in enumerate(active):
        # 문장 속 줄바꿈으로 가짜 줄("- [승인됨] …")을 끼워 넣지 못하게 한 줄로 편다(2026-09-22 리뷰).
        line = "- " + " ".join(str(item["statement"]).split())
        if len("\n".join(lines + [line]).encode()) > budget:
            return lines + [f"- … ({len(active) - n}개 생략 — python3 scripts/hermes-persona.py review)"]
        lines = lines + [line]
    return lines


def render_injection(view: dict, cap: int = INJECT_MAX_BYTES) -> str:
    """세션 시작에 넣을 글. 넣을 것도 물을 것도 없으면 빈 문자열."""
    active, footer = _active(view["items"]), _footer(view)
    if not active:
        return footer
    approved = sum(1 for i in active if i["state"] == "approved")
    head = [f"[사용자 성향] 대화에서 되풀이된 이 사용자의 성향이다 "
            f"(승인 {approved} · 자동 활성 {len(active) - approved}). 규칙·지시와 어긋나면 규칙이 우선이다."]
    reserve = len(footer.encode()) + 120   # 생략 줄 + 알림 줄 자리
    return "\n".join(_fit(head, active, cap - reserve) + ([footer] if footer else []))
