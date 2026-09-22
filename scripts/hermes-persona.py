#!/usr/bin/env python3
"""사용자 성향 CLI.

  distill  대화 기록의 사람 발화 → 관찰(global.db). 파일별 워터마크로 증분.

기본 대상은 **현재 프로젝트의 대화 기록만**이다(2026-09-22 사용자 결정: 공장부터 시험).
review · approve · reject · render 는 Step 4 에서 더한다.
근거: docs/exec-plans/active/2026-09-22-user-persona-distill-plan.md
"""

import argparse
import glob
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hermes_persona_store as store  # noqa: E402
from hermes_persona_extract import build_batches, extract_observations  # noqa: E402
from hermes_persona_source import read_new_utterances  # noqa: E402

DEFAULT_DB = os.path.expanduser("~/.hermes/global.db")
DEFAULT_PROJECTS_DIR = os.path.expanduser("~/.claude/projects")


def _project_key(project_dir: str) -> str:
    """Claude Code 가 대화 기록 폴더 이름을 만드는 방식 — `/`·`_`·`.` 이 `-` 가 된다(실측)."""
    return re.sub(r"[/_.]", "-", os.path.abspath(project_dir))


def _transcripts(args) -> list:
    pattern = "*" if args.all_projects else _project_key(args.project)
    return sorted(glob.glob(os.path.join(args.projects_dir, pattern, "*.jsonl")))


def _distill_file(con, path: str) -> tuple:
    """파일 하나 → (새 발화 수, 관찰 수, 실패 여부). 실패한 묶음부터는 워터마크를 멈춘다."""
    utterances, end = read_new_utterances(path, store.get_watermark(con, path))
    utterances = [{**u, "source_path": path} for u in utterances]
    observed = 0
    for batch in build_batches(utterances):
        found = extract_observations(batch, store.list_keys(con))
        if found is None:
            return len(utterances), observed, True
        for obs in found:
            store.add_observation(con, obs)
        observed += len(found)
        store.set_watermark(con, path, batch[-1]["line"])
    store.set_watermark(con, path, end)
    return len(utterances), observed, False


def cmd_distill(args) -> int:
    os.makedirs(os.path.dirname(args.db) or ".", exist_ok=True)
    con = sqlite3.connect(args.db)
    store.ensure_schema(con)
    files = _transcripts(args)
    new = observed = failed = 0
    for path in files:
        n, o, bad = _distill_file(con, path)
        new, observed, failed = new + n, observed + o, failed + bad
    con.close()
    print(f"[persona] 기록 {len(files)}개 · 새 발화 {new} · 관찰 {observed} · 실패 {failed}")
    if failed:
        print(f"[persona] {failed}개 파일은 LLM 호출 실패 — 워터마크를 멈췄다. 다시 돌리면 이어서 읽는다.",
              file=sys.stderr)
    return 1 if failed else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("distill", help="대화 기록에서 성향 관찰을 뽑는다")
    d.add_argument("--db", default=DEFAULT_DB)
    d.add_argument("--projects-dir", default=DEFAULT_PROJECTS_DIR)
    d.add_argument("--project", default=os.getcwd(), help="이 프로젝트의 대화 기록만 (기본: 현재 폴더)")
    d.add_argument("--all-projects", action="store_true", help="모든 프로젝트의 대화 기록")
    args = ap.parse_args(argv)
    return cmd_distill(args)


if __name__ == "__main__":
    sys.exit(main())
