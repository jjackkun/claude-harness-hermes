#!/usr/bin/env python3
"""R-cx — 순환 복잡도 게이트 (라쳇 방식).

Usage:
    complexity.py file.py ...      # 검사. 위반이면 exit 1
    complexity.py --report f.py    # "복잡도 파일:줄 함수명" 을 한 줄씩 출력 (exit 0)

왜 필요한가: 하네스에는 복잡도를 재는 장치가 하나도 없었다. R-size 는 파일 크기만 보므로
500줄 한도를 지키면서 순환 복잡도 48 짜리 함수를 쓰는 것이 완전히 통과했다 —
실제로 이 저장소에 그런 함수가 둘 있었다(hermes-search.py, generate_settings_json.py 의 main).

임계 12 의 근거: 저장소 함수 295개의 복잡도 분포에서 `11:11개 → 12:4개` 로 급락한다.
1~11 구간은 10~61개로 두텁게 이어지다 12 에서 끊긴다. 그 절벽에 임계를 놓는다.
영상(로버트 마틴)의 권고 6~8 은 CRAP 스코어 기준이라 척도가 다르고, 이 저장소에서
임계 8 이면 68개(23%), 6 이면 101개(34%) 가 걸려 과발화한다.

라쳇인 이유: 임계 12 를 일괄 적용하면 파일 37개 중 16개(43%)가 즉시 막힌다.
그 상태로 켜면 게이트를 끄거나 --no-verify 로 우회하는 것이 정상 작업 흐름이 된다.
.cxbaseline 에 기존 파일의 현재 최대값을 동결하고, **나빠질 때만** 차단한다.

radon 을 쓰지 않는 이유: 하네스는 여러 프로젝트에 설치되는 도구이고, 각 프로젝트에
외부 패키지 설치를 요구하면 설치 실패가 곧 게이트 침묵이 된다(R-test 가 실제로 그 상태다).
표준 ast 만 쓴다 — check-secrets.py·plan_state.py 와 같은 판단이다.

스펙: docs/superpowers/specs/2026-08-24-complexity-gate-design.md
"""
from __future__ import annotations

import ast
import os
import sys

DEFAULT_MAX = 12
BASELINE_FILE = ".cxbaseline"


class _Counter(ast.NodeVisitor):
    """McCabe 근사. 분기를 만들 때마다 +1."""

    def __init__(self) -> None:
        self.n = 1

    def _bump(self, node: ast.AST) -> None:
        self.n += 1
        self.generic_visit(node)

    visit_If = visit_For = visit_While = visit_ExceptHandler = _bump
    visit_AsyncFor = visit_With = visit_Assert = _bump
    visit_IfExp = _bump

    def visit_BoolOp(self, node: ast.BoolOp) -> None:
        # `a and b and c` 는 분기 2개다 — 피연산자 수 - 1.
        self.n += len(node.values) - 1
        self.generic_visit(node)

    def visit_comprehension(self, node: ast.comprehension) -> None:
        self.n += 1 + len(node.ifs)
        self.generic_visit(node)


def measure(path: str) -> list[tuple[int, str, int]]:
    """(복잡도, 함수명, 줄번호) 목록. 읽기·파싱 실패는 빈 목록 — 다른 게이트의 관할이다."""
    try:
        tree = ast.parse(open(path, encoding="utf-8").read())
    except (OSError, SyntaxError, UnicodeDecodeError):
        return []
    out = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            c = _Counter()
            for child in node.body:
                c.visit(child)
            out.append((c.n, node.name, node.lineno))
    return out


def load_baseline(start: str = ".") -> dict[str, int]:
    """`경로 최대값` 한 줄씩. 파일이 없으면 빈 dict — 모두 기본 임계가 적용된다."""
    path = os.path.join(start, BASELINE_FILE)
    if not os.path.exists(path):
        return {}
    out = {}
    for line in open(path, encoding="utf-8"):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.rsplit(None, 1)
        if len(parts) == 2 and parts[1].isdigit():
            out[parts[0]] = int(parts[1])
    return out


def _report(paths: list[str]) -> int:
    for path in paths:
        for cx, name, line in sorted(measure(path), reverse=True):
            print(f"{cx} {path}:{line} {name}")
    return 0


def _judge(path: str, limit: int) -> tuple[list[str], int | None]:
    """(위반 메시지들, 이 파일의 최대 복잡도). 측정할 함수가 없으면 최대값은 None."""
    found = measure(path)
    if not found:
        return [], None
    out = [
        f"[R-cx] {path}:{line} {name}() — 순환 복잡도 {cx} > 한도 {limit}.\n"
        f"  → 분기를 이름 있는 헬퍼로 뽑아낼 것. 조기 반환으로 중첩을 낮출 것.\n"
        f"  근거: docs/design-docs/core-beliefs.md#r-cx"
        for cx, name, line in sorted(found, reverse=True) if cx > limit
    ]
    return out, max(c for c, _, _ in found)


def _main(argv: list[str]) -> int:
    if argv and argv[0] == "--report":
        return _report(argv[1:])

    hard = int(os.environ.get("MAX_COMPLEXITY", DEFAULT_MAX))
    baseline = load_baseline()
    violations: list[str] = []
    improved: list[str] = []

    for path in argv:
        # 두 값의 의미가 다르다 — 섞으면 경계에서 한 칸씩 어긋난다.
        #   MAX_COMPLEXITY(hard): **이 값부터 차단**하는 임계. 12 면 12 가 걸린다.
        #   .cxbaseline: 그 파일에 **허용하는 최대값**. 20 이면 20 은 통과하고 21 이 걸린다.
        # 아래 limit 은 "허용 최대" 로 통일한다.
        limit = baseline[path] if path in baseline else hard - 1
        found, worst = _judge(path, limit)
        violations.extend(found)
        # 기준선을 가진 파일이 개선됐으면 알린다. 고쳐 쓰지는 않는다 —
        # 훅이 워킹트리를 수정하면 커밋에 포함되지 않은 변경이 생긴다.
        if worst is not None and path in baseline and worst < baseline[path]:
            improved.append(f"  {path}: {baseline[path]} → {worst}")

    if improved:
        sys.stderr.write(
            "[R-cx] 복잡도가 개선됐다. .cxbaseline 을 낮춰 후퇴를 막을 것:\n"
            + "\n".join(improved) + "\n"
        )
    if violations:
        sys.stderr.write("\n" + "\n\n".join(violations) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
