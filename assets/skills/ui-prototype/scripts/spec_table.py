"""시안 명세표 읽기 — `<!-- ui-prototype:spec v1 -->` 바로 아래 첫 표와 `<!-- ui-prototype:requires ... -->` 줄.

양식은 assets/spec-table.md 에 있다. 칸 순서·이름이 다르면 SpecError — 조용히 넘어가면
check_spec.py 가 빈 표를 "통과" 로 읽는다.
"""
import re

MARKER = "<!-- ui-prototype:spec v1 -->"
COLUMNS = ["범위", "그룹", "번호", "이름", "상태", "틀", "보여 주는 것", "행동", "근거"]
REQUIRES_RE = re.compile(r"<!--\s*ui-prototype:requires\b(.*?)-->")


class SpecError(ValueError):
    """명세표를 양식대로 읽을 수 없음."""


def _cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def _table_lines(lines):
    start = next((i for i, l in enumerate(lines) if l.strip() == MARKER), None)
    if start is None:
        raise SpecError(f"표지 {MARKER} 가 없습니다")
    rest = lines[start + 1:]
    first = next((i for i, l in enumerate(rest) if l.strip()), None)
    if first is None or not rest[first].lstrip().startswith("|"):
        raise SpecError("표지 바로 아래에 표가 없습니다")
    table = []
    for line in rest[first:]:
        if not line.lstrip().startswith("|"):
            break
        table.append(line)
    return table


def parse_actions(text):
    """'라벨→번호; 라벨→번호' → [(라벨, 번호)]. '-' 는 행동 없음."""
    if text in ("", "-"):
        return []
    pairs = []
    for part in text.split(";"):
        label, arrow, target = part.partition("→")
        if not arrow:
            raise SpecError(f"행동 칸은 '라벨→번호' 를 ';' 로 잇습니다: {part.strip()!r}")
        pairs.append((label.strip(), target.strip()))
    return pairs


def read_spec(text):
    """명세표 문서 → (행 목록, 범위 안 요구 ID 목록). 행은 칸 이름을 키로 한 dict + 'actions'."""
    table = _table_lines(text.splitlines())
    header = _cells(table[0])
    if header != COLUMNS:
        raise SpecError(f"칸 순서·이름이 양식과 다릅니다: {header} (양식 {COLUMNS})")
    rows = []
    for line in table[2:]:
        cells = _cells(line)
        if len(cells) != len(COLUMNS):
            raise SpecError(f"칸 수가 {len(COLUMNS)} 이 아닌 줄: {line.strip()}")
        row = dict(zip(COLUMNS, cells))
        row["actions"] = parse_actions(row["행동"])
        rows.append(row)
    found = REQUIRES_RE.search(text)
    requires = found.group(1).split() if found else []
    return rows, requires
