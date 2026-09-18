#!/usr/bin/env python3
"""승격 제안 CLI — 일반화 점검 → 봉투 작성 → (사람이 명령할 때만) gh 배달.

  hermes-propose.py new|improve|exclude <스킬>  [--deliver]
  hermes-propose.py status

흐름(설계 skill-proposal-delivery.md 2절):
  1. 스킬 본문을 읽어 mesh_gate(일반화 자체 점검) + 금지 내용 게이트를 통과해야 봉투를 쓴다.
  2. `.hermes/outbox/<id>/envelope.json` 에 status=pending 으로 남긴다.
  3. 사람이 `--deliver` 를 붙였을 때만 `gh issue create --label proposal` 로 공장에 배달한다(RV-15).
     실패(오프라인·인증·gh 없음)는 오류가 아니라 pending 유지 + 마지막 오류 문구 보존.
배달 주소는 `factory.json.remote_url` 만 쓴다 — 주소 인자를 받지 않는다(RV-16, 목표 9).
계획: docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 7·8·9

공개 함수 2개: gate_body · main
"""

import argparse
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_envelope import list_envelopes, new_envelope, set_status, write_envelope
from hermes_envelope_gate import check_forbidden
from hermes_mesh_gate import verdict
from hermes_skill_extends import parse_extends
from hermes_universe import read_universe_id


def gate_body(project: str, body: str, *, reason: str = "", diff: str = None,
              run_model: bool = True) -> tuple:
    """봉투에 실릴 텍스트를 두 게이트로 검사한다. (ok, gate_results).

    mesh(일반화)는 스킬 본문만 본다. 금지 내용(누출 방지)은 이슈로 나가는 **모든 칸**
    (body·reason·diff)을 합쳐 본다 — reason 은 사람이 자유롭게 적어 이름·티켓이 새기 쉽다.
    """
    mesh = verdict(body) if run_model else {"passed": True, "reason": "skipped",
                                            "scenario_list": False}
    deliverable = "\n".join(p for p in (body, reason, diff) if p)
    fb_ok, fb_reason = check_forbidden(project, deliverable)
    gate_results = {"mesh": mesh, "forbidden": fb_reason}
    ok = mesh["passed"] and not mesh["scenario_list"] and fb_ok
    return ok, gate_results


def _resolve_skill(db: str, name: str) -> dict:
    """skill_index 에서 이름으로 skill_path·skill_id 를 찾는다."""
    import sqlite3
    from hermes_skill_layers import layer_of_path
    if not os.path.isfile(db):
        return {}
    con = sqlite3.connect(db)
    try:
        for path, sid in con.execute("SELECT skill_path, skill_id FROM skill_index"):
            base = os.path.basename(os.path.dirname(path)) if path.endswith("SKILL.md") \
                else os.path.basename(path)[:-3]
            if base == name and os.path.isfile(path):
                return {"path": path, "skill_id": sid}
    finally:
        con.close()
    return {}


