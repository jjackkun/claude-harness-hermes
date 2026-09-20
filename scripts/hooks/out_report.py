#!/usr/bin/env python3
"""R-out 기록을 명령 머리별로 모아 바이트 분포를 낸다 (계획 2026-09-08-tool-output-budget 목표 5).

  python3 scripts/hooks/out_report.py [--since-days N] [--threshold 8192] [--events 경로]

읽는 것: `.harness/gate-events.jsonl` 의 rule=R-out 레코드. path 칸 `cmd:<머리>`(2026-09-20 이후 기록) 와 detail 의 `<n>B`.
머리가 없는 옛 기록은 `(머리 없음)` 한 줄로 센다 — 버리지 않는다. 표준 모듈만(tier 0). 공개 함수 3개: parse_rows · summarize · main
"""
import argparse
import importlib.util
import os
import re
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_BYTES = re.compile(r"^(\d+)B\b")


def _gate_report():
    spec = importlib.util.spec_from_file_location("gate_report", os.path.join(_HERE, "gate_report.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_rows(records):
    """R-out 레코드 → [(머리, 바이트, verdict)]. skipped(바이트 없음)는 뺀다."""
    rows = []
    for rec in records:
        if rec.get("rule") != "R-out":
            continue
        m = _BYTES.match(str(rec.get("detail") or ""))
        if not m:
            continue
        path = str(rec.get("path") or "")
        head = path[4:] if path.startswith("cmd:") else "(머리 없음)"
        rows.append((head or "-", int(m.group(1)), rec.get("verdict")))
    return rows


def _pct(sorted_vals, q):
    return sorted_vals[min(len(sorted_vals) - 1, int(len(sorted_vals) * q))]


def summarize(rows, threshold):
    """머리별 {n, p50, p90, max, over, total} — 총 바이트 내림차순."""
    by = {}
    for head, n, _v in rows:
        by.setdefault(head, []).append(n)
    out = []
    for head, vals in by.items():
        vals.sort()
        out.append({"head": head, "n": len(vals), "p50": _pct(vals, .5), "p90": _pct(vals, .9), "max": vals[-1],
                    "over": sum(1 for v in vals if v >= threshold), "total": sum(vals)})
    out.sort(key=lambda r: -r["total"])
    return out


def _render(table, threshold, broken, nrows):
    lines = [f"R-out 명령별 출력 분포 — {nrows}건, 임계 {threshold:,}B" + (f", 깨진 줄 {broken}" if broken else "")]
    lines.append(f"{'명령 머리':28} {'n':>5} {'p50':>7} {'p90':>7} {'max':>8} {'초과':>4} {'합계':>10}")
    for r in table:
        lines.append(f"{r['head'][:28]:28} {r['n']:5} {r['p50']:7,} {r['p90']:7,} {r['max']:8,} {r['over']:4} {r['total']:10,}")
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description="R-out 명령별 바이트 분포")
    ap.add_argument("--since-days", type=int, default=None)
    ap.add_argument("--threshold", type=int, default=int(os.environ.get("R_OUT_THRESHOLD", "8192")))
    ap.add_argument("--events", default=None, help="gate-events.jsonl 경로(기본: 프로젝트의 .harness/)")
    args = ap.parse_args(argv)
    gr = _gate_report()
    path = args.events or gr._load_event_module().events_path()
    if not path or not os.path.isfile(path):
        print("[out-report] 기록 없음 — .harness/gate-events.jsonl 이 없다", file=sys.stderr)
        return 2
    since = time.time() - args.since_days * 86400 if args.since_days else None
    records, broken = gr.load_events(path, since)
    rows = parse_rows(records)
    print(_render(summarize(rows, args.threshold), args.threshold, broken, len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
