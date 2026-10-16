#!/usr/bin/env bash
# R-struct 설치·연결 회귀 시험 — 임시 저장소에 실제 설치기로 깔고 pre-commit 을 돌린다.
#
# 단언:
#   1. 설치 → .git/hooks/ 에 lib/struct_files.sh 목록 전부, svelte·python 위반 커밋 차단, 고치면 통과
#   2. 부분 설치(엔진 파일 하나 삭제 · JSON 깨기) → 차단 아님, gate-events 에 R-struct skipped (G7)
#   3. 옛 pre-commit + 새 파일 → Vue 판정은 그대로 차단, 새 언어(svelte)는 미검사(알려진 한계)
#   4. 새 pre-commit + 옛 파일(check-structure.mjs 없음) → skipped, 차단 아님
#   5. 기준선 → 기존 위반 등록 후 통과, 새 위반 차단
# 계획: docs/exec-plans/active/2026-10-16-language-neutral-structure-gate.md Step 6
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0   # 외부 도구 다운로드 끔(네트워크 0)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
command -v node >/dev/null 2>&1 || { echo "  - node 없음, 건너뜀"; exit 0; }

TMP=$(mktemp -d)
export HOME="$TMP/fakehome"; mkdir -p "$HOME"
REGISTRY="$ROOT/.installed-projects"
cleanup() {
  if [[ -f "$REGISTRY" ]]; then
    grep -v "^${TMP}\(/\|$\)" "$REGISTRY" > "$REGISTRY.tmp$$" 2>/dev/null || true
    [[ -f "$REGISTRY.tmp$$" ]] && mv "$REGISTRY.tmp$$" "$REGISTRY"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

cd "$TMP"
git init -q
git config user.email "harness-test@example.com"
git config user.name "harness-test"
bash "$ROOT/project-claude.sh" . harness >/dev/null 2>&1
git add -A && git commit -qm "harness install" >/dev/null 2>&1 || true

# shellcheck source=../lib/struct_files.sh
source "$ROOT/lib/struct_files.sh"
EVENTS=".harness/gate-events.jsonl"
last_struct() { grep '"R-struct"' "$EVENTS" 2>/dev/null | tail -1 | grep -oE '"verdict": *"[a-z]+"' | grep -oE '[a-z]+"$' | tr -d '"'; }
hook() { OUT=$(.git/hooks/pre-commit 2>&1); RC=$?; }

echo "── 1. 설치 ──"
missing=0
for f in "${HARNESS_STRUCT_FILES[@]}"; do [[ -f ".git/hooks/$f" ]] || { missing=1; echo "    없음: $f"; }; done
(( missing == 0 )) && ok "목록 ${#HARNESS_STRUCT_FILES[@]}개 전부 .git/hooks/ 에 있음" || nope "목록 일부 누락"
# 목록 자체에서 빠진 엔진 파일은 위 단언이 못 잡는다 — 원본 폴더와 목록을 대조한다
ON_DISK=$(cd "$ROOT/assets/hooks" && ls check-structure.mjs check-component-structure.mjs structure-* | sort)
IN_LIST=$(printf '%s\n' "${HARNESS_STRUCT_FILES[@]}" | sort)
[[ "$ON_DISK" == "$IN_LIST" ]] && ok "lib/struct_files.sh 목록 == assets/hooks/ 의 구조 검사기 파일" \
  || nope "목록과 원본 불일치: $(diff <(echo "$ON_DISK") <(echo "$IN_LIST") | grep '^[<>]' | tr '\n' ' ')"

mkdir -p src/lib/features/cart app/features/cart
echo '<div/>' > src/lib/features/cart/Cart.svelte
echo 'def checkout(): pass' > app/features/cart/service.py
git add src app
hook
[[ "$OUT" == *"R-struct-5"* && "$(last_struct)" == block ]] && ok "svelte·python 배럴 없음 → R-struct 차단" \
  || nope "차단 기대 (verdict=$(last_struct))"
[[ "$OUT" == *"src/lib/features/cart/"* && "$OUT" == *"app/features/cart/"* ]] && ok "두 언어 모두 메시지에" || nope "두 언어 메시지"

echo "export { default as Cart } from './Cart.svelte'" > src/lib/features/cart/index.ts
echo 'from .service import checkout' > app/features/cart/__init__.py
git add src app
hook
[[ "$OUT" != *"폴더·배럴 구조 위반"* && "$(last_struct)" != block ]] && ok "배럴을 두면 R-struct 통과 (verdict=$(last_struct))" \
  || nope "고친 뒤에도 차단"
rm src/lib/features/cart/index.ts; git add -A src   # 다음 단언용 위반 상태로 되돌림

echo "── 2. 부분 설치 ──"
mv .git/hooks/structure-rule-barrel.mjs "$TMP/barrel.bak"
hook
[[ "$OUT" != *"폴더·배럴 구조 위반"* && "$(last_struct)" == skipped ]] && ok "엔진 파일 삭제 → skipped, 차단 아님" \
  || nope "엔진 파일 삭제 (verdict=$(last_struct))"
mv "$TMP/barrel.bak" .git/hooks/structure-rule-barrel.mjs
cp .git/hooks/structure-langs.json "$TMP/langs.bak"; echo '{broken' > .git/hooks/structure-langs.json
hook
[[ "$OUT" != *"폴더·배럴 구조 위반"* && "$(last_struct)" == skipped ]] && ok "설정표 JSON 깨짐 → skipped, 차단 아님" \
  || nope "JSON 깨짐 (verdict=$(last_struct))"
cp "$TMP/langs.bak" .git/hooks/structure-langs.json

echo "── 3. 옛 pre-commit + 새 파일 ──"
cp .git/hooks/pre-commit "$TMP/new-pre-commit"
git -C "$ROOT" show ff815bc:assets/hooks/pre-commit.sh > .git/hooks/pre-commit
mkdir -p src/components; echo '<template><b/></template>' > src/components/Btn.vue; git add src
hook
[[ "$OUT" == *"R-struct-1"* ]] && ok "옛 pre-commit: Vue 위반은 그대로 차단" || nope "옛 pre-commit Vue 차단"
[[ "$OUT" != *"R-struct-5"* ]] && ok "옛 pre-commit: svelte 는 미검사 (전파 전 구간의 알려진 한계)" || nope "옛 pre-commit 이 svelte 를 봄"
git rm -q --cached src/components/Btn.vue; rm src/components/Btn.vue
cp "$TMP/new-pre-commit" .git/hooks/pre-commit

echo "── 4. 새 pre-commit + 옛 파일 ──"
mv .git/hooks/check-structure.mjs "$TMP/engine.bak"
hook
[[ "$OUT" != *"폴더·배럴 구조 위반"* && "$(last_struct)" == skipped ]] && ok "check-structure.mjs 없음 → skipped" \
  || nope "엔진 없음 (verdict=$(last_struct))"
mv "$TMP/engine.bak" .git/hooks/check-structure.mjs

echo "── 5. 기준선 ──"
node .git/hooks/check-structure.mjs --update-baseline >/dev/null
git add .structbaseline
hook
[[ "$(last_struct)" != block ]] && ok "기존 위반을 기준선에 넣으면 통과 (verdict=$(last_struct))" || nope "기준선 후에도 차단"
mkdir -p src/lib/features/wish; echo '<div/>' > src/lib/features/wish/Wish.svelte; git add src
hook
[[ "$OUT" == *"src/lib/features/wish/"* && "$(last_struct)" == block ]] && ok "기준선에 없는 새 위반은 차단" || nope "새 위반 차단"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
