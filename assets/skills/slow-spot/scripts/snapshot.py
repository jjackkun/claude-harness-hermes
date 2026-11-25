#!/usr/bin/env python3
"""snapshot.py — 폴더 결과를 찍고(take), 두 찍음을 잡음을 빼고 대조한다(diff).

    python3 snapshot.py take <폴더> <찍음 파일>
    python3 snapshot.py diff <찍음 A> <찍음 B> [--ignore <정규식>]...

고치기 전과 고친 뒤 결과가 "바이트까지 같은지" 를 보는 도구다. 파일마다 한 줄을 적는다(경로 뒤는 탭).
    <상대 경로>\tF <sha256> <8진 모드>     일반 파일
    <상대 경로>\tL <링크 대상>              심볼릭 링크(따라가지 않는다)
`.git/` 은 늘 뺀다. 경로 정렬은 바이트 순서라 컴퓨터가 달라도 같은 순서다.

diff 는 다른 줄이 없으면 종료 0, 있으면 다른 경로를 출력하고 종료 1, 쓰임 오류는 종료 2.
--ignore 는 상대 경로에 re.search 로 맞춰 본다. 잡음(시각·무작위 ID 가 든 파일)은 프로젝트마다 다르므로
기본값이 없다 — 고치기 전에 기준선을 두 번 찍어 서로 다른 경로를 잡음으로 넘긴다.
"""
import argparse
import hashlib
import os
import re
import stat
import sys

SKIP_DIRS = {".git"}
CHUNK = 1 << 20


def file_sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(CHUNK), b""):
            h.update(block)
    return h.hexdigest()


def entries(root):
    """(상대 경로, 줄) 을 경로 바이트 순서로 낸다."""
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        # 디렉터리를 가리키는 링크는 os.walk 가 dirnames 에 넣는다 — 따라가지 않고 링크로 적는다.
        for name in list(dirnames):
            full = os.path.join(dirpath, name)
            if os.path.islink(full):
                dirnames.remove(name)
                filenames.append(name)
        for name in filenames:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root)
            if os.path.islink(full):
                found.append((rel, f"{rel}\tL {os.readlink(full)}"))
                continue
            st = os.stat(full)
            if not stat.S_ISREG(st.st_mode):
                continue
            found.append((rel, f"{rel}\tF {file_sha(full)} {stat.S_IMODE(st.st_mode):o}"))
    found.sort(key=lambda item: item[0].encode("utf-8", "surrogateescape"))
    return found


def take(root, out):
    if not os.path.isdir(root):
        print(f"폴더가 없습니다: {root}", file=sys.stderr)
        return 2
    rows = entries(root)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8", errors="surrogateescape") as f:
        for _, line in rows:
            f.write(line + "\n")
    print(f"찍음: {out} (파일 {len(rows)}개)")
    return 0


def load(path):
    """찍음 파일 → {상대 경로: 줄}."""
    table = {}
    with open(path, encoding="utf-8", errors="surrogateescape") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            rel = line.split("\t", 1)[0]
            table[rel] = line
    return table


def diff(a, b, ignores):
    pats = [re.compile(p) for p in ignores]
    ta, tb = load(a), load(b)
    changed = []
    for rel in sorted(set(ta) | set(tb)):
        if any(p.search(rel) for p in pats):
            continue
        if ta.get(rel) == tb.get(rel):
            continue
        if rel not in ta:
            changed.append(f"+ 새로 생김  {rel}")
        elif rel not in tb:
            changed.append(f"- 사라짐    {rel}")
        else:
            changed.append(f"~ 달라짐    {rel}")
    for line in changed:
        print(line)
    print(f"대조: 경로 {len(set(ta) | set(tb))}개 · 다른 경로 {len(changed)}개 · 무시 규칙 {len(pats)}개")
    return 1 if changed else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("take", help="폴더를 찍는다")
    t.add_argument("root")
    t.add_argument("out")
    d = sub.add_parser("diff", help="두 찍음을 대조한다")
    d.add_argument("a")
    d.add_argument("b")
    d.add_argument("--ignore", action="append", default=[], help="무시할 상대 경로 정규식(여러 번)")
    args = ap.parse_args(argv)
    try:
        if args.cmd == "take":
            return take(args.root, args.out)
        return diff(args.a, args.b, args.ignore)
    except (OSError, re.error) as e:
        print(f"오류: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
