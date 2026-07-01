"""[예시] 디렉토리 상호 import 금지 — AST 기반 경계 검사.

⚠️ 이 파일은 ai-dev-setting 의 *예시 갤러리* 에 있다.
   rim-kanban 의 backend/tests/test_r1_boundary.py 에서 발췌.
   자기 프로젝트로 복사할 때 치환해야 할 것:
     - EXECUTION_DIR  → 자기 프로젝트의 "격리할 루트 디렉토리"
     - MODES          → 서로 import 불가인 서브디렉토리 이름 튜플
     - "execution.{forbidden}" → 실제 import 경로 prefix
     - "R1"           → 자기 core-beliefs.md 의 룰 번호

패턴:
  - import/ImportFrom 노드만 AST 로 수집
  - forbidden prefix 에 해당하는 import 가 있으면 파일:라인 으로 위반 누적
  - 마지막에 `assert not violations, "..."` — 위반 목록을 에러 메시지에 박아
    에이전트 컨텍스트로 보낸다 (PDF 9쪽).
"""
from __future__ import annotations

import ast
from pathlib import Path

# ↓↓↓ 프로젝트별로 치환 ↓↓↓
EXECUTION_DIR = Path(__file__).parent.parent / "app" / "execution"
MODES = ("once", "scheduled", "realtime")
# ↑↑↑ 프로젝트별로 치환 ↑↑↑


def _check_no_cross_import(src_mode: str, forbidden_modes: tuple[str, ...]) -> list[str]:
    violations: list[str] = []
    mode_dir = EXECUTION_DIR / src_mode
    if not mode_dir.exists():
        return violations
    for path in mode_dir.rglob("*.py"):
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"))
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            names: list[str] = []
            if isinstance(node, ast.Import):
                names = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom):
                names = [node.module or ""]
            for name in names:
                for forbidden in forbidden_modes:
                    if f"execution.{forbidden}" in name:
                        violations.append(
                            f"{path.relative_to(EXECUTION_DIR.parent.parent)}:{node.lineno} "
                            f"— [{src_mode}] imports [{forbidden}]: {name}"
                        )
    return violations


def test_once_does_not_import_scheduled_or_realtime():
    violations = _check_no_cross_import("once", ("scheduled", "realtime"))
    assert not violations, "R1 위반:\n" + "\n".join(violations)


def test_scheduled_does_not_import_once_or_realtime():
    violations = _check_no_cross_import("scheduled", ("once", "realtime"))
    assert not violations, "R1 위반:\n" + "\n".join(violations)


def test_realtime_does_not_import_once_or_scheduled():
    violations = _check_no_cross_import("realtime", ("once", "scheduled"))
    assert not violations, "R1 위반:\n" + "\n".join(violations)


def test_shared_does_not_import_any_mode():
    violations = _check_no_cross_import("shared", MODES)
    assert not violations, "R1 위반:\n" + "\n".join(violations)
