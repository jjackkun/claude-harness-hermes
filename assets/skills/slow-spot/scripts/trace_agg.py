#!/usr/bin/env python3
"""trace_agg.py — bash_profile.sh 가 남긴 추적 파일을 함수·줄·명령별 시간과 횟수로 모은다.

    python3 trace_agg.py <추적 파일> [--top N]

시간은 "자기 시간" 이다: 추적 줄 하나의 시각부터 다음 추적 줄의 시각까지를 그 줄에 준다.
그래서 `x=$(python3 ...)` 처럼 외부 명령을 띄운 줄은 그 명령이 끝날 때까지의 시간을 받는다.

세 표를 낸다.
- 함수별: 어느 함수가 시간을 먹는가(파일 이름 + 함수)
- 줄별: 그 함수 안 어느 줄인가(명령 견본 포함)
- 명령별: 어떤 명령이 몇 번 불렸나 — 같은 외부 명령(python3·git 등)이 수백 번 불리면 여기서 보인다
"""
import argparse
import collections
import re
import sys

LINE_RE = re.compile(r"^\++@(\d+(?:\.\d+)?)@([^@]*)@([^@]*)@ ?(.*)$")
SAMPLE_LEN = 90


def parse(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            m = LINE_RE.match(raw.rstrip("\n"))
            if m:
                rows.append((float(m.group(1)), m.group(2), m.group(3), m.group(4)))
    return rows


def command_word(cmd):
    """명령의 첫 낱말. 변수 대입(`a=b`)·빈 줄은 None."""
    word = cmd.split(" ", 1)[0] if cmd else ""
    if not word or "=" in word:
        return None
    return word.rsplit("/", 1)[-1]


def aggregate(rows):
    by_fn, by_line, by_cmd = collections.Counter(), collections.Counter(), collections.Counter()
    cmd_count, sample, sample_dt = collections.Counter(), {}, {}
    for cur, nxt in zip(rows, rows[1:]):
        dt = max(nxt[0] - cur[0], 0.0)
        _, where, fn, cmd = cur
        by_fn[where.split(":")[0] + " " + fn] += dt
        by_line[where] += dt
        if dt >= sample_dt.get(where, -1.0):   # 한 줄에 명령이 여럿이면(`f() { local rc; python3 ...`) 가장 오래 걸린 것을 견본으로
            sample[where], sample_dt[where] = cmd[:SAMPLE_LEN], dt
        word = command_word(cmd)
        if word:
            by_cmd[word] += dt
            cmd_count[word] += 1
    return by_fn, by_line, by_cmd, cmd_count, sample


def report(rows, top):
    if len(rows) < 2:
        return "추적 줄이 2개보다 적습니다 — 스크립트가 바로 끝났거나 추적 형식이 다릅니다(bash_profile.sh 로 찍었나요?)."
    by_fn, by_line, by_cmd, cmd_count, sample = aggregate(rows)
    total = rows[-1][0] - rows[0][0] or 1e-9
    out = [f"전체 {total:.2f}초 · 추적 줄 {len(rows)}개 (xtrace 가 붙어 실제보다 느리다 — 비율을 본다)", "", "== 함수별 자기 시간"]
    out += [f"{v:8.2f}s {v / total * 100:5.1f}%  {k}" for k, v in by_fn.most_common(top)]
    out += ["", "== 줄별 자기 시간"]
    out += [f"{v:8.2f}s {v / total * 100:5.1f}%  {k}  | {sample[k]}" for k, v in by_line.most_common(top)]
    out += ["", "== 명령별 (시간 · 횟수)"]
    out += [f"{v:8.2f}s {v / total * 100:5.1f}%  ×{cmd_count[k]:<5d} {k}" for k, v in by_cmd.most_common(top)]
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("trace")
    ap.add_argument("--top", type=int, default=15)
    args = ap.parse_args(argv)
    try:
        rows = parse(args.trace)
    except OSError as e:
        print(f"추적 파일을 읽지 못했습니다: {e}", file=sys.stderr)
        return 2
    print(report(rows, args.top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
