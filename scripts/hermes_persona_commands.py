#!/usr/bin/env python3
"""성향 CLI 의 결정 명령 — review · approve · reject · merge · render.

사람이 할 일은 review 한 번에 모은다: 자동 활성·자동 병합은 기록으로만 보이고(되돌리기 안내),
물을 것은 승인 대기·합치기 질문뿐이다.
근거: docs/exec-plans/completed/2026-09-22-user-persona-distill-plan.md 목표 4 · §6
"""

import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hermes_persona_decisions as dec  # noqa: E402
from hermes_persona_view import build_view, render_injection  # noqa: E402

_CLI = "python3 scripts/hermes-persona.py"


def _view(con) -> dict:
    return build_view(con, datetime.now(timezone.utc))


def _section(title: str, rows: list, hint: str) -> list:
    if not rows:
        return []
    return [f"[{title} {len(rows)}] {hint}"] + [f"  {r}" for r in rows]


def cmd_review(con, args) -> int:
    view = _view(con)
    fmt = lambda i: f"{i['label']} (점수 {i['score']:.2f} · {i['sessions']}세션): {i['statement']}"  # noqa: E731
    by = lambda s: [fmt(i) for i in view["items"] if i["state"] == s]  # noqa: E731
    lines = (_section("승인 대기", by("pending"), f"— {_CLI} approve <라벨…> | approve --all-pending")
             + _section("합치기 질문", [f"{a} ↔ {b}" for a, b in view["merge_questions"]],
                        f"— {_CLI} merge <합칠 라벨> <남길 라벨>")
             + _section("자동 활성", by("auto"), f"— 묻지 않고 주입 중. 되돌리기: {_CLI} reject <라벨>")
             + _section("자동 병합", [f"{a} → {b}" for a, b in view["auto_merges"]], "— 기록")
             + _section("승인됨", by("approved"), ""))
    print("\n".join(lines) if lines else "[persona] 정할 것 없음")
    return 0


def _known(con, labels: list) -> list:
    known = {i["label"] for i in _view(con)["items"]}
    unknown = [label for label in labels if label not in known]
    for label in unknown:
        print(f"[persona] 없는 성향: {label} — {_CLI} review 로 라벨을 확인하십시오", file=sys.stderr)
    return unknown


def cmd_decide(con, args, state: str) -> int:
    labels = list(args.labels)
    if getattr(args, "all_pending", False):
        labels += [i["label"] for i in _view(con)["items"] if i["state"] == "pending"]
        if not labels:
            print("[persona] 승인할 것 없음")
            return 0
    if not labels or _known(con, labels):
        return 2
    for label in labels:
        dec.set_decision(con, label, state)
    print(f"[persona] {state}: {', '.join(labels)}")
    return 0


def cmd_merge(con, args) -> int:
    if _known(con, [args.src, args.dst]):
        return 2
    dec.set_alias(con, args.src, args.dst)
    print(f"[persona] 합침: {args.src} → {args.dst}")
    return 0


def cmd_render(con, args) -> int:
    text = render_injection(_view(con))
    if text:
        print(text)
    return 0
