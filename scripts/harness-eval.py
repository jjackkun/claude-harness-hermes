#!/usr/bin/env python3
"""하네스 행동 회귀 평가 러너 (계획 2026-09-20-agent-eval-regression 목표 3·4).

  python3 scripts/harness-eval.py [--dry-run] [--only id,id] [--strictness supportive,neutral,competing]
                                  [--k 3] [--workers 3] [--model claude-haiku-4-5-20251001] [--timeout 120]

로컬·수동·구독 CLI 경로만(설계 agent-eval-llm-path.md). CI 환경변수가 있으면 거부. 세션 안에서는 summon-guard(RV-06)가 막으므로
사람이 터미널에서 돌린다. 시나리오는 tests/agent-evals/*.json, 픽스처는 project-claude.sh 로 한 번 설치해 복제한다.
결과: 표 + .harness/evals/<stamp>.json. 공개 심볼: load_scenarios · run_one · main
"""
import argparse
import concurrent.futures
import fcntl
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness_eval_grade import attempt_drift, file_shas, grade, summarize  # noqa: E402
from harness_eval_trigger import LEVEL, render_metrics, to_scenarios, trigger_metrics  # noqa: E402

_FACTORY = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_SCEN_DIR = os.path.join(_FACTORY, "tests", "agent-evals")
STRICTNESS = ("supportive", "neutral", "competing")
_TOOLS = "Bash,Edit,Write,Read,Grep,Glob,Skill,AskUserQuestion"
_CLAUDE_JSON = os.environ.get("HARNESS_EVAL_CLAUDE_JSON") or os.path.expanduser("~/.claude.json")
_QUIET_ENV = {"HERMES_DREAM_ON_SESSION_START": "0", "HERMES_DASHBOARD_ON_SESSION_START": "0",
              "HARNESS_SYNC_AUTOENABLE": "0", "HARNESS_TOOL_INSTALL": "0", "HERMES_NO_REGISTER": "1"}


def load_scenarios(only=None, scen_dir=_SCEN_DIR):
    out = []
    for f in sorted(os.listdir(scen_dir)):
        if not f.endswith(".json"):
            continue
        with open(os.path.join(scen_dir, f), encoding="utf-8") as fh:
            s = json.load(fh)
        if only and s["id"] not in only:
            continue
        out.append(s)
    return out


def _build_template(work):
    """픽스처 프로젝트 한 벌 — project-claude.sh 로 harness hermes 설치 + 첫 커밋. 실패하면 RuntimeError."""
    tpl = os.path.join(work, "template")
    os.makedirs(tpl)
    subprocess.run(["git", "-C", tpl, "init", "-q"], check=True)
    subprocess.run(["git", "-C", tpl, "config", "user.email", "eval@local"], check=True)
    subprocess.run(["git", "-C", tpl, "config", "user.name", "eval"], check=True)
    env = dict(os.environ, **_QUIET_ENV, HOME=os.path.join(work, "home"))
    os.makedirs(env["HOME"], exist_ok=True)
    done = subprocess.run(["bash", os.path.join(_FACTORY, "project-claude.sh"), tpl, "harness", "hermes"],
                          capture_output=True, text=True, env=env)
    if done.returncode != 0:
        raise RuntimeError("픽스처 설치 실패:\n" + done.stdout[-1500:] + done.stderr[-500:])
    with open(os.path.join(tpl, "README.md"), "w", encoding="utf-8") as fh:
        fh.write("# eval fixture\n")
    subprocess.run(["git", "-C", tpl, "add", "-A"], check=True)
    first = subprocess.run(["git", "-C", tpl, "commit", "-qm", "fixture"], capture_output=True, text=True)
    if first.returncode != 0:
        # 설치 직후 첫 커밋이 게이트에 막히면 소우주도 막힌다는 뜻이다 — 이유를 그대로 보인다(2026-09-20: P9 가 역할 템플릿을 막던 사고를 이 자리에서 찾았다)
        raise RuntimeError("픽스처 첫 커밋이 게이트에 막힘 — 소우주에서도 같은 일이 난다:\n" + (first.stdout + first.stderr)[-2000:])
    return tpl


def _is_fixture_path(p):
    """우리가 만든 임시 픽스처 경로만 — 사용자의 실제 프로젝트 항목은 절대 지우지 않는다."""
    return os.path.basename(os.path.dirname(p)).startswith("harness-eval.") and p.startswith(tempfile.gettempdir())


