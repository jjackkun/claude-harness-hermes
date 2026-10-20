#!/usr/bin/env python3
"""시안 명세표 ↔ 실제 등록 장면 대조 — 명세표가 원본이고 화면 파일이 따라간다.

사용: python3 check_spec.py <시안 폴더> [--spec <명세표 경로>]   (기본 <시안 폴더>/spec.md)
실패(종료 1): [불일치] [끊김] [요구 누락] [번호] [로드] [틀] [행동] [render] [범위] [명세 행동]
알림(종료에 영향 없음): [알림] 들어오는 버튼 없는 장면 · 아직 등록 안 된 2차 대상
읽을 수 없음(종료 2): 명세표 양식 위반, 시안 스크립트 로드 실패
"""
import argparse
import json
import os
import re
import subprocess
import sys

# 스크립트로 실행하면 이 폴더가 sys.path 맨 앞이라 같은 폴더 모듈을 바로 읽는다 (스킬은 설치 없이 실행된다)
from spec_table import SpecError, read_spec

ID_RE = re.compile(r"^[A-Z]{1,4}-[0-9]{2}[a-z]?$")  # registry.js 의 ID_RE 와 같은 규칙
FRAMES = ("phone", "tablet", "browser", "desktop")
REQ_ID_RE = re.compile(r"\b[A-Z]+-[0-9]+\b")
HERE = os.path.dirname(os.path.abspath(__file__))


def _collect(folder):
    proc = subprocess.run(["node", os.path.join(HERE, "collect_scenes.js"), folder],
                          capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "collect_scenes.js 실패")
    return json.loads(proc.stdout)


def _check_rows(rows):
    ids = [r["번호"] for r in rows]
    fails = []
    for r in rows:
        n = r["번호"]
        if not ID_RE.match(n):
            fails.append(f"[번호] {n} — 영문 대문자 1~4 · '-' · 숫자 2 · 소문자 0~1 (예: SD-01, EB-01a). 원래 번호는 근거 칸에")
        if ids.count(n) > 1:
            fails.append(f"[번호] {n} 가 명세표에 두 번 있음")
        if r["틀"] not in FRAMES:
            fails.append(f"[틀] {n} 의 틀 '{r['틀']}' — {' · '.join(FRAMES)} 중 하나")
        if r["범위"] not in ("1차", "2차"):
            fails.append(f"[범위] {n} 의 범위 '{r['범위']}' — 1차 · 2차 중 하나")
        fails += [f"[명세 행동] {n} → {t} — 명세표에 없는 대상" for _, t in r["actions"] if t not in ids]
    return sorted(set(fails), key=fails.index)


def _check_registration(rows, scenes):
    spec_ids = {r["번호"] for r in rows}
    registered = {s["id"] for s in scenes}
    fails = [f"[불일치] 1차 명세 장면이 등록되지 않음: {r['번호']}"
             for r in rows if r["범위"] == "1차" and r["번호"] not in registered]
    fails += [f"[불일치] 등록됐는데 명세표에 없는 장면: {i}" for i in sorted(registered - spec_ids)]
    return fails


def _check_gos(scene, spec_ids, registered):
    """화면의 버튼 대상 — 명세표에 없으면 실패, 명세표에는 있지만 아직 안 그린 2차 화면이면 알림."""
    sid = scene["id"]
    fails = [f"[끊김] {sid} → {go} (명세표에 없는 대상)" for go in scene["gos"] if go not in spec_ids]
    notes = [f"[알림] 아직 등록 안 된 대상: {sid} → {go}"
             for go in scene["gos"] if go in spec_ids and go not in registered]
    return fails, notes


def _check_actions(scene, row):
    """명세표 행동마다 화면에 그 버튼이 있는가. 같은 화면 안의 변화(자기 번호)는 mount 에서 처리하므로 뺀다."""
    sid = scene["id"]
    return [f"[행동] {sid} → {target} ('{label}') — 명세표에 있는데 화면에 이 버튼이 없음"
            for label, target in row["actions"] if target != sid and target not in scene["gos"]]


def _check_scene(scene, row, spec_ids, registered):
    sid = scene["id"]
    fails = [f"[render] {sid}: {scene['error']}"] if scene.get("error") else []
    if row and row["틀"] in FRAMES and row["틀"] != scene["frame"]:
        fails.append(f"[틀] {sid} 명세 {row['틀']} · 등록 {scene['frame']}")
    go_fails, notes = _check_gos(scene, spec_ids, registered)
    return fails + go_fails + (_check_actions(scene, row) if row else []), notes


def _check_requires(rows, requires):
    cited = {q for r in rows for q in REQ_ID_RE.findall(r["근거"])}
    return [f"[요구 누락] {q} — 범위 안 요구인데 어느 행 근거에도 없음" for q in requires if q not in cited]


def _orphans(scenes):
    """첫 장면(시작 화면) 말고, 다른 장면의 버튼으로는 갈 수 없고 화면 목록으로만 들어오는 장면."""
    incoming = {g for s in scenes for g in s["gos"] if g != s["id"]}
    return [s["id"] for s in scenes[1:] if s["id"] not in incoming]


def _report(folder, spec_path):
    with open(spec_path, encoding="utf-8") as f:
        rows, requires = read_spec(f.read())
    data = _collect(folder)
    scenes = data["scenes"]
    by_id = {r["번호"]: r for r in rows}
    registered = {s["id"] for s in scenes}
    fails = _check_rows(rows) + _check_registration(rows, scenes) + _check_requires(rows, requires)
    fails += [f"[로드] {f} — index.html 에 <script src> 가 없음" for f in data["notLoaded"]]
    notes = []
    for s in scenes:
        f, n = _check_scene(s, by_id.get(s["id"]), set(by_id), registered)
        fails, notes = fails + f, notes + n
    orphans = _orphans(scenes)
    if orphans:
        notes.append(f"[알림] 들어오는 버튼 없는 장면: {', '.join(orphans)} (목록 진입이 맞으면 명세표 근거에 적는다)")
    first = sum(1 for r in rows if r["범위"] == "1차")
    print(f"장면 {len(scenes)} · 명세 행 {len(rows)}(1차 {first}) · 실패 {len(fails)} · 알림 {len(notes)}")
    for line in fails + notes:
        print("  " + line)
    return 1 if fails else 0


def main():
    ap = argparse.ArgumentParser(description="시안 명세표와 등록 장면을 대조한다")
    ap.add_argument("folder", help="시안 폴더 (index.html · spec.md 가 있는 곳)")
    ap.add_argument("--spec", help="명세표 경로 (기본 <시안 폴더>/spec.md)")
    args = ap.parse_args()
    folder = os.path.abspath(args.folder)
    try:
        return _report(folder, args.spec or os.path.join(folder, "spec.md"))
    except (SpecError, RuntimeError, OSError) as err:
        print(f"[읽을 수 없음] {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
