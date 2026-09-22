#!/usr/bin/env python3
"""완료 계획서 회고의 "다음 룰 후보" 를 모아 반복 수·상태를 매긴다. 계산만 한다 — DB·파일 쓰기 없음.

왜: 후보가 48개 계획서에 흩어져 있어 놓치면 다시 찾을 길이 없었다(2026-09-22 실측 약 50건).
상태 넷: review(반복 2회 이상 + 보류 → 승격 검토) · pending(보류) · promoted(승격됨) · dropped(폐기).
근거: docs/exec-plans/completed/2026-09-22-rule-candidates-dashboard-plan.md
"""

import difflib
import glob
import os
import re

# 승격 스킬(harness-promote-rule)의 발동 조건과 같다 — "같은 결함이 2회 이상".
REVIEW_MIN_COUNT = 2
# 같은 교훈을 한 후보로 묶는 문장 유사도. 문장이 계획서마다 달라 추정치다 — 판단은 사람이 한다.
_SAME_LESSON = 0.6
# 좁게 잡는다: "한 번 더 나오면 승격" · "승격 조건 충족" 은 승격된 것이 아니다.
_PROMOTED = re.compile(r"승격\s*(됨|완료|했)|로\s*승격(됨|했|완료)")
_DROPPED = re.compile(r"폐기|철회")
_COUNT = re.compile(r"사례\s*(\d+)\s*건|(\d+)\s*번째\s*사례|—\s*(\d+)\s*건")
_HEAD = re.compile(r"^- 다음 룰 후보:?\s*(.*)$")


def _section(lines: list) -> list:
    """'- 다음 룰 후보' 칸의 후보 문장들. 한 줄 칸이면 그 줄, 하위 목록이면 하위 줄들."""
    for i, line in enumerate(lines):
        m = _HEAD.match(line.strip())
        if not m:
            continue
        subs = []
        for nxt in lines[i + 1:]:
            if not nxt.startswith((" ", "\t")) or not nxt.strip():
                break
            if nxt.strip().startswith("- "):
                subs.append(nxt.strip()[2:])
        items = subs or [m.group(1)]
        return [t.strip() for t in items if t.strip() and not t.strip().startswith("없음")]
    return []


def _lesson(text: str) -> str:
    """교훈 문장 — 설명(" — " 뒤)과 따옴표를 뺀 앞부분."""
    return text.split(" — ")[0].strip().strip('"“”\'')


def _count(text: str) -> int:
    nums = [int(n) for m in _COUNT.finditer(text) for n in m.groups() if n]
    return max(nums, default=1)


def _status(text: str) -> str:
    if _PROMOTED.search(text):
        return "promoted"
    return "dropped" if _DROPPED.search(text) else "pending"


def _raw(completed_dir: str) -> list:
    raw = []
    for path in sorted(glob.glob(os.path.join(completed_dir, "*.md"))):
        name = os.path.basename(path)
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().split("\n")
        for text in _section(lines):
            raw.append({"text": _lesson(text), "note": text, "file": name, "date": name[:10]})
    return raw


def _group(raw: list) -> list:
    groups = []
    for item in raw:
        home = next((g for g in groups
                     if difflib.SequenceMatcher(None, g["text"], item["text"]).ratio() >= _SAME_LESSON), None)
        if home is None:
            groups.append({"text": item["text"], "notes": [item["note"]], "sources": [(item["file"], item["date"])]})
        else:
            home["notes"].append(item["note"])
            home["sources"].append((item["file"], item["date"]))
    return groups


_ORDER = {"review": 0, "pending": 1, "promoted": 2, "dropped": 3}


def collect(completed_dir: str) -> list:
    """후보 목록 — 검토 필요가 맨 앞, 같은 상태 안에서는 최근 순."""
    items = []
    for g in _group(_raw(completed_dir)):
        latest_note = max(zip(g["sources"], g["notes"]), key=lambda x: x[0][1])[1]
        count = max(max(_count(n) for n in g["notes"]), len(g["sources"]))
        status = _status(latest_note)
        if status == "pending" and count >= REVIEW_MIN_COUNT:
            status = "review"
        items.append({"text": g["text"], "count": count, "status": status, "sources": g["sources"],
                      "latest": max(d for _f, d in g["sources"])})
    items.sort(key=lambda i: i["latest"], reverse=True)
    return sorted(items, key=lambda i: _ORDER[i["status"]])
