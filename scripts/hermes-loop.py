#!/usr/bin/env python3
"""헤르메스 루프 CLI — init / run / resume / step / status / stop.

드라이버 while-루프를 소유한다. 완료판정·안전캡은 이 결정적 코드가 쥐고,
창의적 판단·VERIFY 제안은 에이전트(claude -p)가 맡는다 (설계 §6).
run/resume 은 --dangerously-skip-permissions 를 절대 사용하지 않는다 (G9).

사용법:
  hermes-loop.py [--project-dir PATH] init --goal "..." [--title T]
                 [--condition C ...] [--verify CMD] [--max-iter N]
  hermes-loop.py run <loop-id> [--claude-cmd claude] [--iter-timeout SEC]
  hermes-loop.py resume <loop-id>
  hermes-loop.py step <loop-id> --action "..." --verdict V [--signal S]
  hermes-loop.py status [<loop-id>]
  hermes-loop.py stop <loop-id>
"""

import argparse
import os
import subprocess
import sys

import hermes_loop as core
from hermes_loop_prompt import build_iteration_prompt, parse_report


def _db_path(project_dir):
    db = os.path.join(project_dir, ".hermes", "state.db")
    if not os.path.isfile(db):
        print(f"[hermes-loop] DB 없음: {db} (hermes-init.py 먼저 실행)",
              file=sys.stderr)
        sys.exit(1)
    return db


def _decide(verdict, signal):
    """LLM 판정 × 객관신호 교차검증 — goal-met + fail 은 continue 강등 (G3)."""
    if verdict == "goal-met" and signal == "fail":
        return "continue"
    return verdict


def _finish(db, loop_id, status, reason):
    core.finish_loop(db, loop_id, status, reason)
    core.archive_loop(db, loop_id)
    print(f"DECISION:stop:{reason}")


def _require_running(db, loop_id):
    loop = core.get_loop(db, loop_id)
    if not loop:
        print(f"[hermes-loop] 루프 없음: {loop_id}", file=sys.stderr)
        sys.exit(1)
    if loop["status"] != "running":
        print(f"[hermes-loop] 이미 종료된 루프: status={loop['status']}"
              f" reason={loop['finish_reason']}", file=sys.stderr)
        sys.exit(1)
    return loop


# ── init ─────────────────────────────────────────────────────────────────────

def cmd_init(args):
    db = _db_path(args.project_dir)
    loop_id, path = core.create_loop(
        db, args.project_dir, args.goal, title=args.title,
        conditions=args.condition, verify_cmd=args.verify,
        max_iterations=args.max_iter,
        no_progress_limit=args.no_progress_limit)
    print(f"LOOP_ID:{loop_id}")
    print(f"GOAL_MD:{path}")


# ── run / resume (드라이버) — Task 4 에서 구현 ───────────────────────────────

def _drive(args):
    raise NotImplementedError("Task 4 에서 구현")


# ── step (대화형 스킬용 — 공용 판정 코어 노출) ───────────────────────────────

def cmd_step(args):
    db = _db_path(args.project_dir)
    loop = _require_running(db, args.loop_id)
    cap = core.check_caps(loop)              # 안전캡 선행 체크 (G5·G6)
    if cap:
        _finish(db, args.loop_id, "stopped", cap)
        return
    iteration = loop["iterations_used"] + 1
    verdict = _decide(args.verdict, args.signal)
    # 대화형은 드라이버 스냅숏이 없으므로 객관신호 통과를 진전으로 간주
    progressed = bool(args.progressed) if args.progressed is not None \
        else args.signal == "pass"
    core.record_iteration(db, args.loop_id, iteration,
                          args.action, verdict, args.signal, progressed)
    core.append_progress_log(loop["goal_md_path"], iteration,
                             args.action, args.signal, verdict)
    if verdict == "goal-met":
        _finish(db, args.loop_id, "done", "goal-met")
    elif verdict == "blocked":
        _finish(db, args.loop_id, "stopped", "blocked")
    else:
        print("DECISION:continue")


# ── status / stop ────────────────────────────────────────────────────────────