def _trust(paths, add):
    """픽스처 경로를 ~/.claude.json projects 에 신뢰(hasTrustDialogAccepted)로 넣고, 끝나면 넣은 것만 뺀다.
    신뢰가 없으면 claude -p 가 픽스처의 .claude/settings.json(훅·권한)을 거부한다(2026-09-20 실측: 36판 전부 rc 1).
    잠금 + 직전 재읽기로 창을 좁힌다. 다른 키는 건드리지 않는다. 파일이 없거나 깨졌으면 아무것도 하지 않는다."""
    if not os.path.isfile(_CLAUDE_JSON):
        return
    with open(_CLAUDE_JSON, "r+", encoding="utf-8") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        try:
            data = json.load(fh)
        except ValueError:
            return
        projects = data.setdefault("projects", {})
        for p in paths:
            if add and p not in projects:
                projects[p] = {"hasTrustDialogAccepted": True, "allowedTools": []}
            elif not add and _is_fixture_path(p):
                projects.pop(p, None)      # 실행 중 Claude 가 항목에 키를 덧붙인다 — 키 모양으로 거르면 남는다(2026-09-20 실측: 36개 잔류)
        fh.seek(0); fh.truncate()
        json.dump(data, fh, ensure_ascii=False, indent=2)


def _prepare(tpl, dest, scenario):
    shutil.copytree(tpl, dest, symlinks=True)
    for rel, body in (scenario.get("setup") or {}).get("files", {}).items():
        full = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(body)
    for rel in (scenario.get("setup") or {}).get("remove", []):   # 발동 평가의 주입 끔 — 실행 사본에서만 치운다
        full = os.path.join(dest, rel)
        if os.path.lexists(full):
            os.remove(full)
    subprocess.run(["git", "-C", dest, "add", "-A"], check=True)   # 커밋하지 않는다 — 픽스처 게이트를 우회하지 않고, 커밋은 시나리오의 몫이다


def _on_assistant(c, timeline, texts, by_id):
    if c.get("type") == "tool_use":
        entry = {"tool": c.get("name", ""), "input": c.get("input") or {}, "blocked": False, "errored": False, "result": ""}
        timeline.append(entry)
        by_id[c.get("id")] = entry
    elif c.get("type") == "text":
        texts.append(c.get("text", ""))


def _on_tool_result(c, by_id):
    entry = by_id.get(c.get("tool_use_id")) if isinstance(c, dict) else None
    if c.get("type") != "tool_result" or entry is None:
        return
    body = c.get("content")
    body = " ".join(x.get("text", "") for x in body if isinstance(x, dict)) if isinstance(body, list) else str(body or "")
    entry["result"] = body
    entry["blocked"] = bool(c.get("is_error")) and "BLOCK" in body.upper()
    entry["errored"] = bool(c.get("is_error")) and not entry["blocked"]    # 훅 이전에 도구 자체가 실패(예: 읽기 전 Edit) — 효과가 없었다


def _parse_stream(out):
    """stream-json → (타임라인, 최종 텍스트). tool_use 는 assistant 메시지에서, 차단은 tool_result(is_error + BLOCK) 에서."""
    timeline, texts, by_id = [], [], {}
    for line in out.splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if isinstance(ev, dict):     # 줄이 JSON 문자열·숫자일 수 있다(2026-09-20 실측 두 번째 크래시)
            _dispatch(ev, timeline, texts, by_id)
    return timeline, "\n".join(texts)


def _dispatch(ev, timeline, texts, by_id):
    kind = ev.get("type")
    if kind == "result" and ev.get("result"):
        texts.append(str(ev["result"]))
        return
    handler = _on_assistant if kind == "assistant" else (_on_tool_result if kind == "user" else None)
    msg = ev.get("message")
    content = msg.get("content") if isinstance(msg, dict) else []     # system/error 이벤트는 message 가 문자열이다(2026-09-20 실측)
    for c in (content if isinstance(content, list) else []):
        if handler and isinstance(c, dict):
            handler(c, timeline, texts, by_id) if kind == "assistant" else handler(c, by_id)


def _read_files(root, specs):
    out = {}
    for m in specs:
        try:
            with open(os.path.join(root, m["path"]), encoding="utf-8") as fh:
                out[m["path"]] = fh.read()
        except (OSError, KeyError):
            out[m.get("path")] = ""
    return out


def _invoke(cmd, env, cwd, timeout):
    """claude -p 한 번. (stdout, stderr, rc). 실행 예외는 rc 127."""
    try:
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env, cwd=cwd, stdin=subprocess.DEVNULL)
        return done.stdout, done.stderr, done.returncode
    except (OSError, subprocess.SubprocessError) as exc:
        return "", str(exc), 127


def _safe_parse(out, err, rc):
    try:
        timeline, text = _parse_stream(out)
        return timeline, text, err, rc
    except Exception as exc:  # noqa: BLE001 — 한 판의 파싱 실패가 36판 전체를 죽이면 안 된다
        return [], "", f"{err}\n[parse] {exc!r}", rc or 1


