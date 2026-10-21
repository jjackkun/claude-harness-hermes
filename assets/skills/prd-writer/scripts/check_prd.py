#!/usr/bin/env python3
"""prd.md 가 사슬 계약(references/contract.md §6)을 지키는지 검사한다.

사용: python3 check_prd.py docs/product-specs/<이름>/prd.md
종료 0 = 통과, 1 = 어긋남(표식 줄 출력), 2 = 파일·계약을 읽지 못함.
계약 버전은 contract.md 에서 읽는다 — 버전 숫자를 이 파일에 다시 적지 않는다.
"""
import re
import sys
from pathlib import Path

CONTRACT = Path(__file__).resolve().parent.parent / "references" / "contract.md"
SECTIONS = ["문제", "대상 사용자", "목표 지표", "범위", "비범위", "요구사항", "실행 계약", "가정·열린 질문"]
COLUMNS = ["ID", "요구", "검증", "우선순위", "상태"]
PRIORITIES = {"필수", "권장", "선택"}
STATES = {"유효", "폐기"}
FR_RE = re.compile(r"^FR-[0-9]+$")
EMPTY_CELLS = {"", "-"}


def contract_version():
    found = re.search(r"^contract-version: ([0-9]+)$", CONTRACT.read_text(encoding="utf-8"), re.M)
    if not found:
        raise ValueError(f"계약에 버전 줄이 없습니다: {CONTRACT}")
    return found.group(1)


def check_head(text, version):
    rules = {
        "status": r"^- status: (draft|approved)$",
        "updated": r"^- updated: [0-9]{4}-[0-9]{2}-[0-9]{2}$",
        "contract-version": rf"^- contract-version: {version}$",
    }
    return [f"[머리] '{key}' 줄이 없거나 값이 계약과 다름" for key, rule in rules.items() if not re.search(rule, text, re.M)]


def section_body(text, name):
    heading = re.compile(rf"^##\s+(?:[0-9]+\.\s*)?{re.escape(name)}\s*$", re.M)
    found = heading.search(text)
    if not found:
        return None
    rest = text[found.end():]
    following = re.search(r"^##\s", rest, re.M)
    return rest[: following.start()] if following else rest


def first_table(body):
    """절 안의 첫 표 — 처음 나온 `|` 줄부터 `|` 아닌 줄 전까지 (계약 §6: 요구사항 아래 첫 표)."""
    lines, started = [], False
    for raw in body.splitlines():
        line = raw.strip()
        if line.startswith("|"):
            lines.append(line)
            started = True
        elif started:
            break
    return lines


def table_rows(body):
    cells = [[c.strip() for c in ln.strip("|").split("|")] for ln in first_table(body)]
    return (cells[0], cells[2:]) if len(cells) >= 2 else (None, [])


def check_row(row, seen):
    rid, verify, priority, state = row["ID"], row["검증"], row["우선순위"], row["상태"]
    problems = []
    if not FR_RE.match(rid):
        problems.append(f"[FR 형식] '{rid}' — FR-<숫자> 여야 함")
    if rid in seen:
        problems.append(f"[FR 중복] {rid} — 번호는 다시 쓰지 않음")
    seen.add(rid)
    if state == "유효" and verify in EMPTY_CELLS:
        problems.append(f"[검증 빈칸] {rid} — 유효한 요구는 검증 방법이 있어야 함")
    if priority not in PRIORITIES:
        problems.append(f"[값] {rid} 우선순위 '{priority}' — {'·'.join(sorted(PRIORITIES))} 중 하나")
    if state not in STATES:
        problems.append(f"[값] {rid} 상태 '{state}' — {'·'.join(sorted(STATES))} 중 하나")
    return problems


def check_requirements(body):
    header, rows = table_rows(body)
    if header != COLUMNS:
        return [f"[표 없음] 요구사항 첫 표의 열이 {'|'.join(COLUMNS)} 가 아님 (지금: {header})"]
    if not rows:
        return ["[표 없음] 요구사항 표에 행이 없음"]
    seen, problems = set(), []
    for cells in rows:
        problems += check_row(dict(zip(COLUMNS, cells + [""] * len(COLUMNS))), seen)
    return problems


def check(text, version):
    problems = check_head(text, version)
    for name in SECTIONS:
        if section_body(text, name) is None:
            problems.append(f"[절 없음] {name}")
    body = section_body(text, "요구사항")
    if body is not None:
        problems += check_requirements(body)
    return problems


def main(argv):
    if len(argv) != 2:
        print("사용: check_prd.py <prd.md>", file=sys.stderr)
        return 2
    try:
        text = Path(argv[1]).read_text(encoding="utf-8")
        version = contract_version()
    except (OSError, ValueError) as err:
        print(f"[읽기 실패] {err}", file=sys.stderr)
        return 2
    problems = check(text, version)
    for line in problems:
        print(line)
    print(f"{'통과' if not problems else '실패'} — 어긋남 {len(problems)}건 (contract-version {version})")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
