#!/usr/bin/env bash
# R-dep 회귀 테스트 — 모듈 의존 계약
#
# 스펙: docs/superpowers/specs/2026-08-24-module-dependency-contract-design.md
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEP="$ROOT/assets/hooks/depcheck.py"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

[[ -f "$DEP" ]] || { echo "  ✗ 전제: 검사기 없음 — $DEP"; echo "PASS=0 FAIL=1"; exit 1; }
ok "전제: 검사기 존재"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; mkdir -p scripts hooks

run() { if python3 "$DEP" "$@" >/dev/null 2>&1; then echo OK; else echo BLOCK; fi; }
msg() { python3 "$DEP" "$@" 2>&1 || true; }

base_contract() {
cat > .deprc <<'EOF'
tier: 0  scripts/low.py
tier: 1  scripts/mid.py
tier: 2  scripts/high.py
forbid: hooks/*.py -> scripts/*.py
EOF
}
echo "x = 1"                        > scripts/low.py
echo "import low"                   > scripts/mid.py
echo "import mid"                   > scripts/high.py
base_contract

echo "── R-dep-1: 계층 역전 ──"
[[ "$(run scripts/high.py)" == OK ]] && ok "상위→하위 import 는 통과" || nope "상위→하위 import 는 통과"
echo "import high" > scripts/low.py
[[ "$(run scripts/low.py)" == BLOCK ]] && ok "하위→상위 import 는 차단" || nope "하위→상위 import 는 차단"
msg scripts/low.py | grep -q "R-dep-1" && ok "메시지에 R-dep-1" || nope "메시지에 R-dep-1"
echo "x = 1" > scripts/low.py

echo "── 같은 계층은 허용 ──"
cat > .deprc <<'EOF'
tier: 0  scripts/a.py scripts/b.py
EOF
echo "import b" > scripts/a.py; echo "x = 1" > scripts/b.py
[[ "$(run scripts/a.py)" == OK ]] && ok "동일 계층 상호 참조 허용" || nope "동일 계층 상호 참조 허용"

echo "── R-dep-2: 순환 ──"
echo "import a" > scripts/b.py
[[ "$(run scripts/a.py scripts/b.py)" == BLOCK ]] && ok "순환은 차단" || nope "순환은 차단"
msg scripts/a.py scripts/b.py | grep -q "R-dep-2" && ok "메시지에 R-dep-2" || nope "메시지에 R-dep-2"
echo "x = 1" > scripts/b.py

echo "── R-dep-3: 디렉터리 경계 ──"
base_contract
echo "import low" > hooks/h.py
[[ "$(run hooks/h.py)" == BLOCK ]] && ok "훅이 scripts/ 를 import 하면 차단" || nope "훅이 scripts/ 를 import 하면 차단"

echo "── 들여쓴 import 도 잡는다 (정규식 구현이면 실패) ──"
printf 'def go():\n    import low\n    return low\n' > hooks/h.py
[[ "$(run hooks/h.py)" == BLOCK ]] && ok "함수 안 import 도 검출" || nope "함수 안 import 도 검출"

echo "── optional: 선택적 의존 ──"
printf 'try:\n    import low\nexcept ImportError:\n    low = None\n' > hooks/h.py
[[ "$(run hooks/h.py)" == BLOCK ]] && ok "등록 없으면 try/except 라도 차단" || nope "등록 없으면 try/except 라도 차단"
base_contract; echo "optional: hooks/h.py -> low" >> .deprc
[[ "$(run hooks/h.py)" == OK ]] && ok "등록 + 실제 선택적이면 통과" || nope "등록 + 실제 선택적이면 통과"

# 등록이 곧 면제가 되면 optional 한 줄 추가가 우회 경로가 된다.
echo "import low" > hooks/h.py
[[ "$(run hooks/h.py)" == BLOCK ]] && ok "등록돼도 하드 import 면 차단" || nope "등록돼도 하드 import 면 차단"
printf 'try:\n    import low\nexcept ImportError:\n    pass\n' > hooks/h.py
[[ "$(run hooks/h.py)" == BLOCK ]] && ok "fallback 없는 except 는 차단" || nope "fallback 없는 except 는 차단"
printf 'try:\n    import low\nexcept ValueError:\n    low = None\n' > hooks/h.py
[[ "$(run hooks/h.py)" == BLOCK ]] && ok "ImportError 아닌 핸들러는 차단" || nope "ImportError 아닌 핸들러는 차단"

echo "── R-dep-4: 계약에 없는 파일 ──"
base_contract
echo "x = 1" > scripts/newbie.py
[[ "$(run scripts/newbie.py)" == OK ]] && ok "미등록 파일은 차단하지 않음" || nope "미등록 파일은 차단하지 않음"
msg scripts/newbie.py | grep -q "R-dep-4" && ok "미등록 파일은 경고" || nope "미등록 파일은 경고"

echo "── 계약 부재 ──"
rm -f .deprc
OUT="$(msg scripts/high.py)"
[[ "$(run scripts/high.py)" == OK ]] && ok "계약 없으면 통과" || nope "계약 없으면 통과"
# 계약 부재는 고장이 아니라 미설정이다. 매 커밋 경고를 내면 경고 피로로 훅이 꺼진다.
[[ -z "$OUT" ]] && ok "계약 부재는 조용함(경고 피로 방지)" || nope "계약 부재는 조용함 (실제: $OUT)"

echo "── 견고성 ──"
base_contract
printf 'def broken(:\n' > scripts/bad.py
[[ "$(run scripts/bad.py)" == OK ]] && ok "문법 오류는 통과" || nope "문법 오류는 통과"
[[ "$(run scripts/missing.py)" == OK ]] && ok "없는 파일은 통과" || nope "없는 파일은 통과"

echo "── 실제 저장소 검증 ──"
cd "$ROOT"
if [[ -f .deprc ]]; then
  git ls-files '*.py' | grep -v __pycache__ | xargs python3 "$DEP" >/dev/null 2>&1
  [[ "$?" -eq 0 ]] && ok "이 저장소는 자기 계약을 통과한다" || nope "이 저장소는 자기 계약을 통과한다"
else
  nope "이 저장소에 .deprc 가 없다"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
