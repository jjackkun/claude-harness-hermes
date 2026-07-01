"""[예시] 디렉토리 경계 강제 — pytest.mark.parametrize 다층 방어 패턴.

⚠️ 이 파일은 ai-dev-setting 의 *예시 갤러리* 에 있다.
   rim-kanban 의 backend/tests/test_module_boundaries.py 에서 발췌.

test_mode_isolation.py 와 *같은 R1을 다른 각도로* 강제한다. 둘 다 있는 이유:
  1. 에이전트가 한 테스트를 우회/삭제해도 다른 테스트가 남는다 (다층 방어).
  2. parametrize 패턴이 더 간결해서 모드 개수가 늘어날 때 유지보수가 쉽다.
  3. 두 테스트가 서로 다른 import 탐지 규칙(substring vs endswith)을 써서 edge case
     커버리지가 올라간다.

치환 대상:
  - EXEC_ROOT, MODES
  - "app.execution.{sib}" 문자열
"""
from __future__ import annotations

import ast
from pathlib import Path

import pytest

# ↓↓↓ 프로젝트별로 치환 ↓↓↓
EXEC_ROOT = Path(__file__).resolve().parents[1] / "app" / "execution"
MODES = ("once", "scheduled", "realtime")
# ↑↑↑ 프로젝트별로 치환 ↑↑↑


def _collect_imports(pkg_dir: Path) -> list[tuple[Path, str]]:
    results: list[tuple[Path, str]] = []
    for py in pkg_dir.rglob("*.py"):
        tree = ast.parse(py.read_text(encoding="utf-8"), filename=str(py))
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module:
                results.append((py, node.module))
            elif isinstance(node, ast.Import):
                for alias in node.names:
                    results.append((py, alias.name))
    return results


@pytest.mark.parametrize("mode", MODES)
def test_mode_does_not_import_sibling_modes(mode: str) -> None:
    pkg = EXEC_ROOT / mode
    forbidden = {m for m in MODES if m != mode}
    violations: list[str] = []
    for file, module in _collect_imports(pkg):
        for sib in forbidden:
            if f"app.execution.{sib}" in module or module.endswith(f".execution.{sib}"):
                violations.append(f"{file}: imports {module} (forbidden sibling '{sib}')")
    assert not violations, "R1 위반:\n" + "\n".join(violations)


def test_shared_does_not_import_any_mode() -> None:
    pkg = EXEC_ROOT / "shared"
    violations: list[str] = []
    for file, module in _collect_imports(pkg):
        for sib in MODES:
            if f"app.execution.{sib}" in module:
                violations.append(f"{file}: imports {module} (shared must not depend on mode {sib})")
    assert not violations, "R1 위반 (의존 역전):\n" + "\n".join(violations)
