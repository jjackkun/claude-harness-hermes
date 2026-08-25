#!/usr/bin/env python3
"""파일이 바깥에 약속하는 공개 심볼을 센다 — 인터페이스 폭의 단일 정의.

근거: docs/design-docs/core-beliefs.md#r-iface

왜 모듈로 뺐는가 (2026-08-25):
  폭을 재는 곳이 둘이었다 — `claude-pretooluse-iface-guard.sh`(생성 시점 차단)와
  `claude-posttooluse-size-warn.sh`(편집 시점 델타 경고). 각자 세다 보니 어긋났다:
  후자는 `^export ` grep 이라 **Svelte 에서 한 번도 발화할 수 없었다.**
  실측 — Svelte 200개 표본 중 `^export ` 가 잡힌 파일 0개, `$props()` 사용 177개.
  같은 것을 두 곳에서 재면 반드시 갈라진다. 정의를 하나로 둔다.

사용법 (stdin 으로 내용을 받고 확장자로 언어를 고른다):
  cat foo.svelte        | iface_width.py count .svelte   → 공개 심볼 수
  git show HEAD:foo.py  | iface_width.py count .py       → 같은 방식으로 과거 버전
확장자를 모르면 0 을 출력하고 종료코드 1 — "센 결과 0" 과 "셀 줄 모름" 을 구분한다.
"""

import ast
import re
import sys

SCRIPT_BLOCK = re.compile(r"<script[^>]*>(.*?)</script>", re.S | re.I)
PROPS_DESTRUCTURE = re.compile(
    r"(?:let|const)\s*\{([^}]*)\}\s*=\s*\$props\s*\(\s*\)", re.S)
DEFINE_MACRO = re.compile(
    r"define(?:Props|Expose)\s*(?:<[^>]*>)?\s*\(\s*\{([^}]*)\}", re.S)

SFC_EXT = (".vue", ".svelte")
JS_EXT = (".js", ".jsx", ".ts", ".tsx", ".mjs")


def _py(src):
    """최상위 def/class 중 밑줄로 시작하지 않는 것. 파이썬의 관례가 곧 경계다."""
    tree = ast.parse(src)
    return [n.name for n in tree.body
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
            and not n.name.startswith("_")]


def _js(src):
    """`export ` 로 시작하는 최상위 선언. 재export 는 R-struct-4 관할이다."""
    return [ln for ln in src.split("\n") if ln.startswith("export ")]


def _split_entries(text):
    return [x for x in (part.strip() for part in text.split(",")) if x]


def _sfc(src):
    """SFC 의 공개 폭. `<script>` 안만 본다.

    세 형태를 모두 센다 — 하나만 세면 나머지 형태의 컴포넌트가 폭 0 으로 보인다.
      - `export let/const/...`      Svelte 4 prop, 일반 export
      - `let { a, b } = $props()`   Svelte 5 runes
      - `defineProps`/`defineExpose`  Vue SFC
    마크업은 세지 않는다 — `<template>` 안의 "export let" 은 글자일 뿐이다.
    """
    scripts = "\n".join(SCRIPT_BLOCK.findall(src))
    if not scripts:
        return []
    names = [ln for ln in scripts.split("\n") if ln.strip().startswith("export ")]
    for match in PROPS_DESTRUCTURE.finditer(scripts):
        names += _split_entries(match.group(1))
    for match in DEFINE_MACRO.finditer(scripts):
        names += _split_entries(match.group(1))
    return names


def public_symbols(ext, src):
    """확장자에 맞는 공개 심볼 목록. 셀 줄 모르는 확장자는 None."""
    if ext == ".py":
        return _py(src)
    if ext in JS_EXT:
        return _js(src)
    if ext in SFC_EXT:
        return _sfc(src)
    return None


def main(argv):
    if len(argv) < 3 or argv[1] != "count":
        print("usage: iface_width.py count <ext>  (내용은 stdin)", file=sys.stderr)
        return 2
    try:
        names = public_symbols(argv[2], sys.stdin.read())
    except SyntaxError:
        # 문법이 온전하지 않은 내용은 다른 게이트의 관할이다.
        print(0)
        return 1
    if names is None:
        print(0)
        return 1
    print(len(names))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
