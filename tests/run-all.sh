#!/usr/bin/env bash
# tests/run-all.sh — 전체 테스트 러너
#
# 실행 순서:
#   1. 정적 검사: 고아 테스트 검사(tests/*-test.sh · *smoke*.sh 가 목록에 없으면 실패) +
#                 bash -n (셸 전수) + python3 -m py_compile (scripts/*.py, lib/*.py)
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
#       bash tests/run-all.sh --check-orphans   — 고아 테스트 검사만 (종료 코드 0/1)
# 종료 코드: 0 = 전체 통과, 1 = 1개 이상 실패

set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0   # 개별 테스트도 같은 값을 갖지만 run-all 에서 한 번 더 못 박는다

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

# 러너에 등록된 테스트 목록. tests/ 의 *-test.sh · *smoke*.sh 는 반드시 여기(또는 §2)에
# 있어야 한다 — 없으면 아래 orphan_test_check 가 러너를 빨강으로 만든다.
REGISTERED_TESTS=(
  windows-helpers-test.sh
  plan-state-test.sh
  iface-gate-test.sh
  plan-declare-gate-test.sh
  plan-stale-completion-test.sh
  doc-counts-gate-test.sh
  design-cover-gate-test.sh
  output-budget-test.sh
  gate-declaration-coverage-test.sh
  struct-barrel-test.sh
  complexity-gate-test.sh
  cx-baseline-distribution-test.sh
  dep-contract-test.sh
  pipe-gate-test.sh
  gate-event-test.sh
  gate-report-test.sh
  gate-instrumentation-test.sh
  gate-precommit-instrumentation-test.sh
  r5-detection-test.sh
  coverage-probe-test.sh
  mutation-probe-test.sh
  mutation-trigger-test.sh
  doc-gardening-drift-test.sh
  claude-md-skill-index-test.sh
  update-all-roundtrip-test.sh
  harness-hooks-smoke.sh
  hook-prune-test.sh
  hook-stdin-dispatch-test.sh
  hermes-keywords-test.sh
  hermes-evolve-vocab-test.sh
  windows-smoke.sh
  hermes-pipeline-test.sh
  hermes-loop-test.sh
  hermes-redact-test.sh
  hermes-redact-boundary-test.sh
  hermes-secret-masking-test.sh
  check-secrets-answerkey-test.sh
  check-secrets-code-expr-test.sh
  hermes-crystallize-naming-test.sh
  hermes-dream-test.sh
  hermes-cleanup-lock-test.sh
  hermes-recall-measurement-test.sh
  hermes-recall-history-search-test.sh
  uninstall-roundtrip-test.sh
  copy-install-test.sh
  install-receipt-test.sh
  install-coexist-test.sh
  install-closure-test.sh
  raw-copy-guard-test.sh
  hermes-universe-test.sh
  hermes-journal-test.sh
  hermes-keys-test.sh
  hermes-key-guard-test.sh
  hermes-sync-test.sh
  tool-installers-test.sh
  hermes-redact-pii-test.sh
  sync-autoenable-test.sh
  hermes-roster-test.sh
  hermes-summon-guard-test.sh
  hermes-soul-inject-test.sh
  hermes-role-templates-test.sh
  hermes-memory-events-test.sh
  hermes-handoff-test.sh
  hermes-teaching-test.sh
  hermes-dashboard-test.sh
  hermes-skill-layers-test.sh
  hermes-skill-inject-test.sh
  hermes-skill-extends-test.sh
  hermes-propose-test.sh
  hermes-crystallize-reversed-test.sh
  hermes-skill-yield-test.sh
  hermes-cleanup-step5-test.sh
  memory-symlink-roundtrip-test.sh
  hermes-history-export-test.sh
  hermes-lifecycle-test.sh
  hermes-lifecycle-portability-test.sh
  hermes-mesh-consume-test.sh
  hermes-mesh-gate-test.sh
  run-all-orphan-guard-test.sh
)

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

# §2 에서 개별 run_step 으로 도는 테스트 (REGISTERED_TESTS 밖이지만 고아가 아니다)
INTEGRITY_TESTS="preset-integrity-test.sh"

# 고아 테스트 검사 — tests/ 의 *-test.sh · *smoke*.sh 가 러너 목록에 없으면 실패.
# 조용히 안 도는 테스트를 금지한다. 의도적으로 빼려면 SKIP_TESTS 에 이름을 적는다.
# (backlog run-all-orphan-test-guard: 한때 6개 테스트가 등록 누락으로 안 돌았다)
orphan_test_check() {
  local rc=0 f name orphans=() missing=()
  local listed=",${INTEGRITY_TESTS},$(IFS=,; echo "${REGISTERED_TESTS[*]}"),"
  while IFS= read -r f; do
    name="${f##*/}"
    [[ "$listed" == *",$name,"* ]] && continue
    _is_skipped "$name" && continue
    orphans+=("$name")
  done < <(find "$TESTS_DIR" -maxdepth 1 -type f \( -name "*-test.sh" -o -name "*smoke*.sh" \) | sort)
  for name in $INTEGRITY_TESTS "${REGISTERED_TESTS[@]}"; do
    [[ -f "$TESTS_DIR/$name" ]] || missing+=("$name")
  done
  if [[ ${#orphans[@]} -gt 0 ]]; then
    echo "  ✗ 고아 테스트 ${#orphans[@]}개 — run-all.sh 의 REGISTERED_TESTS 에 추가하거나 SKIP_TESTS=<이름> 으로 명시해 빼십시오:"
    printf '      - %s\n' "${orphans[@]}"; rc=1
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "  ✗ 목록에 있으나 없음 ${#missing[@]}개 — 파일을 복구하거나 목록에서 지우십시오:"
    printf '      - %s\n' "${missing[@]}"; rc=1
  fi
  [[ $rc -eq 0 ]] && echo "  ✓ 고아 테스트 0 · 결손 0 (등록 $(( ${#REGISTERED_TESTS[@]} + 1 ))개)"
  return $rc
}

if [[ "${1:-}" == "--check-orphans" ]]; then
  orphan_test_check; exit $?
fi

run_step "고아 테스트 검사" orphan_test_check
run_step "bash -n (셸 문법 전수)" bash_syntax_check
run_step "python3 -m py_compile (scripts + lib)" python_compile_check

# ── 2. 무결성 검사 ────────────────────────────────────────────────────────────

run_step "preset-integrity-test.sh" bash "$TESTS_DIR/preset-integrity-test.sh"
run_step "sync-plugins.sh --check" bash "$REPO_ROOT/scripts/sync-plugins.sh" --check

# ── 3. 통합 테스트 ────────────────────────────────────────────────────────────

for t in "${REGISTERED_TESTS[@]}"; do
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
