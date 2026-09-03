#!/usr/bin/env python3
"""누적된 게이트 이벤트를 룰별 발화율 표로 집계한다.

근거: docs/design-docs/core-beliefs.md — Provisional 룰의 승격·강등 판단 입력.

단일 책임: **읽기와 집계**. 레코드 형식·저장 위치의 주인은 `gate_event.py` 이고,
이 파일은 그 상수를 import 해서 쓴다. 필드 이름을 여기서 다시 적으면 정의가 둘이 되고,
그러면 집계가 조용히 0 을 낸다.

사용법:
  gate_report.py                 # 전체
  gate_report.py --days 7        # 최근 7일
  gate_report.py --rule R-iface  # 한 룰만

읽는 법:
  기회  = 그 룰이 실제로 평가된 횟수 (분모)
  발화율 = (warn + block) / 기회
  우회  = waiver 로 통과한 횟수. 늘어나면 임계가 과발화한다는 신호다.
  건너뜀 = 판정 모듈이 없어 검사하지 못한 횟수. **0 이 아니면 게이트가 죽어 있었다.**

종료코드: 0=성공, 2=이벤트 파일 없음/읽기 실패.
"""

import importlib.util
import json
import os
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load_event_module():
    """스키마와 경로의 주인을 가져온다. 없으면 이 도구는 성립하지 않는다."""
    path = os.path.join(_HERE, "gate_event.py")
    spec = importlib.util.spec_from_file_location("gate_event", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_events(path, since=None):
    """jsonl 을 레코드 리스트로. 깨진 줄은 건너뛰되 개수를 함께 돌려준다.

    깨진 줄을 조용히 버리지 않는 이유: 기록이 유실되고 있다는 사실 자체가
    관측 대상이다. 발화율이 낮은 것이 "안 걸렸다" 인지 "기록이 깨졌다" 인지 구분해야 한다.
    """
    records, broken = [], 0
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                broken += 1
                continue
            if since is not None and rec.get("ts", 0) < since:
                continue
            records.append(rec)
    return records, broken


def tally(records):
    """룰별 {verdict: 횟수} 로 접는다."""
    out = {}
    for rec in records:
        rule = rec.get("rule") or "(unknown)"
        verdict = rec.get("verdict") or "?"
        out.setdefault(rule, {})[verdict] = out.setdefault(rule, {}).get(verdict, 0) + 1
    return out


def _row(rule, counts, verdicts):
    """룰 하나를 표의 한 줄로. 기회(분모)에서 skipped 는 뺀다 —
    판정하지 못한 것은 평가 기회가 아니다."""
    chance = sum(counts.get(v, 0) for v in verdicts if v != "skipped")
    fired = counts.get("warn", 0) + counts.get("block", 0)
    rate = "%.1f%%" % (100.0 * fired / chance) if chance else "—"
    return (rule, str(chance), str(counts.get("pass", 0)), str(counts.get("warn", 0)),
            str(counts.get("block", 0)), str(counts.get("waived", 0)),
            str(counts.get("skipped", 0)), rate)


def _rate_key(row):
    """발화율 내림차순. 분모가 없는 줄은 맨 아래로 — 판단할 근거가 없는 줄이다."""
    return (1, row[0]) if row[7] == "—" else (0, -float(row[7][:-1]), row[0])


def _render(header, rows):
    widths = []
    for i, h in enumerate(header):
        widths.append(max([len(h)] + [len(r[i]) for r in rows]))
    out = ["  ".join(h.ljust(widths[i]) for i, h in enumerate(header)),
           "  ".join("-" * w for w in widths)]
    for r in rows:
        out.append("  ".join(r[i].ljust(widths[i]) for i in range(len(header))))
    return "\n".join(out)


def format_table(counts, verdicts):
    """사람이 읽을 표. 발화율 내림차순 — 과발화 후보가 위로 온다."""
    header = ("룰", "기회", "통과", "경고", "차단", "우회", "건너뜀", "발화율")
    rows = sorted((_row(rule, c, verdicts) for rule, c in counts.items()), key=_rate_key)
    return _render(header, rows)


def _parse_args(argv):
    args, key = {}, None
    for tok in argv[1:]:
        if tok.startswith("--"):
            key = tok[2:]
            args[key] = None
        elif key is not None:
            args[key] = tok
            key = None
    return args


def _since(days):
    if days and days.isdigit():
        return int(time.time()) - int(days) * 86400
    return None


def _notes(records, counts, broken, days):
    out = ["레코드 %d건%s" % (len(records), " (기간 %s일)" % days if days else "")]
    if broken:
        out.append("⚠ 파싱 실패한 줄 %d개 — 기록이 유실되고 있습니다." % broken)
    skipped = sorted(r for r, c in counts.items() if c.get("skipped"))
    if skipped:
        out.append("⚠ 건너뛴 게이트: %s — 판정 모듈 배포를 확인하십시오 (재설치)."
                   % ", ".join(skipped))
    return out


def main(argv):
    args = _parse_args(argv)
    ev = _load_event_module()
    path = ev.events_path()
    if not path or not os.path.exists(path):
        print("이벤트 파일이 없습니다 — 아직 게이트가 한 번도 판정하지 않았거나 "
              "gate_event.py 가 배포되지 않았습니다.", file=sys.stderr)
        return 2

    days = args.get("days")
    records, broken = load_events(path, _since(days))
    if args.get("rule"):
        records = [r for r in records if r.get("rule") == args["rule"]]
    if not records:
        print("해당 조건의 이벤트가 없습니다.")
        return 0

    counts = tally(records)
    print(format_table(counts, ev.VERDICTS))
    print()
    for line in _notes(records, counts, broken, days):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
