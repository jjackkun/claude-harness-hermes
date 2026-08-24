#!/usr/bin/env python3
"""R-dep — 모듈 의존 계약 검사.

Usage:
    depcheck.py file.py ...     # 위반이면 exit 1

규칙:
    R-dep-1  하위 tier 가 상위 tier 를 import      (차단)
    R-dep-2  순환 의존                              (차단)
    R-dep-3  forbid: 에 명시된 디렉터리 경계 위반   (차단)
    R-dep-4  계약에 없는 파일                       (경고)

계약 파일 `.deprc` 형식:

    scope: scripts/*.py lib/*.py
    tier: 0  scripts/low.py scripts/other.py
    tier: 1  scripts/mid.py
    forbid:  hooks/*.py -> scripts/*.py
    optional: hooks/h.py -> low

tier 번호가 큰 쪽이 상위다. 같은 tier 안의 상호 참조는 허용한다.
`scope:` 는 계약이 관할하는 범위다. 밖의 파일은 R-dep-4 경고 대상이 아니다 —
외부에서 들여온 스크립트까지 경고하면 노이즈로 게이트가 꺼진다.

왜 AST 인가: 첫 측정을 `^(from|import)` 정규식으로 했다가 **들여쓴 import 를 전부 놓쳤다**.
전체 28개 간선 중 9개(3분의 1)가 빠져 있었고, 그중 하나가 초안의 forbid 규칙을
위반하는 의도된 설계였다. 파이썬의 조건부·지연 import 는 함수나 try 블록 안에
들어가므로 들여쓰기가 기본이다.

왜 import-linter 를 쓰지 않는가: scripts/ 는 파이썬 패키지가 아니다. __init__.py 가 없고
대신 10곳 이상에서 sys.path 를 조작한다. import-linter 는 패키지 경로 기반 계약을
요구하므로 이 구조에 맞지 않는다. 표준 ast 만 쓴다.

선택적 의존: `try/except ImportError` 로 감싸 없어도 동작하는 import 는 `optional:` 로
등록하면 면제된다. 다만 **등록만으로는 부족하고 실제로 선택적인지 검사한다** —
등록이 곧 면제가 되면 `optional:` 한 줄 추가가 우회 경로가 되기 때문이다.

스펙: docs/superpowers/specs/2026-08-24-module-dependency-contract-design.md
"""
from __future__ import annotations

import ast
import fnmatch
import os
import sys

CONTRACT_FILE = ".deprc"


def _module_of(path: str) -> str:
    return os.path.splitext(os.path.basename(path))[0]


def parse_contract(path: str = CONTRACT_FILE) -> dict | None:
    """계약을 읽는다. 파일이 없으면 None — 호출부가 '조용히 넘기지 않고' 알린다."""
    if not os.path.exists(path):
        return None
    tiers: dict[str, int] = {}
    scope: list[str] = []
    forbids: list[tuple[str, str]] = []
    optionals: set[tuple[str, str]] = set()
    for raw in open(path, encoding="utf-8"):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        key, _, rest = line.partition(":")
        key, rest = key.strip(), rest.strip()
        if key == "scope":
            scope.extend(rest.split())
        elif key == "tier":
            num, _, files = rest.partition(" ")
            for f in files.split():
                tiers[f] = int(num)
        elif key in ("forbid", "optional"):
            src, _, dst = rest.partition("->")
            pair = (src.strip(), dst.strip())
            (forbids if key == "forbid" else optionals).append(pair) \
                if key == "forbid" else optionals.add(pair)
    return {"tiers": tiers, "forbids": forbids, "optionals": optionals, "scope": scope}


def collect_imports(path: str) -> list[tuple[str, bool]]:
    """(모듈명, 선택적인가) 목록. 읽기·파싱 실패는 빈 목록 — 다른 게이트의 관할이다."""
    try:
        tree = ast.parse(open(path, encoding="utf-8").read())
    except (OSError, SyntaxError, UnicodeDecodeError):
        return []

    # try 본문 안의 import 중, ImportError 를 잡고 fallback 을 두는 것만 선택적이다.
    optional_nodes: set[int] = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.Try):
            continue
        # 핸들러가 ImportError 를 잡고, **fallback 을 실제로 두는** 경우만 선택적이다.
        # `except ImportError: pass` 는 이름을 정의하지 않아 뒤 코드가 NameError 로 죽는다 —
        # "없어도 동작한다" 가 성립하지 않으므로 선택적 의존이 아니다.
        guards_import = any(
            h.type is not None
            and "ImportError" in ast.dump(h.type)
            and any(not isinstance(st, ast.Pass) for st in h.body)
            for h in node.handlers
        )
        if not guards_import:
            continue
        for stmt in node.body:
            for sub in ast.walk(stmt):
                if isinstance(sub, (ast.Import, ast.ImportFrom)):
                    optional_nodes.add(id(sub))

    out = []
    for node in ast.walk(tree):
        names = []
        if isinstance(node, ast.Import):
            names = [a.name.split(".")[0] for a in node.names]
        elif isinstance(node, ast.ImportFrom) and node.module:
            names = [node.module.split(".")[0]]
        for name in names:
            out.append((name, id(node) in optional_nodes))
    return out


