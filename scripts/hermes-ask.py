#!/usr/bin/env python3
"""커밋 때 사람에게 물을 항목을 보이고, 사람이 고른 답을 기록하고, 정답지 결과를 보고한다.

  list    [--session ID] [--json]  물을 항목. 세션당 한 번만 낸다(냈다고 표시). 항목이 없으면 아무것도 내지 않는다.
  answer  <항목 id> <선택>          p:… keep|drop · s:… approve|reject · g:… ok|leak · later(기록 안 함)
  report                            정답지 표본 수 · 놓침 · 95% 상한 · 대기 문장의 사람 판정 · 물음 횟수

이 명령은 모델도 부를 수 있다. 사용자가 폼에서 고른 값만 기록해야 한다(안내 문구에 적혀 있다).
계획: docs/exec-plans/active/2026-09-29-privacy-gate-hardening.md 목표 5~7
"""

import argparse
import json
import os
import sqlite3
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hermes_ask_items as items  # noqa: E402
import hermes_privacy_gold as gold  # noqa: E402
from hermes_privacy_pending import decide, text_hash  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LABEL = {"p": "올리기 전 확인", "s": "성향 승인", "g": "표본 확인"}
CHOICES = {"p": ("keep", "drop"), "s": ("approve", "reject"), "g": ("ok", "leak")}
USAGE = ("위 항목을 질문 폼 하나에 묶어 사용자에게 물어라(질문 4개까지). 선택지: 문장 = 올림(keep)/지움(drop)/나중에 · "
         "성향 = 승인(approve)/거부(reject)/나중에 · 표본 = 올려도 됨(ok)/올리면 안 됨(leak)/나중에.\n"
         "사용자가 폼에서 고른 값만 기록한다(사용자 대신 정하지 않는다): python3 scripts/hermes-ask.py answer <ID> <선택>. "
         "'나중에'는 기록하지 않는다.")


def _connect(project: str):
    return sqlite3.connect(os.path.join(project, ".hermes", "state.db"), timeout=5.0)


def cmd_list(project: str, session: str, as_json: bool) -> int:
    con = _connect(project)
    if session and items.already_asked(con, session):
        return 0
    found = items.collect(con, session or "manual")
    if not found:
        return 0
    if as_json:
        print(json.dumps([{"id": i, "text": t} for i, t in found], ensure_ascii=False))
        return 0
    print(f"[ASK] {len(found)}")
    for item_id, text in found:
        print(f"{item_id}\t{LABEL[item_id[0]]}\t{str(text).strip()[:200]}")
    print("---\n" + USAGE)
    if session:
        items.mark_asked(con, session, len(found))
    return 0


def _run(*args) -> int:
    return subprocess.run([sys.executable, *args], capture_output=True, text=True).returncode


def _answer_gold(con, project: str, key: str, choice: str) -> int:
    cands = items.gold_candidates(con)
    hits = [h for h in cands if h.startswith(key)]
    if len(hits) != 1:
        print(f"표본 {key} 를 찾을 수 없습니다(스테이징이 바뀌었을 수 있습니다).", file=sys.stderr)
        return 1
    gold.record(con, hits[0], choice)
    if choice == "leak":
        decide(con, hits[0], "drop")
        con.commit()
        where = sorted({p for p, t in items.staged_texts() if text_hash(t) == hits[0]})
        print("놓친 문장으로 기록하고 지움(drop) 처리했습니다. 스테이징에서 다음 파일의 그 문장을 빼십시오: " + ", ".join(where))
    con.commit()
    return 0


def cmd_answer(project: str, item_id: str, choice: str) -> int:
    if choice == "later":
        return 0
    kind, _, key = item_id.partition(":")
    if kind not in CHOICES or not key or choice not in CHOICES[kind]:
        print(f"허용되지 않은 항목/선택입니다: {item_id} {choice} (가능: {CHOICES.get(kind)})", file=sys.stderr)
        return 1
    if kind == "p":
        return _run(os.path.join(HERE, "hermes-privacy-review.py"), "--project", project, "decide", key, choice)
    if kind == "s":
        return _run(os.path.join(HERE, "hermes-persona.py"), "approve" if choice == "approve" else "reject", key)
    return _answer_gold(_connect(project), project, key, choice)


def cmd_report(project: str) -> int:
    con = _connect(project)
    st = gold.stats(con)
    items.ensure_marker(con)
    asks, asked = con.execute("SELECT COUNT(*), COALESCE(SUM(n_items), 0) FROM ask_marker").fetchone()
    print(f"정답지: 표본 {st['n']}개 (목표 {gold.TARGET}) · 놓침 {st['leaks']}건", end="")
    print(f" · 95% 상한 {st['upper'] * 100:.1f}%" if st["upper"] is not None else "")
    print("  스테이징된 통과 문장 중 사람이 응답한 표본 기준입니다 — 모집단 전체의 보증이 아닙니다.")
    if st["leaks"]:
        print("  놓침이 있으므로 판정 문구(RULE) 개선 계획을 세우십시오.")
    print(f"대기 문장의 사람 판정: 둠 {st['keep']}건(과탐) · 지움 {st['drop']}건")
    print(f"물음 {asks}회 · 항목 {asked}개 · 남은 대기 문장 {len(items.privacy_items(con))}건 · 남은 성향 대기 {len(items.persona_items())}건")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="커밋 때 묻기")
    ap.add_argument("--project", default=os.getcwd())
    sub = ap.add_subparsers(dest="cmd", required=True)
    ls = sub.add_parser("list")
    ls.add_argument("--session", default="")
    ls.add_argument("--json", action="store_true")
    an = sub.add_parser("answer")
    an.add_argument("item")
    an.add_argument("choice")
    sub.add_parser("report")
    args = ap.parse_args()
    project = os.path.abspath(args.project)
    os.chdir(project)                      # 스테이징 문장을 읽는 git 은 저장소 안에서 부른다
    if not os.path.isfile(os.path.join(project, ".hermes", "state.db")):
        return 0
    if args.cmd == "list":
        return cmd_list(project, args.session, args.json)
    return cmd_answer(project, args.item, args.choice) if args.cmd == "answer" else cmd_report(project)


if __name__ == "__main__":
    sys.exit(main())
