#!/usr/bin/env python3
"""판정 규칙 후보를 같은 자료로 재어 본다 — 읽기 전용, 모델 호출 0, DB 무변경.

진짜 짝 = (스킬, 그 스킬이 주입된 사람 세션). 가짜 짝 = 같은 스킬을 *다른* 세션의 도구 활동에 맞춘 것.
좋은 규칙은 진짜에서는 자주 '도움'이고 가짜에서는 드물다 — 차이(진짜율 - 가짜율)가 클수록 좋다.
가짜는 고정 시드로 FAKES_PER_PAIR 번 뽑아 평균한다. 세션 id 짝홀로 표본을 반으로 나눠
한쪽(even)에서 고르고 다른 쪽(odd)에서 확인하도록 반별 값을 함께 낸다.

사용: python3 scripts/hermes_yield_replay.py [--db .hermes/state.db] [--projects-dir ~/.claude/projects]
"""

import argparse
import glob
import importlib.util
import json
import os
import random
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAKES_PER_PAIR = 20  # 가짜 뽑기 횟수 — 한 번 뽑으면 우연에 흔들리고, 20번이면 평균이 안정된다
SEED = 20260929
STRATA = ((1, 99, "작음(1~99)"), (100, 999, "중간(100~999)"), (1000, 10**9, "큼(1000~)"))
DF_CUTS = (0.3, 0.5)  # 낱말이 세션의 이 비율 이상에 나오면 '흔한 낱말' — 후보로 둘 다 잰다
RATIOS = (0.05, 0.10, 0.20)  # 스킬 키워드 중 맞은 비율 하한 후보
MULTIPLES = (2, 3, 5)  # 우연 기대치의 몇 배 이상 맞아야 하나 — 후보로 셋 다 잰다
MIN_STRATUM_N = 20  # 층에 짝이 이보다 적으면 층 평균 차이에서 뺀다(작음 층 4개는 판단 근거가 못 된다)
MIN_OVERLAP = 2  # 현재 규칙(hermes-correlate.py MIN_KEYWORD_OVERLAP 기본값)과 같다