def run_one(tpl, work, scenario, strictness, idx, model, timeout):
    """시나리오 한 판: 픽스처 복제 → claude -p → 채점. 반환 {scenario, strictness, run, pass, attempted, blocked, violations, timeline}."""
    dest = os.path.join(work, f"{scenario['id']}-{strictness}-{idx}")
    _prepare(tpl, dest, scenario)
    watched = (scenario.get("expect") or {}).get("unchanged_files") or []
    before = file_shas(dest, watched)
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}   # HOME 은 그대로 — 구독 인증이 거기 있다
    env.update(_QUIET_ENV)
    cmd = [os.environ.get("HERMES_CLAUDE_BIN", "claude"), "-p", scenario["prompts"][strictness], "--output-format", "stream-json",
           "--verbose", "--model", model, "--allowedTools", _TOOLS, "--permission-mode", "acceptEdits"]
    timeline, text, err, rc = _safe_parse(*_invoke(cmd, env, dest, timeout))
    expect = scenario.get("expect") or {}
    g = grade(timeline, text, before, file_shas(dest, watched), expect, _read_files(dest, expect.get("must_contain_files") or []))
    if rc != 0 and not timeline:
        # 실행 자체가 실패한 판은 "시도 없음 = 통과" 로 세지 않는다 — 2026-09-20 첫 실측이 36판 전부 rc 1·타임라인 0 인데 15/18 통과로 나왔다
        g["pass"] = False
        g["violations"].append(f"실행 실패 rc={rc}: {err.strip()[-200:]}")
        print(f"[harness-eval WARN] {scenario['id']}/{strictness}#{idx} rc={rc}: {err.strip()[-300:]}", file=sys.stderr)
    g.update({"scenario": scenario["id"], "strictness": strictness, "run": idx, "exit_code": rc, "stderr_tail": err.strip()[-500:], "text_tail": text.strip()[-600:],
              "timeline": [{"tool": e["tool"], "input": e["input"], "blocked": e["blocked"], "errored": e.get("errored", False),
                            "result_tail": str(e.get("result") or "")[-160:]} for e in timeline]})
    return g


def _aggregate(results):
    groups = {}
    for r in results:
        groups.setdefault((r["scenario"], r["strictness"]), []).append(r)
    return {f"{s}/{st}": summarize(rs) for (s, st), rs in sorted(groups.items())}


def _render(agg):
    lines = [f"{'시나리오/단계':34} {'pass@k':>6} {'pass^k':>6} {'시도율':>6} {'훅값':>6} {'발화후위반':>9}"]
    for key, m in agg.items():
        hv = "-" if m["hook_value"] is None else f"{m['hook_value']:.0%}"
        lines.append(f"{key:34} {str(m['pass_at_k']):>6} {str(m['pass_pow_k']):>6} {m['attempt_rate']:>6.0%} {hv:>6} {m['fired_but_violated']:>9}")
    total = len(agg)
    lines.append(f"합계: pass@k {sum(1 for m in agg.values() if m['pass_at_k'])}/{total} · pass^k {sum(1 for m in agg.values() if m['pass_pow_k'])}/{total}"
                 f" · 발화 후 위반 {sum(m['fired_but_violated'] for m in agg.values())}")
    return "\n".join(lines)


def _dry_run(scenarios, levels, k):
    print(f"[harness-eval dry-run] 시나리오 {len(scenarios)} × 단계 {len(levels)} × k={k} = 호출 {len(scenarios) * len(levels) * k}회 (지금은 0회)")
    for s in scenarios:
        print(f"- {s['id']} ({s.get('rule', '?')})")
        for st in levels:
            print(f"    {st:10} {s['prompts'][st][:90]!r}")
    return 0


def _parse_args(argv):
    ap = argparse.ArgumentParser(description="하네스 행동 회귀 평가")
    ap.add_argument("--dry-run", action="store_true"); ap.add_argument("--only", default="")
    ap.add_argument("--strictness", default=",".join(STRICTNESS)); ap.add_argument("--k", type=int, default=3)
    ap.add_argument("--workers", type=int, default=3); ap.add_argument("--model", default="claude-haiku-4-5-20251001")
    ap.add_argument("--timeout", type=int, default=120); ap.add_argument("--scen-dir", default=_SCEN_DIR)
    ap.add_argument("--out-dir", default=os.path.join(_FACTORY, ".harness", "evals"))
    ap.add_argument("--trigger", default="", help="스킬 발동 평가 — assets/skills/<스킬>/evals/trigger-eval.json 을 픽스처 안에서 돌린다")
    ap.add_argument("--no-inject", action="store_true", help="발동 평가에서 세션 훅의 스킬 주입을 끈다(실행 사본의 .hermes/state.db 제거)")
    a = ap.parse_args(argv)
    if a.trigger:   # 행동 평가와 결과 폴더를 나눈다 — 섞이면 시도율 상승 비교의 "직전" 이 발동 평가가 돼 조용히 꺼진다
        a.out_dir = os.path.join(a.out_dir, f"trigger-{a.trigger}" + ("-noinject" if a.no_inject else ""))
    return a


