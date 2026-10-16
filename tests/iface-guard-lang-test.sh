#!/usr/bin/env bash
# R-iface 언어 확장 회귀 시험 — 새 파일의 공개 심볼 8개는 차단, 7개(+비공개 3개)는 통과.
#
# 언어: java kotlin csharp php swift go rust dart. ruby 는 공개 판정 규칙이 없어 제외(계획 §7).
# 비공개 3개를 늘 함께 넣는다 — 공개만 세는지(비공개를 세지 않는지)를 같이 잰다.
# 계획: docs/exec-plans/active/2026-10-16-language-neutral-structure-gate.md G6
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/assets/hooks/claude-pretooluse-iface-guard.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
command -v python3 >/dev/null 2>&1 || { echo "  - python3 없음, 건너뜀"; exit 0; }
[[ -f "$HOOK" ]] || { echo "  ✗ 전제: 훅 없음 — $HOOK"; echo "PASS=0 FAIL=1"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# $1=언어 $2=공개 수 → 그 언어 소스를 표준출력에 (비공개 3개 포함)
gen() {
  python3 - "$1" "$2" <<'PY'
import sys
lang, n = sys.argv[1], int(sys.argv[2])
pub = [f"a{i}" for i in range(n)]
priv = ["p0", "p1", "p2"]
L = []
if lang == "java":
    L.append("public class Foo {")
    L += [f"    public int {x}() {{ return 1; }}" for x in pub[1:]]
    L += [f"    private int {x}() {{ return 1; }}" for x in priv]
    L.append("}")
elif lang == "kotlin":
    L.append("class Foo {")
    L += [f"    fun {x}(): Int {{\n        val local = 1\n        return local\n    }}" for x in pub[1:]]
    L += [f"    private fun {x}() = 1" for x in priv]
    L.append("}")
elif lang == "csharp":
    L.append("public class Foo {")
    L += [f"    public int {x.upper()}() => 1;" for x in pub[1:]]
    L += [f"    private int {x.upper()}() => 1;" for x in priv]
    L.append("}")
elif lang == "php":
    L.append("<?php\nclass Foo {")
    L += [f"    public function {x}() {{ return 1; }}" for x in pub[1:]]
    L += [f"    private function {x}() {{ return 1; }}" for x in priv]
    L.append("}")
elif lang == "swift":
    L.append("public struct Foo {")
    L += [f"    public func {x}() -> Int {{ 1 }}" for x in pub[1:]]
    L += [f"    func {x}() -> Int {{ 1 }}" for x in priv]
    L.append("}")
elif lang == "go":
    L.append("package foo\n\ntype Foo struct{}")
    L += [f"func (f *Foo) {x.capitalize()}() int {{ return 1 }}" for x in pub[1:]]
    L += [f"func {x}() int {{ return 1 }}" for x in priv]
elif lang == "rust":
    L.append("pub struct Foo;")
    L += [f"pub fn {x}() -> i32 {{ 1 }}" for x in pub[1:]]
    L += [f"fn {x}() -> i32 {{ 1 }}" for x in priv[:2]] + ["pub(crate) fn p2() -> i32 { 1 }", "pub use crate::x::Y;"]
elif lang == "dart":
    L.append("class Foo {}")
    L += [f"int {x}() => 1;" for x in pub[1:]]
    L += [f"int _{x}() => 1;" for x in priv]
print("\n".join(L))
PY
}

payload() {  # $1=file_path  $2=content
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}))' "$1" "$2"
}
verdict() {
  local out; out="$(cd "$WORK" && bash "$HOOK" 2>/dev/null)" || true
  printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' && echo DENY || echo ALLOW
}

for spec in java:Foo.java kotlin:Foo.kt csharp:Foo.cs php:Foo.php swift:Foo.swift go:foo.go rust:foo.rs dart:foo.dart; do
  lang="${spec%%:*}"; file="$WORK/new/${spec#*:}"
  got8=$(payload "$file" "$(gen "$lang" 8)" | verdict)
  got7=$(payload "$file" "$(gen "$lang" 7)" | verdict)
  [[ "$got8" == DENY ]] && ok "$lang 공개 8 → 차단" || nope "$lang 공개 8 → 기대 DENY / 실제 $got8"
  [[ "$got7" == ALLOW ]] && ok "$lang 공개 7 (+비공개 3) → 통과" || nope "$lang 공개 7 → 기대 ALLOW / 실제 $got7"
done

echo "── 오탐 방지 ──"
KT_TOP="$(printf 'package foo\n'; for i in 0 1 2 3 4 5 6; do printf 'fun a%s(): Int {\n    val local%s = 1\n    var other%s = 2\n    return local%s\n}\n' $i $i $i $i; done)"
[[ "$(payload "$WORK/new/Top.kt" "$KT_TOP" | verdict)" == ALLOW ]] && ok "kotlin 최상위 함수 7개 — 몸체의 지역 val/var 는 세지 않음" \
  || nope "kotlin 지역 선언을 공개로 셈"
DART_LIB="$(printf 'library shop;\npart of shop;\nimport "a.dart";\nexport "b.dart" show B;\n'; for i in 0 1 2 3 4 5 6; do printf 'int a%s() => 1;\n' $i; done)"
[[ "$(payload "$WORK/new/lib.dart" "$DART_LIB" | verdict)" == ALLOW ]] && ok "dart library·part·import·export 줄은 세지 않음" \
  || nope "dart 지시문 줄을 공개로 셈"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