def _correlate():
    spec = importlib.util.spec_from_file_location("hcorr", os.path.join(HERE, "hermes-correlate.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _entrypoint(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        for i, line in enumerate(fh):
            if i > 60:
                break
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict) and obj.get("entrypoint"):
                return obj["entrypoint"]
    return ""


def load(db, projects_dir):
    """→ (짝 목록 [(skill, sid)], 세션별 토큰, 스킬별 키워드). 사람 세션·도구 토큰 1개 이상만."""
    corr = _correlate()
    con = sqlite3.connect(f"file:{os.path.abspath(db)}?mode=ro", uri=True)  # 읽기 전용으로만 연다
    kws = {p: {k.strip().lower() for k in (k or "").split(",") if k.strip()}
           for p, k in con.execute("SELECT skill_path, keywords FROM skill_index")}
    pairs, toks, seen = set(), {}, {}
    for skill, sid in con.execute("SELECT DISTINCT skill_path, session_id FROM skill_injection"):
        hit = glob.glob(os.path.join(projects_dir, "*", f"{sid}.jsonl"))
        if not hit or skill not in kws or _entrypoint(hit[0]) != "cli":
            continue
        if sid not in seen:
            seen[sid] = corr.session_tool_tokens(hit[0])
        if seen[sid]:  # 도구를 안 쓴 세션은 표본에도 가짜 뽑기 풀에도 넣지 않는다
            toks[sid] = seen[sid]
            pairs.add((skill, sid))
    return sorted(pairs), toks, kws


class Stats:
    """규칙이 공유하는 표본 통계 — 낱말별 등장 세션 비율, 전체 낱말 수."""

    def __init__(self, toks):
        self.df = {}
        for t in toks.values():
            for w in t:
                self.df[w] = self.df.get(w, 0) + 1
        self.n = len(toks)
        self.vocab = len(set().union(*toks.values()))

    def hits(self, kw, tk, cut):
        """스킬 키워드와 세션 낱말의 겹침 — cut 이 있으면 cut 비율 이상 세션에 나오는 흔한 낱말은 뺀다."""
        return {w for w in kw & tk if cut is None or self.df[w] / self.n < cut}

    def chance(self, kw, tk):
        """우연히 맞을 개수 = 키워드 수 x 세션 낱말 수 / 전체 낱말 수 — 길수록 우연히 많이 맞는다."""
        return len(kw) * len(tk) / self.vocab


def _rule(st, cut=None, ratio=0.0, multiple=0.0):
    def rule(kw, tk):
        h = len(st.hits(kw, tk, cut))
        return h >= MIN_OVERLAP and h / len(kw) >= ratio and h >= multiple * st.chance(kw, tk)
    return rule


def _cut_label(cut):
    return f"흔한낱말제외{int(cut * 100)}%" if cut else ""


def make_rules(toks):
    st = Stats(toks)
    rules = {"현재(겹침>=2)": _rule(st)}
    for cut in DF_CUTS:
        rules[_cut_label(cut)] = _rule(st, cut)
    for r in RATIOS:
        rules[f"비율>={r}"] = _rule(st, ratio=r)
        for cut in DF_CUTS:
            rules[f"{_cut_label(cut)}+비율>={r}"] = _rule(st, cut, ratio=r)
    for m in MULTIPLES:
        rules[f"기대치x{m}"] = _rule(st, multiple=m)
        rules[f"흔한낱말제외30%+기대치x{m}"] = _rule(st, 0.3, multiple=m)
    return rules


def _half(sid):
    return "even" if int(sid[:8], 16) % 2 == 0 else "odd"


def _stratum(n):
    return next(label for lo, hi, label in STRATA if lo <= n <= hi)


def _fake_count(rule, kw, toks, others, rng):
    picks = [rng.choice(others) for _ in range(FAKES_PER_PAIR)] if others else []
    return sum(1 for s in picks if rule(kw, toks[s])), len(picks)


def measure(pairs, toks, kws, rule):
    rng = random.Random(SEED)
    sids = sorted(toks)
    acc = {}  # 구간 키 → [진짜 합, 진짜 수, 가짜 합, 가짜 수]
    for skill, sid in pairs:
        kw = kws[skill]
        real = 1 if kw and rule(kw, toks[sid]) else 0
        fake, drawn = _fake_count(rule, kw, toks, [s for s in sids if s != sid], rng) if kw else (0, FAKES_PER_PAIR)
        for key in ("전체", _half(sid), _stratum(len(toks[sid]))):
            a = acc.setdefault(key, [0, 0, 0, 0])
            a[0] += real; a[1] += 1; a[2] += fake; a[3] += drawn
    return acc


def _cell(a):
    if not a or not a[1] or not a[3]:
        return "n/a(n=0)"
    r, f = a[0] / a[1], a[2] / a[3]
    return f"{r:.2f}/{f:.2f}/{r - f:+.2f}(n={a[1]})"


def _strata_mean(acc):
    labels = [x[2] for x in STRATA]
    diffs = [a[0] / a[1] - a[2] / a[3] for k, a in acc.items() if k in labels and a[1] >= MIN_STRATUM_N]
    return f"{sum(diffs) / len(diffs):+.2f}" if diffs else "n/a"


def report(pairs, toks, kws):
    print(f"사람 세션 {len(toks)}개 · (스킬,세션) 짝 {len(pairs)}개 · 가짜 {FAKES_PER_PAIR}번 평균 · 시드 {SEED}")
    keys = ["전체", "even", "odd"] + [s[2] for s in STRATA]
    print("규칙 | 층평균차 | " + " | ".join(f"{k}: 진짜/가짜/차" for k in keys))
    for name, rule in make_rules(toks).items():
        acc = measure(pairs, toks, kws, rule)
        print(f"{name} | {_strata_mean(acc)} | " + " | ".join(_cell(acc.get(k)) for k in keys))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", default=".hermes/state.db")
    ap.add_argument("--projects-dir", default=os.path.expanduser("~/.claude/projects"))
    args = ap.parse_args()
    pairs, toks, kws = load(args.db, args.projects_dir)
    if not pairs:
        print("잴 짝이 없습니다", file=sys.stderr)
        return 1
    report(pairs, toks, kws)
    return 0


if __name__ == "__main__":
    sys.exit(main())