def _trigger_queries(skill):
    with open(os.path.join(_FACTORY, "assets", "skills", skill, "evals", "trigger-eval.json"), encoding="utf-8") as fh:
        return json.load(fh)


def _load(a):
    """(시나리오, 단계) — 발동 평가면 질의를 시나리오로 바꾸고 한 단계만, 아니면 tests/agent-evals."""
    if a.trigger:
        return to_scenarios(a.trigger, _trigger_queries(a.trigger), inject=not a.no_inject), [LEVEL]
    only = {x.strip() for x in a.only.split(",") if x.strip()} or None
    return load_scenarios(only, a.scen_dir), [x for x in a.strictness.split(",") if x in STRICTNESS]


def _report(a, prev, results):
    """표·결과 저장. 발동 평가는 측정이라 rc 0, 행동 평가는 pass@k 전부여야 rc 0."""
    agg = _aggregate(results)
    if a.trigger:
        print(render_metrics(trigger_metrics(a.trigger, _trigger_queries(a.trigger), results), inject=not a.no_inject))
        print(f"결과: {os.path.relpath(_save(a, agg, results), _FACTORY)}")
        return 0
    _print_drift(prev, agg)
    print(_render(agg))
    print(f"결과: {os.path.relpath(_save(a, agg, results), _FACTORY)}")
    return 0 if all(m["pass_at_k"] for m in agg.values()) else 1


def _execute(scenarios, levels, a):
    work = tempfile.mkdtemp(prefix="harness-eval.")
    try:
        tpl = _build_template(work)
        jobs = [(s, st, i) for s in scenarios for st in levels for i in range(a.k)]
        dests = [os.path.join(work, f"{s['id']}-{st}-{i}") for s, st, i in jobs]
        print(f"[harness-eval] {len(jobs)}회 실행 (모델 {a.model}, 작업자 {a.workers})", file=sys.stderr)
        _trust(dests, add=True)
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as ex:
                return list(ex.map(lambda j: run_one(tpl, work, j[0], j[1], j[2], a.model, a.timeout), jobs))
        finally:
            _trust(dests, add=False)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def _previous_aggregate(out_dir):
    """out_dir 의 가장 최근 결과 파일의 집계. 없거나 깨졌으면 {} — 비교할 직전이 없다는 뜻이다."""
    try:
        paths = sorted(f for f in os.listdir(out_dir) if f.endswith(".json"))
    except OSError:
        return {}
    if not paths:
        return {}
    try:
        with open(os.path.join(out_dir, paths[-1]), encoding="utf-8") as fh:
            return json.load(fh).get("aggregate") or {}
    except (OSError, ValueError):
        return {}


def _render_drift(drift):
    if not drift:
        return ""
    lines = ["⚠ 시도율 상승 — 직전 실행보다 금지 행동을 **시도한** 비율이 올랐다(pass@k 에는 안 보인다):"]
    lines += [f"   {key:34} {before:.0%} → {now:.0%}" for key, before, now in drift]
    return "\n".join(lines)


def _print_drift(prev, agg):
    drift = _render_drift(attempt_drift(prev, agg))
    if drift:
        print(drift)


def _save(a, agg, results):
    os.makedirs(a.out_dir, exist_ok=True)
    path = os.path.join(a.out_dir, time.strftime("%Y-%m-%d_%H%M%S") + ".json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"model": a.model, "k": a.k, "aggregate": agg, "results": results}, fh, ensure_ascii=False, indent=1)
    return path


def main(argv=None):
    a = _parse_args(argv)
    if os.environ.get("CI"):
        print("[harness-eval] CI 에서는 돌리지 않는다(설계 agent-eval-llm-path.md 결정 2) — 로컬·수동만", file=sys.stderr)
        return 2
    scenarios, levels = _load(a)
    if not scenarios:
        print("[harness-eval] 시나리오 없음", file=sys.stderr)
        return 2
    if a.dry_run:
        return _dry_run(scenarios, levels, a.k)
    prev = _previous_aggregate(a.out_dir)   # 저장 전에 읽는다 — 이번 결과가 "직전" 이 되면 안 된다
    return _report(a, prev, _execute(scenarios, levels, a))


if __name__ == "__main__":
    sys.exit(main())
