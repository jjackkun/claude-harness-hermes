"""[예시] 특정 패키지 import·설치·가용성 3중 차단.

⚠️ 이 파일은 ai-dev-setting 의 *예시 갤러리* 에 있다.
   rim-kanban 의 backend/tests/test_llm_path.py 에서 발췌 (R3: anthropic SDK 금지).

패턴의 핵심 — "왜 3중인가":
  1. test_no_import_anthropic_in_source: 소스 코드 AST 로 import 문 탐지.
     → 커밋된 코드가 금지 패키지를 import 하는 것 자체를 차단.
  2. test_anthropic_not_in_requirements: requirements.txt / pyproject.toml 검사.
     → 의존성 선언으로 몰래 추가되는 것을 차단.
  3. test_anthropic_not_importable: 현재 venv 에 실제로 설치돼 있지 않음을 검증.
     → 개발자가 로컬에서 `pip install anthropic` 해도 CI 가 잡음.

3중으로 하는 이유: PDF 8쪽 "구현을 세세하게 관리하지 않고 불변 조건을 강제 적용한다"
+ 다층 방어. 한 레이어만 있으면 다른 레이어로 우회한다.

치환 대상:
  - "anthropic" 문자열을 전부 금지할 패키지 이름으로 바꿔라.
  - APP_DIR 경로.
  - R3 → 자기 프로젝트의 룰 번호.
"""
from __future__ import annotations

import ast
import importlib.util
from pathlib import Path

# ↓↓↓ 프로젝트별로 치환 ↓↓↓
BACKEND_DIR = Path(__file__).parent.parent
APP_DIR = BACKEND_DIR / "app"
BANNED_PACKAGE = "anthropic"
RULE_ID = "R3"
# ↑↑↑ 프로젝트별로 치환 ↑↑↑


def _py_files():
    return list(APP_DIR.rglob("*.py"))


def test_no_import_banned_package_in_source():
    """app/ 내 어떤 .py 도 금지 패키지를 import 하지 않는다."""
    violations: list[str] = []
    for path in _py_files():
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"))
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name == BANNED_PACKAGE or alias.name.startswith(f"{BANNED_PACKAGE}."):
                        violations.append(f"{path}:{node.lineno} — import {alias.name}")
            elif isinstance(node, ast.ImportFrom):
                if node.module and (
                    node.module == BANNED_PACKAGE
                    or node.module.startswith(f"{BANNED_PACKAGE}.")
                ):
                    violations.append(f"{path}:{node.lineno} — from {node.module} import ...")
    assert not violations, f"{RULE_ID} 위반 — {BANNED_PACKAGE} import 발견:\n" + "\n".join(violations)


def test_banned_package_not_in_requirements():
    """requirements.txt / pyproject.toml 에 금지 패키지가 없다."""
    req_file = BACKEND_DIR / "requirements.txt"
    if req_file.exists():
        content = req_file.read_text(encoding="utf-8").lower()
        assert BANNED_PACKAGE not in content, (
            f"requirements.txt 에 {BANNED_PACKAGE} 포함됨 ({RULE_ID} 위반)"
        )

    pyproject = BACKEND_DIR / "pyproject.toml"
    if pyproject.exists():
        content = pyproject.read_text(encoding="utf-8").lower()
        assert BANNED_PACKAGE not in content, (
            f"pyproject.toml 에 {BANNED_PACKAGE} 포함됨 ({RULE_ID} 위반)"
        )


def test_banned_package_not_importable():
    """현재 venv 에 금지 패키지가 설치돼 있지 않다."""
    spec = importlib.util.find_spec(BANNED_PACKAGE)
    assert spec is None, (
        f"{BANNED_PACKAGE} 가 venv 에 설치돼 있음 ({RULE_ID} 위반): "
        f"{spec.origin if spec else ''}"
    )