def _read_body(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _remote_repo(project: str) -> str:
    """factory.json.remote_url 을 gh -R 용 owner/repo 로. 못 구하면 ''."""
    try:
        with open(os.path.join(project, ".hermes", "factory.json"), encoding="utf-8") as fh:
            url = json.load(fh).get("remote_url") or ""
    except (OSError, ValueError):
        return ""
    m = url.rstrip("/").removesuffix(".git")
    if ":" in m and "/" in m:
        return m.split(":")[-1] if "@" in m else "/".join(m.split("/")[-2:])
    return ""


def _deliver(project: str, env: dict) -> tuple:
    """gh 로 이슈를 연다. (status, error, issue_url). 실패는 pending + 오류 문구."""
    repo = _remote_repo(project)
    if not repo:
        return "pending", "factory.json.remote_url 없음", None
    if not shutil.which("gh"):
        return "pending", "gh 없음(사람이 배달 필요)", None
    title = f"[proposal] {env['kind']} {(env.get('skill_id') or '')[:8]}"
    body = json.dumps({k: env.get(k) for k in
                       ("envelope_id", "kind", "universe_id", "agent_id", "skill_id",
                        "base", "body", "diff", "reason", "gate_results")},
                      ensure_ascii=False, indent=2)
    # 최종 방어선 — 이슈로 나가는 **정확히 그 JSON** 을 통째로 다시 검사한다. 개별 칸 게이트를
    # 우회한 값(미해결 skill_id 폴백·HERMES_AGENT_ID 등)이 여기서 걸린다(누출 방지, 리뷰 지적).
    fb_ok, fb_reason = check_forbidden(project, body)
    if not fb_ok:
        return "pending", f"누출 게이트 거부(배달 안 함): {fb_reason}", None
    try:
        done = subprocess.run(["gh", "issue", "create", "-R", repo, "--label", "proposal",
                               "--title", title, "--body", body],
                              capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as exc:
        return "pending", f"gh 실행 실패: {exc}", None
    if done.returncode != 0:
        return "pending", f"gh 오류: {done.stderr.strip()[:120]}", None
    return "delivered", None, done.stdout.strip() or None


def _make_and_write(args, kind, body, base) -> dict:
    project = args.project
    skill_id = args.skill_id
    env = new_envelope(kind, read_universe_id(project) or "", os.environ.get("HERMES_AGENT_ID", "main"),
                       skill_id, body, args.reason, args.gate_results, base=base)
    write_envelope(project, env)
    return env


def _accepted(kind: str, ok: bool, gate_results: dict) -> bool:
    """게이트 판정. exclude 는 본문이 없어 일반화(mesh)는 건너뛰되, 누출(금지 내용) 검사는
    반드시 통과해야 한다 — reason 이 공개 이슈로 나가기 때문이다."""
    if kind == "exclude":
        return gate_results["forbidden"] == "clean"
    return ok


def _base_of(kind: str, path: str):
    if kind != "improve" or not path:
        return None
    ext = parse_extends(path)
    return f"{ext[0]}@{ext[1]}" if ext else None


def _propose_template(args) -> int:
    """에이전트 복제 제안(H-09): SOUL 본문 + 개인 스킬을 kind=template 봉투로. 기억·이력은 넣지 않는다.
    누출·국한성 게이트는 new 와 같다 — 소우주 사실이 SOUL 에 남아 있으면 여기서 막힌다(설계 의도)."""
    from hermes_agent_export import export_agent
    try:
        exported = export_agent(args.project, args.skill)
    except KeyError as exc:
        print(f"[hermes-propose] {exc}", file=sys.stderr)
        return 2
    ok, gate_results = gate_body(args.project, exported["body"], reason=args.reason,
                                 run_model=not args.no_model)
    if not ok:
        print(f"[hermes-propose] 거부: {gate_results}", file=sys.stderr)
        return 3
    args.skill_id = None
    args.gate_results = gate_results
    os.environ["HERMES_AGENT_ID"] = exported["agent_id"]      # 봉투 agent_id = 복제 원본의 기계 id
    env = _make_and_write(args, "template", exported["body"], None)
    print(f"봉투 작성: {env['envelope_id']} status={env['status']} kind=template (기억·이력 제외)")
    if args.deliver:
        status, err, url = _deliver(args.project, env)
        print(f"배달: {status}{' — ' + err if err else ''}{' ' + url if url else ''}")
    else:
        print("배달 안 함(사람이 --deliver 를 붙여야 gh 로 나간다)")
    return 0


def _propose(args, kind: str) -> int:
    project = args.project
    resolved = _resolve_skill(os.path.join(project, ".hermes", "state.db"), args.skill)
    body = _read_body(resolved["path"]) if resolved.get("path") else ""
    base = _base_of(kind, resolved.get("path"))
    ok, gate_results = gate_body(project, body, reason=args.reason,
                                 run_model=not args.no_model)
    if not _accepted(kind, ok, gate_results):
        print(f"[hermes-propose] 게이트 거부 — 배달 불가: {gate_results}", file=sys.stderr)
        return 3
    args.skill_id = resolved.get("skill_id") or args.skill
    args.gate_results = gate_results
    env = _make_and_write(args, kind, body if kind != "exclude" else "", base)
    print(f"봉투 작성: {env['envelope_id']} status={env['status']} kind={kind}")
    if args.deliver:
        status, error, issue_url = _deliver(project, env)
        set_status(project, env["envelope_id"], status, error, issue_url)
        print(f"배달: status={status}{' — ' + error if error else ''}")
    else:
        print("배달 안 함(사람이 --deliver 를 붙여야 gh 로 나간다)")
    return 0


def _status(args) -> int:
    for env in list_envelopes(args.project):
        err = f" ({env.get('error')})" if env.get("error") else ""
        print(f"{env['status']:<10} {env['kind']:<8} {env['envelope_id']} {(env.get('skill_id') or '')[:8]}{err}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="헤르메스 승격 제안")
    ap.add_argument("--project", default=os.getcwd())
    ap.add_argument("--remote", help=argparse.SUPPRESS)   # 받되 거부(RV-16, 목표 9)
    ap.add_argument("--deliver", action="store_true", help="사람 명령 — gh 로 배달")
    ap.add_argument("--reason", default="", help="제안 이유(우주 심사 근거)")
    ap.add_argument("--no-model", action="store_true", help="mesh_gate stage2(claude) 건너뜀")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for k in ("new", "improve", "exclude"):
        sub.add_parser(k).add_argument("skill")
    sub.add_parser("template", help="에이전트 복제 제안 — SOUL+개인 스킬을 우주 템플릿 후보로(H-09)").add_argument("skill", metavar="agent")
    sub.add_parser("status")
    args = ap.parse_args()
    if args.remote:
        print("[hermes-propose] 배달 주소는 factory.json.remote_url 만 쓴다 — --remote 금지(RV-16)",
              file=sys.stderr)
        return 2
    if args.cmd == "status":
        return _status(args)
    if args.cmd == "template":
        return _propose_template(args)
    return _propose(args, args.cmd)


if __name__ == "__main__":
    raise SystemExit(main())
