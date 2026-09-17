#!/usr/bin/env python3
"""R-design-cover — 설계 문서의 확정 결정이 계획서에 옮겨졌는지 판정한다.

두 가지를 본다(docs/design-docs/core-beliefs.md#r-design-cover):
  (A) 결정 ID(RV-07 · G-14 · V-8 · K-3 · T-1 · C-11)가 설계 문서에 있으면 어느 계획서(docs/exec-plans/**)에든
      같은 ID 가 있어야 한다 — 인용이 없으면 "계획으로 옮겨지지 않은 확정".
  (B) `(확정)`·`(합의)` 표지가 붙은 절 제목은 결정 ID 를 달아야 한다 — ID 가 없으면 (A) 가 볼 수 없다.

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
BASELINE = ".design-cover-baseline"
ID_RE = re.compile(r"\b(?:RV|G|V|K|T|C)-\d{1,3}\b")
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


def gaps(root="."):
    """현재 틈 전부. 각 항목은 'id:<ID>' 또는 'heading:<파일>:<제목>' 한 줄이다."""
    design_files = list(_walk_md(root, DESIGN_DIR))
    if not design_files:
        return None
    plans_text = "\n".join(_read(p) for p in _walk_md(root, PLAN_DIR))
    cited = set(ID_RE.findall(plans_text))
    out = []
    for path in design_files:
        rel = os.path.relpath(path, root)
        text = _read(path)
        for did in sorted(set(ID_RE.findall(text))):
            if did not in cited:
                out.append(f"id:{did}")
        for line in text.splitlines():
            m = CONFIRMED_HEADING_RE.match(line)
            if m and not ID_RE.search(line):
                out.append(f"heading:{rel}:{m.group(1).strip()}")
    return sorted(set(out))


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
        print("# id:<ID> = 계획서에 인용되지 않은 결정 ID · heading:<파일>:<제목> = ID 없는 확정 절")
        print("\n".join(found))
        return 0
    new = [g for g in found if g not in baseline(root)]
    print("\n".join(new))
    return 0 if new else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
