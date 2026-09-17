#!/usr/bin/env python3
"""R-design-cover — 설계 문서의 확정 결정이 계획서에 옮겨졌는지 판정한다.

세 가지를 본다(docs/design-docs/core-beliefs.md#r-design-cover). 결정 ID 의 정본은 원장
docs/hermes-universe/decision-log.md 다 — 접두어 목록도 거기서 읽는다(| D-01 | 꼴 행). 원장에 없는 접두어
(G-·Q- 질문, K-·ZD- 외부 참조)는 결정이 아니므로 검사 대상이 아니다.
  (A) 설계 문서가 인용한 원장 결정 ID 는 어느 계획서(docs/exec-plans/{active,completed}/**)에든 있어야 한다 —
      backlog/ 는 인용으로 치지 않는다(아직 하기로 안 한 것). 없으면
      "계획으로 옮겨지지 않은 확정".
  (B) `(확정)`·`(합의)` 표지가 붙은 절 제목은 원장 결정 ID 를 달아야 한다 — 없으면 (A) 가 볼 수 없다.
  (C) 원장 접두어를 쓰는데 원장에 없는 ID(A-77 같은 오타·미등록)는 틈 — 원장이 정본이다.

산문으로만 적힌 확정 문장(ID 도 표지도 없음)은 이 판정이 못 본다 — 그것이 2026-09-17 SOUL 주입 누락의 꼴이었고,
그래서 (B) 로 "확정이면 ID 를 달라" 를 강제해 앞으로는 (A) 가 보게 한다.

기준선 `.design-cover-baseline` 은 도입 시점에 이미 있던 틈을 잠근다 — 새 틈만 경고하고, 기준선은 줄어들기만 한다.

사용:  design_cover.py check [--root DIR]     새 틈을 한 줄씩 출력. 종료코드 0=새 틈 있음 · 1=없음 · 2=판정 불가
       design_cover.py baseline [--root DIR]  현재 틈 전부를 기준선 형식으로 출력(사람이 파일로 저장)
"""
import os
import re
import sys

DESIGN_DIR = os.path.join("docs", "hermes-universe", "design")
PLAN_DIR = os.path.join("docs", "exec-plans")
LEDGER = os.path.join("docs", "hermes-universe", "decision-log.md")
BASELINE = ".design-cover-baseline"
ID_RE = re.compile(r"\b[A-Z]{1,2}-\d{1,3}\b")
LEDGER_ROW_RE = re.compile(r"^\|\s*([A-Z]{1,2}-\d{1,3})\s*\|", re.M)
CONFIRMED_HEADING_RE = re.compile(r"^#{2,3}\s+(.*?)\s*\((?:확정|합의)[^)]*\)\s*$")


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _walk_md(root, sub):
    base = os.path.join(root, sub)
    for dirpath, _, files in os.walk(base):
        for f in sorted(files):
            if f.endswith(".md"):
                yield os.path.join(dirpath, f)


def ledger_ids(root="."):
    """원장의 결정 ID 전부. 원장이 없으면 None — 그때는 (A)(C) 를 건너뛴다."""
    path = os.path.join(root, LEDGER)
    if not os.path.isfile(path):
        return None
    return set(LEDGER_ROW_RE.findall(_read(path)))


def gaps(root="."):
    """현재 틈 전부. 항목: 'id:<ID>'(A) · 'heading:<파일>:<제목>'(B) · 'id-unknown:<ID>'(C)."""
    design_files = list(_walk_md(root, DESIGN_DIR))
    if not design_files:
        return None
    # backlog/ 는 "아직 하기로 안 한 것" 이라 인용으로 치지 않는다 — 거기 적힌 ID 는 여전히 틈이다.
    plans_text = "\n".join(_read(p) for p in _walk_md(root, PLAN_DIR)
                           if os.sep + "backlog" + os.sep not in p)
    cited = set(ID_RE.findall(plans_text))
    ledger = ledger_ids(root)
    out = []
    for path in design_files:
        text = _read(path)
        out += _id_gaps(text, ledger, cited)
        out += _heading_gaps(text, os.path.relpath(path, root), ledger)
    return sorted(set(out))


def _id_gaps(text: str, ledger, cited: set) -> list:
    """(A)(C). 원장이 없으면 판정하지 않는다. 원장에 없는 접두어(질문·외부 참조)는 결정이 아니다."""
    if ledger is None:
        return []
    prefixes = {i.split("-")[0] for i in ledger}
    out = []
    for did in sorted(set(ID_RE.findall(text))):
        if did.split("-")[0] not in prefixes:
            continue
        if did not in ledger:
            out.append(f"id-unknown:{did}")   # (C)
        elif did not in cited:
            out.append(f"id:{did}")           # (A)
    return out


def _heading_gaps(text: str, rel: str, ledger) -> list:
    """(B) 확정·합의 절 제목에 원장 결정 ID 가 없는 것."""
    return [f"heading:{rel}:{m.group(1).strip()}"
            for m in (CONFIRMED_HEADING_RE.match(line) for line in text.splitlines())
            if m and not _has_ledger_id(m.group(0), ledger)]


def _has_ledger_id(line: str, ledger) -> bool:
    ids = ID_RE.findall(line)
    if ledger is None:
        return bool(ids)
    return any(i in ledger for i in ids)


def baseline(root="."):
    path = os.path.join(root, BASELINE)
    if not os.path.isfile(path):
        return set()
    return {ln.strip() for ln in _read(path).splitlines() if ln.strip() and not ln.startswith("#")}


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "check"
    root = argv[argv.index("--root") + 1] if "--root" in argv else "."
    found = gaps(root)
    if found is None:
        return 2
    if cmd == "baseline":
        print("# R-design-cover 기준선 — 도입 시점(2026-09-17)에 이미 있던 틈. 줄어들기만 한다.")
        print("# id:<ID> = 계획서에 인용되지 않은 결정 ID · heading:<파일>:<제목> = 원장 ID 없는 확정 절 · id-unknown:<ID> = 원장에 없는 결정 ID")
        print("\n".join(found))
        return 0
    new = [g for g in found if g not in baseline(root)]
    print("\n".join(new))
    return 0 if new else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
