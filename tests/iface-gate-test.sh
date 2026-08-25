#!/usr/bin/env bash
# R-iface 게이트 회귀 테스트 — PreToolUse(Write) 인터페이스 폭 차단
#
# 스펙: docs/superpowers/specs/2026-08-24-interface-width-gate-design.md
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/assets/hooks/claude-pretooluse-iface-guard.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 전제 — 훅이 없으면 ALLOW 단언이 공허하게 통과한다(훅 부재와 훅 허용을 구분 못 함).
# 여기서 멈춰야 "테스트는 다 통과하는데 게이트는 없는" 상태를 만들지 않는다.
if [[ ! -f "$HOOK" ]]; then
  echo "  ✗ 전제: 훅이 없다 — $HOOK"
  echo "PASS=0 FAIL=1"
  exit 1
fi
ok "전제: 훅 존재"

# 훅에 넘길 PreToolUse 페이로드를 만든다.
payload() {  # $1=file_path  $2=content
  python3 -c '
import json, sys
print(json.dumps({"tool_name": "Write",
                  "tool_input": {"file_path": sys.argv[1], "content": sys.argv[2]}}))' "$1" "$2"
}

# 훅을 돌리고 차단 여부를 판정한다. 차단이면 "DENY", 아니면 "ALLOW".
verdict() {  # stdin = payload
  local out input
  input="$(cat)"   # 파이프를 끝까지 비운다 — 훅이 stdin 을 안 읽어도 BrokenPipe 가 안 난다
  out="$(cd "$WORK" && printf '%s' "$input" | bash "$HOOK" 2>/dev/null)" || true
  if printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    echo "DENY"
  else
    echo "ALLOW"
  fi
}

check() {  # $1=이름 $2=기대(DENY/ALLOW) $3=file_path $4=content
  local got
  got="$(payload "$3" "$4" | verdict)"
  if [[ "$got" == "$2" ]]; then ok "$1"; else nope "$1 (기대 $2, 실제 $got)"; fi
}

# ── 픽스처 ────────────────────────────────────────────────────────
gen_py() {  # $1=공개 개수  $2=비공개 개수
  local i
  for ((i=1; i<=$1; i++)); do printf 'def pub%d():\n    return %d\n\n' "$i" "$i"; done
  for ((i=1; i<=$2; i++)); do printf 'def _priv%d():\n    return %d\n\n' "$i" "$i"; done
}
gen_js() {  # $1=공개 개수
  local i
  for ((i=1; i<=$1; i++)); do printf 'export function pub%d() { return %d }\n' "$i" "$i"; done
}

echo "── 임계 (공개 심볼 8) ──"
check "공개 8개 → 차단"            DENY  "$WORK/a.py" "$(gen_py 8 0)"
check "공개 7개 → 통과"            ALLOW "$WORK/b.py" "$(gen_py 7 0)"
check "공개 12개 → 차단"           DENY  "$WORK/c.py" "$(gen_py 12 0)"

echo "── 비공개는 폭이 아니다 ──"
check "공개 7 + 비공개 9 → 통과"   ALLOW "$WORK/d.py" "$(gen_py 7 9)"

echo "── main() 제외 ──"
check "공개 7 + main → 통과"       ALLOW "$WORK/e.py" "$(gen_py 7 0)
def main():
    return 0"

echo "── 신규 파일만 대상 ──"
printf 'x = 1\n' > "$WORK/exists.py"
check "이미 존재하는 파일 → 통과"  ALLOW "$WORK/exists.py" "$(gen_py 12 0)"

echo "── waiver ──"
check "waiver 주석 → 통과"         ALLOW "$WORK/f.py" "# R-iface-waiver: 완전 열거 상태 머신이라 한 책임이다
$(gen_py 9 0)"

