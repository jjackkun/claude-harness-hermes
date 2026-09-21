#!/usr/bin/env python3
"""스킬 발동 평가 — trigger-eval.json 을 harness-eval 시나리오로 바꾸고, 결과에서 정밀도·재현율을 계산한다.

9-20 에 skill-creator 의 평가기로 hermes-agent 발동률을 쟀을 때 재현율 28% 가 나왔지만 원인은 평가 방식이었다
(docs/audits/2026-09-20-hermes-agent-trigger-eval.md): 명령을 가짜 이름으로 바꿔 빈 루트에 심으니
`/hermes-agent` 슬래시조차 발동할 수 없었다. 여기서는 harness-eval 이 설치한 픽스처 프로젝트 안에서,
**진짜 스킬 이름**의 `Skill` 호출만 발동으로 센다.

주입 끔(`inject=False`)은 실행 사본의 `.hermes/state.db` 를 치운다 — 세션 훅은 그 파일이 있을 때만
`[Hermes 관련 규칙]` 을 붙인다(claude-userpromptsubmit-reminders.sh). 제품 훅에 시험용 스위치를 두지 않는다.

모델 호출 0. 공개 심볼: to_scenarios · trigger_metrics · render_metrics
"""
import re

LEVEL = "neutral"   # 발동 평가는 질의 그대로 한 단계만 — 부추김·반대 단계는 행동 평가(tests/agent-evals)의 몫
_INJECT_DB = ".hermes/state.db"


def _scenario_id(idx):
    return f"trig-{idx:02d}"


def to_scenarios(skill, queries, inject=True):
    """[{query, should_trigger}] → harness-eval 시나리오. 발동해야 하면 Skill 호출 필수, 아니면 금지."""
    spec = [{"tool": "Skill", "input_regex": r"(^|\s)(\S+:)?" + re.escape(skill) + r"(\s|$)"}]
    out = []
    for i, q in enumerate(queries, 1):
        want = bool(q.get("should_trigger"))
        out.append({
            "id": _scenario_id(i),
            "rule": f"{skill} {'발동해야 함' if want else '발동하면 안 됨'}",
            "prompts": {LEVEL: q["query"]},
            "expect": {"require_tool": spec} if want else {"forbid_tool": spec},
            "setup": {} if inject else {"remove": [_INJECT_DB]},
        })
    return out


def _triggered(timeline, skill):
    """진짜 스킬 이름과 정확히 같은 Skill 호출이 있었나. `plugin:skill` 꼴도 인정, `skill-xyz` 는 아니다."""
    for e in timeline or []:
        if e.get("tool") != "Skill" or not isinstance(e.get("input"), dict):
            continue
        name = str(e["input"].get("skill") or "")
        if name == skill or name.endswith(":" + skill):
            return True
    return False


def _per_query(skill, queries, results):
    runs = {}
    for r in results:
        runs.setdefault(r["scenario"], []).append(_triggered(r.get("timeline"), skill))
    rows = []
    for i, q in enumerate(queries, 1):
        hits = runs.get(_scenario_id(i), [])
        rows.append({"query": q["query"], "should_trigger": bool(q.get("should_trigger")),
                     "runs": len(hits), "triggered": sum(hits)})
    return rows


def _ratio(num, den):
    return round(num / den, 4) if den else None


def trigger_metrics(skill, queries, results):
    """run 단위 정밀도·재현율, 질의 단위 정확도(발동률 ≥ 50% 로 판정)."""
    rows = _per_query(skill, queries, results)
    tp = sum(r["triggered"] for r in rows if r["should_trigger"])
    fn = sum(r["runs"] - r["triggered"] for r in rows if r["should_trigger"])
    fp = sum(r["triggered"] for r in rows if not r["should_trigger"])
    passed = sum(1 for r in rows if r["runs"] and (r["triggered"] / r["runs"] >= 0.5) == r["should_trigger"])
    return {"skill": skill, "queries": rows, "precision": _ratio(tp, tp + fp), "recall": _ratio(tp, tp + fn),
            "accuracy": _ratio(passed, len(rows)), "passed": passed, "false_triggers": fp}


def _pct(v):
    return "-" if v is None else f"{v:.0%}"


def render_metrics(m, inject=True):
    lines = [f"[스킬 발동] {m['skill']} — 질의 {len(m['queries'])} · 세션 주입 {'켬' if inject else '끔'}",
             f"  정밀도 {_pct(m['precision'])} · 재현율 {_pct(m['recall'])} · 정확도 {_pct(m['accuracy'])}"
             f" ({m['passed']}/{len(m['queries'])} 질의 통과) · 오발동 {m['false_triggers']}회"]
    for r in m["queries"]:
        mark = "발동" if r["should_trigger"] else "비발동"
        lines.append(f"    {mark:4} {r['triggered']}/{r['runs']}  {r['query'][:60]!r}")
    return "\n".join(lines)
