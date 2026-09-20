#!/usr/bin/env python3
"""소우주 한 곳의 DB·파일에서 대시보드 네 판(에이전트·스킬·학습 루프·건강)의 숫자·표 행을 dict 로 모은다 (계획 2026-09-18-hermes-dashboard 목표 1~6).

읽기 전용(mode=ro). 모델 호출 0(R3). 기준을 다시 정의하지 않는다 — 강등 후보는 hermes_skill_yield, 열린 인계는 hermes_handoff_queue,
게이트 발화율은 scripts/hooks/gate_report 를 그대로 부른다. 표가 없는 구버전 DB 는 그 판만 비운다.
공개 함수 2개: collect · collect_universe
"""
import json
import os
import re
import sqlite3
import subprocess
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "hooks"))
import gate_report  # noqa: E402
from hermes_handoff_queue import queue  # noqa: E402
from hermes_owner_memory import open_proposals  # noqa: E402
from hermes_skill_layers import LAYERS  # noqa: E402
from hermes_skill_yield import low_yield_skills  # noqa: E402

DREAM_THROTTLE_HOURS = 20


def _ro(db: str):
    return sqlite3.connect(f"file:{db}?mode=ro", uri=True)


def _has(con, table: str) -> bool:
    return bool(con.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone())


def _roster(project: str) -> list:
    try:
        with open(os.path.join(project, ".hermes", "agents.json"), encoding="utf-8") as fh:
            return json.load(fh).get("agents", [])
    except (OSError, ValueError):
        return []


def _blocked_handoffs(con, seen: set) -> list:
    """되묻기·거절로 보낸 쪽에 되돌아가 아직 안 끝난 봉투 — 대기열(queue)에는 안 보이므로 따로 모은다."""
    rows = con.execute(
        "SELECT a.task_id, a.ts, a.intent, a.decision, r.kind FROM journal_events a "
        "JOIN journal_events r ON r.task_id = a.task_id AND r.kind IN ('handoff.question','handoff.declined') "
        "WHERE a.kind='task.assigned' AND a.task_id NOT IN "
        "(SELECT task_id FROM journal_events WHERE kind IN ('task.finished','handoff.expired')) "
        "ORDER BY a.ts").fetchall()
    out, done = [], set(seen)
    for task_id, ts, goal, dec, how in rows:
        if task_id in done:
            continue
        done.add(task_id)
        m = re.search(r"(?<!return_)\bto=(\S+)", dec or "")
        out.append({"to": m.group(1) if m else "?", "task_id": task_id, "kind": how.split(".")[-1], "goal": goal,
                    "ts": ts, "blocked": True})
    return out


def _open_handoffs(db: str, con, roster: list) -> list:
    """대기열에 있는 봉투(열림) + 되묻기·거절로 되돌아가 아직 안 끝난 봉투(막힘)."""
    if not (os.path.isfile(db) and _has(con, "journal_events")):
        return []
    targets = [f"agent:{a['agent_id']}" for a in roster if a.get("status") != "retired"] + ["human"]
    out = [{"to": t, "blocked": False, **item} for t in targets for item in queue(db, t)]
    return out + _blocked_handoffs(con, {h["task_id"] for h in out})


def _summons_recent(con, names: dict) -> list:
    if not _has(con, "summons"):
        return []
    return [{"agent_id": a, "name": names.get(a, a[:8]), "requested_by": r, "issued_at": i, "used_at": u}
            for a, r, i, u in con.execute(
                "SELECT agent_id, requested_by, issued_at, used_at FROM summons ORDER BY issued_at DESC LIMIT 10")]


def _corrections(con, names: dict) -> list:
    """about 별 corrected 지적 누적 수(agent-teaching 목표 6 이관)."""
    if not _has(con, "memory_events"):
        return []
    return [{"agent_id": a, "name": names.get(a, a[:8]), "about": ab, "count": n} for a, ab, n in con.execute(
        "SELECT agent_id, about, COUNT(*) FROM memory_events WHERE kind='memory.added' "
        "AND source_event LIKE 'review:%:corrected:%' GROUP BY agent_id, about ORDER BY COUNT(*) DESC")]


def _agents_pane(project: str, db: str, con) -> dict:
    roster = _roster(project)
    names = {a.get("agent_id"): a.get("name") for a in roster}
    rows = [{"name": a.get("name"), "status": a.get("status"), "agent_id": a.get("agent_id"),
             **{k: (a.get("org") or {}).get(k) for k in ("discipline", "rank", "unit")}} for a in roster]
    return {"roster": rows, "open_handoffs": _open_handoffs(db, con, roster), "summons_recent": _summons_recent(con, names),
            "owner_proposals": len(open_proposals(project)), "corrections": _corrections(con, names)}


def _by_layer(con) -> dict:
    out = {layer: 0 for layer in LAYERS}
    if not _has(con, "skill_index"):
        return out
    cols = [r[1] for r in con.execute("PRAGMA table_info(skill_index)")]
    col = "COALESCE(layer, 'common')" if "layer" in cols else "'common'"
    for layer, n in con.execute(f"SELECT {col}, COUNT(*) FROM skill_index GROUP BY 1"):
        out[layer if layer in out else "common"] += n
    return out