echo "── AST 구현 (정규식이면 실패하는 케이스) ──"
check "문자열 안의 def 는 안 센다" ALLOW "$WORK/g.py" 'DOC = """
def a(): pass
def b(): pass
def c(): pass
def d(): pass
def e(): pass
def f(): pass
def g(): pass
def h(): pass
"""
def only_one():
    return DOC'
check "문법 오류 → 통과"           ALLOW "$WORK/h.py" "def broken(:
    this is not python"

echo "── 대상 확장자 ──"
check "JS export 8개 → 차단"       DENY  "$WORK/i.js" "$(gen_js 8)"
check "JS export 7개 → 통과"       ALLOW "$WORK/j.js" "$(gen_js 7)"
check "대상 아닌 확장자 → 통과"    ALLOW "$WORK/k.md" "$(gen_py 12 0)"

echo "── 차단 메시지 ──"
PL="$(payload "$WORK/z.py" "$(gen_py 9 0)")"
MSG="$(cd "$WORK" && printf '%s' "$PL" | bash "$HOOK" 2>/dev/null)" || true
if printf '%s' "$MSG" | grep -q "R-iface"; then ok "메시지에 룰 ID"; else nope "메시지에 룰 ID"; fi
if printf '%s' "$MSG" | grep -q "core-beliefs.md#r-iface"; then ok "메시지에 근거 링크"; else nope "메시지에 근거 링크"; fi
if printf '%s' "$MSG" | grep -q "9"; then ok "메시지에 실제 심볼 수"; else nope "메시지에 실제 심볼 수"; fi

# ── SFC (.vue / .svelte) ────────────────────────────────────────────────
# 실측 근거(2026-08-25): 설치된 프로젝트의 SFC 1,063개 중 97.9%가 폭 7 이하이고
# 7:23개 → 8:6개 로 떨어진다. 파이썬·JS 에서 나온 임계 8 이 독립적으로 재확인됐다.
echo "-- Svelte --"
SV7=""; for i in 1 2 3 4 5 6 7; do SV7+="  export let p$i;"$'\n'; done
SV8="$SV7  export let p8;"$'\n'
[[ "$(payload "$WORK/A.svelte" "<script>"$'\n'"$SV8</script>"$'\n'"<div/>" | verdict)" == DENY ]] \
  && ok "svelte export let 8개 → 차단" || nope "svelte export let 8개 → 차단"
[[ "$(payload "$WORK/B.svelte" "<script>"$'\n'"$SV7</script>"$'\n'"<div/>" | verdict)" == ALLOW ]] \
  && ok "svelte export let 7개 → 통과" || nope "svelte export let 7개 → 통과"

# Svelte 5 runes — 사용자 규칙이 runes 를 강제하므로 export let 만 세면 폭이 0으로 보인다.
RUNE8='<script>
  let { a, b, c, d, e, f, g, h } = $props();
</script>
<div/>'
[[ "$(payload "$WORK/C.svelte" "$RUNE8" | verdict)" == DENY ]] \
  && ok "svelte props 구조분해 8개 → 차단" || nope "svelte props 구조분해 8개 → 차단"
RUNE7='<script>
  let { a, b, c, d, e, f, g } = $props();
</script>
<div/>'
[[ "$(payload "$WORK/D.svelte" "$RUNE7" | verdict)" == ALLOW ]] \
  && ok "svelte props 7개 → 통과" || nope "svelte props 7개 → 통과"

echo "-- Vue --"
VUE8='<script setup>
defineProps({ a: 1, b: 1, c: 1, d: 1, e: 1, f: 1, g: 1, h: 1 })
</script>
<template><div/></template>'
[[ "$(payload "$WORK/E.vue" "$VUE8" | verdict)" == DENY ]] \
  && ok "vue defineProps 8개 → 차단" || nope "vue defineProps 8개 → 차단"
VUE7='<script setup>
defineProps({ a: 1, b: 1, c: 1, d: 1, e: 1, f: 1, g: 1 })
</script>
<template><div/></template>'
[[ "$(payload "$WORK/F.vue" "$VUE7" | verdict)" == ALLOW ]] \
  && ok "vue defineProps 7개 → 통과" || nope "vue defineProps 7개 → 통과"

echo "-- SFC 견고성 --"
# 마크업에 있는 단어는 인터페이스가 아니다. <script> 밖은 세지 않는다.
MARKUP='<template>
  <p>export let a; export let b; export let c; export let d;</p>
  <p>export let e; export let f; export let g; export let h;</p>
</template>'
[[ "$(payload "$WORK/G.vue" "$MARKUP" | verdict)" == ALLOW ]] \
  && ok "마크업 안의 export 문자열은 세지 않는다" || nope "마크업 안의 export 문자열은 세지 않는다"
[[ "$(payload "$WORK/H.svelte" "<div>markup only</div>" | verdict)" == ALLOW ]] \
  && ok "script 없는 SFC 는 통과" || nope "script 없는 SFC 는 통과"
[[ "$(payload "$WORK/I.svelte" "<!-- R-iface-waiver: 한 책임이다 -->"$'\n'"<script>"$'\n'"$SV8</script>" | verdict)" == ALLOW ]] \
  && ok "SFC 도 waiver 가 통한다" || nope "SFC 도 waiver 가 통한다"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