def _cycles(edges: dict[str, set[str]]) -> list[list[str]]:
    """되돌아오는 간선을 찾는다. 하나만 보고해도 충분하다 — 고치면 다시 돈다."""
    found, state = [], {}

    def walk(node: str, stack: list[str]) -> None:
        state[node] = 1
        for nxt in sorted(edges.get(node, ())):
            if state.get(nxt) == 1:
                found.append(stack[stack.index(nxt):] + [nxt])
            elif not state.get(nxt):
                walk(nxt, stack + [nxt])
        state[node] = 2

    for node in sorted(edges):
        if not state.get(node):
            walk(node, [node])
    return found


def _check(paths: list[str], contract: dict) -> tuple[list[str], list[str]]:
    tiers, forbids, optionals = contract["tiers"], contract["forbids"], contract["optionals"]
    scope = contract["scope"]
    by_module = {_module_of(f): f for f in tiers}
    violations, warnings = [], []
    edges: dict[str, set[str]] = {}

    for path in paths:
        imports = collect_imports(path)
        if not imports and not os.path.exists(path):
            continue
        in_scope = not scope or any(fnmatch.fnmatch(path, p) for p in scope)
        if in_scope and path not in tiers and os.path.exists(path):
            warnings.append(
                f"[R-dep-4] {path} — 계약({CONTRACT_FILE})에 tier 가 없다.\n"
                f"  → 이 파일이 어느 계층에 속하는지 정해 계약에 추가할 것."
            )
        for mod, is_optional in imports:
            target = by_module.get(mod)
            if target is None:
                continue
            edges.setdefault(path, set()).add(target)

            exempt = (path, mod) in optionals and is_optional
            for src_pat, dst_pat in forbids:
                if fnmatch.fnmatch(path, src_pat) and fnmatch.fnmatch(target, dst_pat):
                    if exempt:
                        continue
                    extra = ""
                    if (path, mod) in optionals and not is_optional:
                        extra = ("\n  → optional: 로 등록돼 있으나 실제로 선택적이지 않다. "
                                 "try/except ImportError + fallback 할당이 필요하다.")
                    violations.append(
                        f"[R-dep-3] {path} → {mod} — 금지된 경계 ({src_pat} -> {dst_pat}).{extra}\n"
                        f"  근거: docs/design-docs/core-beliefs.md#r-dep"
                    )
            if path in tiers and target in tiers and tiers[path] < tiers[target]:
                violations.append(
                    f"[R-dep-1] {path}(tier {tiers[path]}) → {mod}(tier {tiers[target]}) — 계층 역전.\n"
                    f"  → 하위 계층은 상위를 알 수 없다. 공통 부분을 더 낮은 tier 로 내릴 것.\n"
                    f"  근거: docs/design-docs/core-beliefs.md#r-dep"
                )

    for cycle in _cycles(edges):
        violations.append(
            "[R-dep-2] 순환 의존: " + " → ".join(cycle) + "\n"
            "  → 공통 부분을 더 낮은 계층의 새 모듈로 뽑아낼 것.\n"
            "  근거: docs/design-docs/core-beliefs.md#r-dep"
        )
    return violations, warnings


def _main(argv: list[str]) -> int:
    contract = parse_contract()
    if contract is None:
        # 계약 파일 부재 = **이 기능을 켜지 않았다**. 조용히 통과시킨다.
        #
        # 스펙 초안은 R-test 사고("게이트가 죽은 줄 모른다")를 이유로 여기서도 경고하기로 했으나,
        # 두 상황은 다르다. R-test 는 *켜져 있는데* 아무것도 안 막으면서 통과 표시를 냈다.
        # 여기서는 사용자가 계약을 만든 적이 없다 — 고장이 아니라 미설정이다.
        # 계약이 없는 프로젝트에 매 커밋 경고를 내면 경고 피로로 훅 자체가 꺼진다
        # (size-warn 이 같은 이유로 겹치는 경고를 억제한다).
        #
        # "죽은 줄 모르는" 위험은 설치 시점에 안내하는 쪽으로 옮긴다.
        return 0
    violations, warnings = _check(argv, contract)
    if warnings:
        sys.stderr.write("\n" + "\n\n".join(warnings) + "\n")
    if violations:
        sys.stderr.write("\n" + "\n\n".join(violations) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
