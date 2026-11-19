#!/usr/bin/env python3
"""결정화 판정 장부 — `.hermes/enforce-verdicts.jsonl` 에 한 줄씩 남기고, 검사 후보를 모아 보인다.

왜 스킬 파일 밖에 두나: `hermes-evolve-skill.py` 가 모델로 스킬 파일 전체를 다시 써서, 본문 안 표식은 조용히 사라진다.
되돌리기: 장부 줄을 지우고 `UPDATE pattern_count SET crystallized=0 WHERE pattern_key=?` → 다음 결정화에서 다시 판정.
계획: docs/exec-plans/active/2026-11-19-crystallize-check-first-plan.md

공개: append · read · main (`list --hermes-dir <.hermes>`)
"""

import argparse
import json
import os
import sys
from datetime import datetime

LEDGER_NAME = "enforce-verdicts.jsonl"


def _path(hermes_dir: str) -> str:
    return os.path.join(hermes_dir, LEDGER_NAME)


def append(hermes_dir: str, key: str, verdict: str, detail: str = "", note: str = "", skill_file: str = ""):
    """판정 한 줄을 덧붙인다(쓴 줄, 실패면 None). covered 면 detail 이 게이트 이름, checkable 이면 종류(hook·gate·test)."""
    row = {"date": datetime.now().strftime("%Y-%m-%d"), "key": key, "verdict": verdict}
    if verdict == "covered":
        row["gate"] = detail
    elif verdict == "checkable":
        row["kind"] = detail
    if note:
        row["note"] = note
    if skill_file:
        row["skill_file"] = skill_file
    # 장부는 부가 기록이다 — 쓰기 실패(디스크·권한)가 결정화 루프를 끊지 않게 남기고 넘어간다.
    try:
        os.makedirs(hermes_dir or ".", exist_ok=True)
        with open(_path(hermes_dir), "a", encoding="utf-8") as fh:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")
    except OSError as e:
        print(f"[enforce-ledger] 장부 쓰기 실패({key}): {e}", file=sys.stderr)
        return None
    return row


def read(hermes_dir: str) -> list:
    """장부 전체. 깨진 줄은 건너뛰고 stderr 에 남긴다. 장부가 없으면 빈 목록."""
    rows = []
    try:
        with open(_path(hermes_dir), encoding="utf-8") as fh:
            lines = fh.readlines()
    except FileNotFoundError:
        return rows
    for n, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            print(f"[enforce-ledger] {LEDGER_NAME}:{n} 깨진 줄 건너뜀", file=sys.stderr)
    return rows


def _latest(rows: list) -> list:
    """키마다 마지막 판정만 남긴다(되돌린 뒤 다시 판정한 키)."""
    return list({r.get("key"): r for r in rows}.values())


def main() -> None:
    parser = argparse.ArgumentParser(description="결정화 판정 장부")
    parser.add_argument("action", choices=["list"], help="list: 검사로 옮길 후보(checkable)를 보인다")
    parser.add_argument("--hermes-dir", default=".hermes", help=".hermes 폴더 경로")
    parser.add_argument("--all", action="store_true", help="checkable 뿐 아니라 모든 판정")
    args = parser.parse_args()
    for r in _latest(read(args.hermes_dir)):
        if not args.all and r.get("verdict") != "checkable":
            continue
        what = r.get("kind") or r.get("gate") or r.get("note") or "-"
        print(f"{r.get('date', '')}  {r.get('verdict')}:{what}  {r.get('key')}  {r.get('skill_file', '')}")


if __name__ == "__main__":
    main()
