#!/usr/bin/env bash
# R-struct-4 회귀 테스트 — 배럴의 전량 재export 금지
#
# 배럴은 은닉 장치가 아니라 재노출 장치다. `export *` 로 전부 내보내면
# 호출자가 알아야 할 심볼 수가 그대로여서 인터페이스가 하나도 좁아지지 않는다.
# R-iface 가 "나눠라" 라고 해서 나눈 결과가 이 형태면 폭은 줄지 않는다.
#
# 스펙: docs/superpowers/specs/2026-08-24-interface-width-gate-design.md 축 C
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/assets/hooks/check-component-structure.mjs"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

command -v node >/dev/null 2>&1 || { echo "  - node 없음, 건너뜀"; exit 0; }
[[ -f "$CHECK" ]] || { echo "  ✗ 전제: 검사기 없음 — $CHECK"; exit 1; }
ok "전제: 검사기 존재"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# $1=이름 $2=기대(BLOCK/OK) $3=배럴 상대경로 $4=내용
check() {
  mkdir -p "$(dirname "$3")"
  printf '%s\n' "$4" > "$3"
  local got=OK
  node "$CHECK" "$3" >/dev/null 2>&1 || got=BLOCK
  if [[ "$got" == "$2" ]]; then ok "$1"; else nope "$1 (기대 $2, 실제 $got)"; fi
}

echo "── R-struct-4: 전량 재export 금지 ──"
check "export * from → 차단"       BLOCK "src/lib/index.js"  "export * from './parse.js'"
check "export * as ns from → 차단" BLOCK "src/lib2/index.js" "export * as parse from './parse.js'"
check "선별 export → 통과"         OK    "src/lib3/index.js" "export { parse } from './parse.js'
export { save } from './save.js'"
check "default 재export → 통과"    OK    "src/lib4/index.js" "export { default } from './Btn.vue'"
check "index.ts 도 대상"           BLOCK "src/lib5/index.ts" "export * from './x'"

echo "── 배럴이 아닌 파일은 대상 아님 ──"
check "일반 파일의 export * 는 통과" OK   "src/lib6/util.js"  "export * from './x.js'"

echo "── 오탐 방지 ──"
check "문자열 안의 export * 는 통과" OK   "src/lib7/index.js" "const DOC = \"export * from './x'\"
export { DOC }"
check "주석 안의 export * 는 통과"   OK   "src/lib8/index.js" "// export * from './old.js'
export { a } from './a.js'"

echo "── 메시지 ──"
mkdir -p src/lib9; printf "export * from './x.js'\n" > src/lib9/index.js
MSG="$(node "$CHECK" src/lib9/index.js 2>&1 || true)"
printf '%s' "$MSG" | grep -q "R-struct-4" && ok "메시지에 룰 ID" || nope "메시지에 룰 ID"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