def _top_injected(con) -> list:
    if not _has(con, "skill_injection"):
        return []
    return [{"skill_path": p, "injected": n, "helpful": h or 0, "rate": (h or 0) / n if n else 0.0}
            for p, n, h in con.execute(
                "SELECT skill_path, COUNT(*), SUM(CASE WHEN correlated THEN 1 ELSE 0 END) "
                "FROM skill_injection GROUP BY skill_path ORDER BY COUNT(*) DESC LIMIT 10")]


def _pending_crystallize(con) -> list:
    if not _has(con, "pattern_count"):
        return []
    return [{"key": k, "count": n} for k, n in con.execute(
        "SELECT pattern_key, count FROM pattern_count WHERE count >= 3 AND crystallized = 0 ORDER BY count DESC")]


def _skills_pane(con) -> dict:
    return {"by_layer": _by_layer(con), "top_injected": _top_injected(con),
            "demote_candidates": low_yield_skills(con), "pending_crystallize": _pending_crystallize(con)}


def _learning_pane(project: str, con) -> dict:
    out = {"summaries": 0, "dream_runs": 0, "last_dream": None, "next_dream_at": None, "evolved": 0, "crystallized": 0}
    if _has(con, "session_summary"):
        out["summaries"] = con.execute("SELECT COUNT(*) FROM session_summary").fetchone()[0]
    if _has(con, "dream_log"):
        out["dream_runs"], out["evolved"], out["crystallized"], out["last_dream"] = con.execute(
            "SELECT COUNT(*), COALESCE(SUM(evolved),0), COALESCE(SUM(crystallized),0), MAX(run_at) FROM dream_log").fetchone()
    marker = os.path.join(project, ".hermes", "dream-last-run")
    if os.path.isfile(marker):
        last = datetime.fromtimestamp(os.path.getmtime(marker), timezone.utc)
        out["next_dream_at"] = (last + timedelta(hours=DREAM_THROTTLE_HOURS)).strftime("%Y-%m-%dT%H:%M:%SZ")
    return out


def _health_pane(project: str) -> dict:
    gates = []
    path = os.path.join(project, ".harness", "gate-events.jsonl")
    if os.path.isfile(path):
        records, _broken = gate_report.load_events(path)
        counts = gate_report.tally(records)
        verdicts = ("pass", "warn", "block", "waived", "skipped")
        rows = [gate_report._row(rule, c, verdicts) for rule, c in counts.items()]
        rows.sort(key=gate_report._rate_key)
        gates = [{"rule": r[0], "chance": int(r[1]), "warn": int(r[3]), "block": int(r[4]), "rate": r[7]} for r in rows[:5]]
    debt = []
    dirty = os.path.join(project, ".claude", ".review-dirty")
    if os.path.isfile(dirty):
        with open(dirty, encoding="utf-8") as fh:
            debt = sorted({line.split("  ", 1)[-1].strip() for line in fh if line.startswith(("edit:", "first:"))})
    active_dir = os.path.join(project, "docs", "exec-plans", "active")
    plans = sorted(f for f in os.listdir(active_dir) if f.endswith(".md")) if os.path.isdir(active_dir) else []
    return {"gates_top": gates, "review_debt": debt, "active_plans": plans}


def collect(project: str) -> dict:
    """네 판 전부. DB 가 없으면 판은 비고 `db_missing` 이 True."""
    project = os.path.abspath(project)
    db = os.path.join(project, ".hermes", "state.db")
    out = {"project": os.path.basename(project), "path": project,
           "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "db_missing": not os.path.isfile(db)}
    con = _ro(db) if os.path.isfile(db) else sqlite3.connect(":memory:")
    try:
        out["agents"] = _agents_pane(project, db, con)
        out["skills"] = _skills_pane(con)
        out["learning"] = _learning_pane(project, con)
    finally:
        con.close()
    out["health"] = _health_pane(project)
    return out


def _factory_head(factory: str) -> str:
    try:
        return subprocess.run(["git", "-C", factory, "rev-parse", "HEAD"], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def _factory_match(path: str, head: str):
    try:
        with open(os.path.join(path, ".hermes", "factory.json"), encoding="utf-8") as fh:
            return json.load(fh).get("installed_version") == head
    except (OSError, ValueError):
        return None


def _universe_row(path: str, head: str) -> dict:
    row = {"project": os.path.basename(path), "path": path, "installed": os.path.isfile(os.path.join(path, ".hermes", "state.db"))}
    if not row["installed"]:
        return row
    d = collect(path)
    inj = d["skills"]["top_injected"]
    total = sum(i["injected"] for i in inj)
    row.update({"agents": sum(1 for a in d["agents"]["roster"] if a["status"] != "retired"),
                "skills": sum(d["skills"]["by_layer"].values()),
                "helpful_rate": (sum(i["helpful"] for i in inj) / total) if total else None,
                "demote_candidates": len(d["skills"]["demote_candidates"]),
                "last_dream": d["learning"]["last_dream"], "factory_match": _factory_match(path, head)})
    return row


def collect_universe(factory: str, registry: str = None) -> list:
    """`.installed-projects` 의 소우주마다 한 행. hermes 미설치(state.db 없음)는 installed=False."""
    registry = registry or os.path.join(factory, ".installed-projects")
    try:
        with open(registry, encoding="utf-8") as fh:
            paths = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
    except OSError:
        paths = []
    head = _factory_head(factory)
    return [_universe_row(p, head) for p in paths]
