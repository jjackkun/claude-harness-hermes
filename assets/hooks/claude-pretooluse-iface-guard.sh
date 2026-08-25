#!/usr/bin/env bash
# PreToolUse(Write) hook — 새 파일의 인터페이스 폭을 파일이 쓰이기 *전에* 검사한다.
#
# 목적: 책임 분리 판단이 R-size 500줄 한도에서야 일어나는 문제.
# 그 시점의 분리는 늦고 기계적이다 — 다 쓴 파일을 줄 수 경계로 가르면 숨어 있던
# 내부 함수가 파일 밖으로 나오며 공개 심볼로 승격돼 인터페이스가 오히려 넓어진다.
# 본 hook 은 파일이 만들어지기 전에 공개 심볼을 세어 구조 판단을 앞당긴다.
#
# 근거 실측(2026-08-24): hermes-lifecycle.py 는 은닉률 66%(공개 7/비공개 14)인데
# 483줄이라 500 한도에 가장 먼저 걸리고, hermes_loop.py 는 공개 19/비공개 1 로
# 사실상 전부 노출돼 있는데 385줄이라 아무 신호도 받지 않았다. 줄 수는 폭을 잘못 재고 있었다.
#
# 임계 8 의 근거: 저장소 운영 코드 36개의 공개 심볼 분포에서 7이 최빈 고원(4개)이고
# 8부터가 상위 사분위다. 고원 안이 아니라 고원 바로 위에서 자른다.
#
# 차단하는 이유: PreToolUse 는 아직 아무것도 쓰이지 않은 시점이라 오탐 비용이 거의 0 이다.
# 같은 지표라도 커밋 시점에 막으면 완성된 코드의 재구성을 요구해 우회가 상시화된다.
#
# 스펙: docs/superpowers/specs/2026-08-24-interface-width-gate-design.md
# 등록: .claude/settings.json 의 hooks.PreToolUse[matcher="Write"].

set -uo pipefail

MAX_IFACE="${MAX_IFACE:-8}"
[[ -f .harnessrc ]] && source .harnessrc
MAX_IFACE="${MAX_IFACE:-8}"

command -v python3 >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# 판정은 전부 파이썬이 한다 — 공개 심볼 계수는 AST 로 해야 하고(문자열 안의 def 오탐),
# 셸에서 content 를 다루면 개행·따옴표에서 깨진다.
read -r -d '' PYSRC <<'PY' || true
import ast, json, os, re, sys

MAX = int(os.environ.get("MAX_IFACE", "8"))
WAIVER = re.compile(r"R-iface-waiver\s*:")

def public_symbols_py(src):
    """모듈 최상위의 공개 심볼만 센다. main() 은 CLI 진입점이지 인터페이스가 아니다."""
    tree = ast.parse(src)          # 실패는 호출부에서 통과로 처리한다
    names = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            if not node.name.startswith("_") and node.name != "main":
                names.append(node.name)
    return names

def public_symbols_js(src):
    """`export ` 로 시작하는 최상위 선언. 재export(`export {` / `export *`)는 축 C 관할이다."""
    return [ln for ln in src.split("\n") if ln.startswith("export ")]

SCRIPT_BLOCK = re.compile(r"<script[^>]*>(.*?)</script>", re.S | re.I)
PROPS_DESTRUCTURE = re.compile(
    r"(?:let|const)\s*\{([^}]*)\}\s*=\s*\$props\s*\(\s*\)", re.S)
DEFINE_MACRO = re.compile(
    r"define(?:Props|Expose)\s*(?:<[^>]*>)?\s*\(\s*\{([^}]*)\}", re.S)


