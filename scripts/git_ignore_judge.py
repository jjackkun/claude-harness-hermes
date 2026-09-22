#!/usr/bin/env python3
"""git 이 이 경로를 무시하는가 — 한 가지만 판정한다 (계획 2026-09-22-gitignore-judge).

왜 종료 코드를 안 쓰는가: `git check-ignore -q <경로>` 의 종료 코드는 판 차이가 있다.
git 2.25.1 은 **예외 규칙(`!`)에 걸려 되살아난 경로에도 0(무시됨)** 을 준다 — 신형 git 은 1 이다.
그래서 `-v` 출력의 **패턴**을 읽는다. 패턴이 `!` 로 시작하면 그 경로는 무시되지 않는다.

    <출처>:<줄번호>:<패턴>\t<경로>
    .gitignore:2:!.claude/keep.json	.claude/keep.json   ← 무시 아님
    .gitignore:1:.claude/*	.claude/drop.json           ← 무시됨

규칙 해석은 계속 git 에게 맡긴다 — 바뀌는 것은 답을 읽는 방법뿐이다.

CLI 종료 코드: 0 무시됨 · 1 무시 안 됨 · 2 판정 불가(git 없음·저장소 아님).

공개 2개: is_ignored · main
"""

import argparse
import re
import subprocess
import sys

# `<출처>:<줄번호>:<패턴>` — 줄번호가 숫자라는 것만 믿는다. 출처 경로에 ':' 가 있어도 비탐욕 매칭이 받는다.
_VERBOSE_LINE = re.compile(r"^(.*?):(\d+):(.*)$")


def is_ignored(repo: str, rel: str) -> bool:
    """`repo` 안에서 `rel` 이 git 무시 규칙에 덮이는가. 판정 불가면 예외를 올린다.

    출력이 없으면 어떤 규칙에도 안 걸린 것이므로 무시되지 않는다.
    """
    proc = subprocess.run(["git", "-C", repo, "check-ignore", "-v", "--", rel],
                          capture_output=True, text=True, timeout=10)
    if proc.returncode not in (0, 1):          # 128 = 저장소 아님 등
        raise RuntimeError(proc.stderr.strip() or f"check-ignore rc={proc.returncode}")
    first = proc.stdout.split("\n", 1)[0].split("\t", 1)[0].strip()
    if not first:
        return False
    matched = _VERBOSE_LINE.match(first)
    if not matched:
        raise RuntimeError(f"해석할 수 없는 check-ignore 출력: {first!r}")
    return not matched.group(3).startswith("!")


def main() -> int:
    ap = argparse.ArgumentParser(description="git 무시 판정 (0 무시됨 · 1 아님 · 2 판정 불가)")
    ap.add_argument("--repo", required=True, help="저장소 경로")
    ap.add_argument("path", help="저장소 기준 상대 경로")
    args = ap.parse_args()
    try:
        ignored = is_ignored(args.repo, args.path)
    except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
        print(f"판정 불가: {exc}", file=sys.stderr)
        return 2
    print("ignored" if ignored else "not-ignored")
    return 0 if ignored else 1


if __name__ == "__main__":
    sys.exit(main())