def cmd_status(args):
    db = _db_path(args.project_dir)
    if args.loop_id:
        loop = core.get_loop(db, args.loop_id)
        if not loop:
            print(f"[hermes-loop] 루프 없음: {args.loop_id}", file=sys.stderr)
            sys.exit(1)
        print(f"[{loop['id']}] {loop['title']}")
        print(f"  status={loop['status']}"
              f" reason={loop['finish_reason'] or '-'}"
              f" iter={loop['iterations_used']}/{loop['max_iterations']}"
              f" no_progress={loop['no_progress_count']}"
              f"/{loop['no_progress_limit']}")
        print(f"  GOAL.md: {loop['goal_md_path']}")
        con = core.connect_db(db)
        rows = con.execute(
            "SELECT iteration, verdict, objective_signal, progressed,"
            " action_summary FROM loop_steps WHERE loop_id=?"
            " ORDER BY iteration", (args.loop_id,)).fetchall()
        con.close()
        for it, v, sig, prog, act in rows:
            mark = "●" if prog else "○"
            print(f"  {mark} iter {it}: {v} · signal:{sig} · {(act or '')[:60]}")
    else:
        loops = core.list_loops(db)
        if not loops:
            print("[hermes-loop] 루프 없음")
            return
        for lp in loops:
            print(f"[{lp['id']}] {lp['status']:8s}"
                  f" iter={lp['iterations_used']}/{lp['max_iterations']}"
                  f" reason={(lp['finish_reason'] or '-'):12s} {lp['title']}")


def cmd_stop(args):
    db = _db_path(args.project_dir)
    _require_running(db, args.loop_id)
    _finish(db, args.loop_id, "stopped", "user-stop")


def main():
    parser = argparse.ArgumentParser(
        description="헤르메스 목표 기반 자율 루프 CLI")
    parser.add_argument("--project-dir", default=os.getcwd(),
                        help="프로젝트 경로 (기본: 현재 디렉토리)")
    sub = parser.add_subparsers(dest="cmd")

    p = sub.add_parser("init", help="목표 정의 → GOAL.md + loops 행 생성")
    p.add_argument("--goal", required=True, help="목표 서술")
    p.add_argument("--title", help="제목 (기본: 목표 첫 줄 60자)")
    p.add_argument("--condition", action="append", default=[],
                   help="완료 조건 (반복 지정 가능)")
    p.add_argument("--verify", help="객관 검증 명령 (goal-met 최종 게이트)")
    p.add_argument("--max-iter", type=int, dest="max_iter",
                   help="최대 반복 (기본: max(조건수×3, 5))")
    p.add_argument("--no-progress-limit", type=int,
                   default=core.NO_PROGRESS_LIMIT, help="무진전 한도 (기본 3)")

    for name, help_text in (("run", "헤드리스 드라이버 실행"),
                            ("resume", "중단된 루프 재개 (G8)")):
        p = sub.add_parser(name, help=help_text)
        p.add_argument("loop_id")
        p.add_argument("--claude-cmd", default="claude")
        p.add_argument("--iter-timeout", type=int, default=0,
                       help="반복당 claude 실행 제한초 (0=무제한)")

    p = sub.add_parser("step", help="대화형 반복 1회 기록 + 판정")
    p.add_argument("loop_id")
    p.add_argument("--action", required=True)
    p.add_argument("--verdict", required=True, choices=core.VERDICTS)
    p.add_argument("--signal", default="none", choices=core.SIGNALS)
    p.add_argument("--progressed", type=int, choices=(0, 1), default=None)

    p = sub.add_parser("status", help="루프 현황")
    p.add_argument("loop_id", nargs="?")

    p = sub.add_parser("stop", help="사용자 강제 중단 (finish_reason=user-stop)")
    p.add_argument("loop_id")

    args = parser.parse_args()
    args.project_dir = os.path.abspath(args.project_dir)

    if args.cmd == "init":
        cmd_init(args)
    elif args.cmd in ("run", "resume"):
        _drive(args)
    elif args.cmd == "step":
        cmd_step(args)
    elif args.cmd == "status":
        cmd_status(args)
    elif args.cmd == "stop":
        cmd_stop(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
