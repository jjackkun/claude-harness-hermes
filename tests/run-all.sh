#!/usr/bin/env bash
# tests/run-all.sh — 전체 테스트 러너
#
# 실행 순서:
#   1. 정적 검사: bash -n (셸 전수) + python3 -m py_compile (scripts/*.py, lib/*.py)
#   2. 무결성 검사: preset-integrity-test.sh, sync-plugins.sh --check
#   3. 통합 테스트: windows-helpers / harness-hooks-smoke / windows-smoke /
#                   hermes-pipeline / uninstall-roundtrip
#
# 각 테스트는 서브셸로 실행되어 한 테스트의 실패가 러너를 죽이지 않는다.
#
# 환경변수:
#   SKIP_INTERACTIVE=1  — 외부 의존(fzf 등)·대화형 입력이 필요한 테스트를 SKIP
#                          (CI 기본. 현재 모든 테스트가 비대화형이라 목록은 비어 있음)
#   SKIP_TESTS=a.sh,b.sh — 쉼표 구분으로 특정 테스트 파일명 SKIP
#
# 실행: bash tests/run-all.sh
# 종료 코드: 0 = 전체 통과, 1 = 1개 이상 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'

TOTAL=0; PASSED=0; FAILED=0; SKIPPED=0
declare -a FAILED_NAMES=()

# fzf 등 외부 도구나 대화형 입력이 필요한 테스트 파일명 (SKIP_INTERACTIVE=1 시 건너뜀)
INTERACTIVE_TESTS=""

_is_skipped() {
  local name="$1"
  if [[ "${SKIP_INTERACTIVE:-0}" == "1" ]] && [[ ",$INTERACTIVE_TESTS," == *",$name,"* ]]; then
    return 0
  fi
  if [[ -n "${SKIP_TESTS:-}" ]] && [[ ",${SKIP_TESTS}," == *",$name,"* ]]; then
    return 0
  fi
  return 1
}

run_step() { # run_step <이름> <명령...>
  local name="$1"; shift
  TOTAL=$((TOTAL+1))
  if _is_skipped "$name"; then
    echo -e "${YELLOW}── SKIP: $name ──${RESET}"
    SKIPPED=$((SKIPPED+1)); TOTAL=$((TOTAL-1))
    return 0
  fi
  echo -e "${BOLD}── RUN: $name ──${RESET}"
  if ( "$@" ); then
    echo -e "${GREEN}── PASS: $name ──${RESET}"
    PASSED=$((PASSED+1))
  else
    echo -e "${RED}── FAIL: $name ──${RESET}"
    FAILED=$((FAILED+1))
    FAILED_NAMES+=("$name")
  fi
  echo ""
}

# ── 1. 정적 검사 ──────────────────────────────────────────────────────────────

bash_syntax_check() {
  local rc=0 f
  while IFS= read -r f; do
    if ! bash -n "$f" 2>/dev/null; then
      echo "  ✗ bash -n 실패: ${f#$REPO_ROOT/}"
      bash -n "$f" 2>&1 | sed 's/^/    /'
      rc=1
    fi
  done < <(find "$REPO_ROOT" -name "*.sh" -type f \
             -not -path "*/.git/*" \
             -not -path "$REPO_ROOT/bin/*" \
             -not -path "*/node_modules/*" \
             -not -path "*/.claude/worktrees/*")
  [[ $rc -eq 0 ]] && echo "  ✓ 셸 스크립트 전수 bash -n 통과"
  return $rc
}

python_compile_check() {
  local rc=0 f
  while IFS= read -r f; do
    if ! python3 -m py_compile "$f" 2>/dev/null; then
      echo "  ✗ py_compile 실패: ${f#$REPO_ROOT/}"
      python3 -m py_compile "$f" 2>&1 | sed 's/^/    /'
      rc=1
    fi
  done < <(find "$REPO_ROOT/scripts" "$REPO_ROOT/lib" -maxdepth 1 -name "*.py" -type f)
  [[ $rc -eq 0 ]] && echo "  ✓ scripts/*.py + lib/*.py 전수 py_compile 통과"
  return $rc
}

run_step "bash -n (셸 문법 전수)" bash_syntax_check
run_step "python3 -m py_compile (scripts + lib)" python_compile_check

# ── 2. 무결성 검사 ────────────────────────────────────────────────────────────

run_step "preset-integrity-test.sh" bash "$TESTS_DIR/preset-integrity-test.sh"
run_step "sync-plugins.sh --check" bash "$REPO_ROOT/scripts/sync-plugins.sh" --check

# ── 3. 통합 테스트 ────────────────────────────────────────────────────────────

for t in \
  windows-helpers-test.sh \
  harness-hooks-smoke.sh \
  windows-smoke.sh \
  hermes-pipeline-test.sh \
  hermes-loop-test.sh \
  hermes-redact-test.sh \
  hermes-dream-test.sh \
  hermes-recall-measurement-test.sh \
  uninstall-roundtrip-test.sh \
  memory-symlink-roundtrip-test.sh
do
  run_step "$t" bash "$TESTS_DIR/$t"
done

# ── 결과 집계 ─────────────────────────────────────────────────────────────────

echo -e "${BOLD}━━━ 전체 결과 ━━━${RESET}"
echo -e "  실행: $TOTAL  ${GREEN}통과: $PASSED${RESET}  ${RED}실패: $FAILED${RESET}  ${YELLOW}스킵: $SKIPPED${RESET}"
if [[ $FAILED -gt 0 ]]; then
  echo -e "  ${RED}실패 목록:${RESET}"
  for name in "${FAILED_NAMES[@]}"; do
    echo "    - $name"
  done
  exit 1
fi
exit 0