def public_symbols_sfc(src):
    """SFC(.vue/.svelte)의 공개 폭. `<script>` 안만 본다.

    실측(2026-08-25, 설치된 프로젝트의 SFC 1,063개): 97.9%가 폭 7 이하이고
    7:23개 → 8:6개 로 떨어진다. 파이썬·JS 에서 나온 임계 8 이 독립적으로 재확인됐다.

    세 형태를 모두 센다 — 하나만 세면 나머지 형태의 컴포넌트가 폭 0 으로 보인다.
      - `export let/const/function/...`  (Svelte 4 prop, 일반 export)
      - `let { a, b } = $props()`        (Svelte 5 runes — 이 저장소 규칙이 강제하는 형태)
      - `defineProps({...})` / `defineExpose({...})` (Vue SFC)
    마크업은 세지 않는다. `<template>` 안의 "export let" 은 글자일 뿐 인터페이스가 아니다.
    """
    scripts = "\n".join(SCRIPT_BLOCK.findall(src))
    if not scripts:
        return []

    names = [ln for ln in scripts.split("\n") if ln.strip().startswith("export ")]
    for match in PROPS_DESTRUCTURE.finditer(scripts):
        names += [x for x in (p.strip() for p in match.group(1).split(",")) if x]
    for match in DEFINE_MACRO.finditer(scripts):
        names += [x for x in (p.strip() for p in match.group(1).split(",")) if x]
    return names


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return None
    ti = payload.get("tool_input") or {}
    path = ti.get("file_path") or ""
    content = ti.get("content")
    if not path or not isinstance(content, str):
        return None

    # 신규 파일만 대상. 이미 있는 파일에 대한 Write 는 덮어쓰기이며 델타 신호 관할이다.
    if os.path.exists(path):
        return None

    ext = os.path.splitext(path)[1]
    if ext == ".py":
        counter = public_symbols_py
    elif ext in (".js", ".jsx", ".ts", ".tsx"):
        counter = public_symbols_js
    elif ext in (".vue", ".svelte"):
        counter = public_symbols_sfc
    else:
        return None

    # waiver 는 파일 상단에서만 인정한다 — 아래쪽에 묻어두면 리뷰에서 안 보인다.
    head = "\n".join(content.split("\n")[:20])
    if WAIVER.search(head):
        return None

    try:
        names = counter(content)
    except SyntaxError:
        # 아직 문법이 온전하지 않은 content 로 파일 생성을 막으면 원인 불명 차단이 된다.
        # 문법 오류는 다른 게이트의 관할이다.
        return None

    if len(names) < MAX:
        return None

    priv = 0
    if ext == ".py":
        try:
            for node in ast.parse(content).body:
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                    if node.name.startswith("_"):
                        priv += 1
        except SyntaxError:
            pass
    total = len(names) + priv
    hide = f"{100 * priv // total}%" if total else "0%"

    reason = (
        f"[R-iface] {path} 생성 차단 — 공개 심볼 {len(names)}개 (은닉 {hide}).\n"
        f"  파일을 만들기 전에 답할 것: 이 {len(names)}개가 지는 책임은 몇 개인가?\n"
        f"  2개 이상이면 폴더+배럴 구조를 먼저 만들고 각 파일에 나눠 쓸 것.\n"
        f"  1개라면 파일 상단에 `R-iface-waiver: <근거>` 주석을 남기고 다시 시도할 것.\n"
        f"  외부에서 안 쓰는 것은 밑줄을 붙여 감출 것.\n"
        f"  공개: {', '.join(names[:12])}{' …' if len(names) > 12 else ''}\n"
        f"  근거: docs/design-docs/core-beliefs.md#r-iface"
    )
    return reason

r = main()
if r:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": r,
            # permissionDecision 을 무시하는 구버전에서는 컨텍스트 주입으로 강등된다.
            "additionalContext": r,
        }
    }, ensure_ascii=False))
PY

RESULT="$(printf '%s' "$INPUT" | MAX_IFACE="$MAX_IFACE" python3 -c "$PYSRC" 2>/dev/null)" || true

[[ -n "$RESULT" ]] && printf '%s\n' "$RESULT"
exit 0
