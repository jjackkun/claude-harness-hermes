#!/usr/bin/env bash
# R-test 게이트: 시험 폴더가 둘이면(tests · backend/tests) 둘 다 한 번에 돈다
# (계획 docs/exec-plans/active/2026-09-30-test-speed-gate.md 목표 3 · Step B2).
#
# 예전에는 `for cand in tests backend/tests; do … break` 라서 첫 폴더만 돌았다.
# terminal-shipping 은 둘 다 있어 루트 tests/(탐침 292개)만 돌고 백엔드 1,465개는 커밋 때
# 한 번도 돌지 않았다(2026-09-30 실측).
#
# 픽스처에 harness 를 실제로 설치하고 .git/hooks/pre-commit 을 돌린다. pytest 는 가짜(받은 인자를 적는다).
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
REGISTRY="$REPO_ROOT/.installed-projects"
cleanup() {
  if [[ -f "$REGISTRY" ]]; then
    grep -vxF "$TMP/p" "$REGISTRY" > "$REGISTRY.tmp$$" || true
    mv "$REGISTRY.tmp$$" "$REGISTRY"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

P="$TMP/p"; mkdir -p "$P"; cd "$P"
git init -q; git config user.email t@t; git config user.name t
bash "$REPO_ROOT/project-claude.sh" . harness >/dev/null 2>&1
git add -A >/dev/null 2>&1; git commit -qm base --no-gpg-sign >/dev/null 2>&1 || git commit -qm base >/dev/null 2>&1

ARGS="$TMP/args"
mkdir -p venv/bin
cat > venv/bin/pytest <<SH
#!/usr/bin/env bash
[[ "\${1:-}" == "--version" ]] && { echo "pytest 8.0.0"; exit 0; }
echo "\$*" > "$ARGS"
echo "3 passed in 0.10s"
SH
chmod +x venv/bin/pytest

run_gate() {   # 새 .py 를 스테이징하고 pre-commit 을 돈다 → 받은 pytest 인자
  : > "$ARGS"
  echo "x = $RANDOM" > "mod_$RANDOM.py"; git add -A . >/dev/null 2>&1
  .git/hooks/pre-commit >/dev/null 2>&1
  cat "$ARGS"
}

echo "== 1. 폴더가 하나뿐이면 그것만"
mkdir -p backend/tests; printf 'def test_a():\n    assert True\n' > backend/tests/test_a.py
assert "backend/tests 만" "backend/tests -q" "$(run_gate)"

echo "== 2. 둘 다 있으면 둘 다 (tests 먼저)"
mkdir -p tests; printf 'def test_b():\n    assert True\n' > tests/test_b.py
assert "tests 와 backend/tests" "tests backend/tests -q" "$(run_gate)"

echo "== 3. tests 만 있으면 그것만"
rm -rf backend/tests
assert "tests 만" "tests -q" "$(run_gate)"

echo; echo "통과 $PASS · 실패 $FAIL"
[[ "$FAIL" -eq 0 ]]
