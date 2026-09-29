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

# ── pyenv shim 우회 — 설치기와 같은 함수(lib/pyenv_bypass.sh). 끄기: HARNESS_NO_PYENV_BYPASS=1
# 러너를 가짜 저장소로 복사해 도는 시험(run-all-parallel-test)에서는 이 파일이 없다 — 없으면 건너뛴다.
[[ -f "$REPO_ROOT/lib/pyenv_bypass.sh" ]] && source "$REPO_ROOT/lib/pyenv_bypass.sh"
if declare -F harness_pyenv_bypass >/dev/null 2>&1; then
  harness_pyenv_bypass
  [[ "${_HARNESS_PYBIN_PID:-}" == "$$" ]] && echo "[run-all] pyenv shim 우회 → $(pyenv which python3 2>/dev/null)"
fi
# 우회 폴더는 **이 러너가 만든 것만** 지운다. 중첩 실행된 러너가 바깥 러너의 폴더를 물려받아
# 지우면, 바깥의 남은 시험이 전부 느린 셔임으로 되돌아간다(2026-09-23 리뷰 지적).
_cleanup_runall() {
  declare -F harness_pyenv_cleanup >/dev/null 2>&1 && harness_pyenv_cleanup
  [[ -n "${TMP_PARALLEL:-}" ]] && rm -rf "$TMP_PARALLEL"
  return 0
}
trap _cleanup_runall EXIT

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
  local rc=0 out=""
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    # CI 에서만 출력을 사본으로 남긴다 — 실패 시 annotation 으로 올리기 위해 (로그는 관리자만 읽는다)
    out="$(mktemp)"
    ( "$@" ) 2>&1 | tee "$out" || rc=$?
  else
    ( "$@" ) || rc=$?
  fi
  if [[ $rc -eq 0 ]]; then
    echo -e "${GREEN}── PASS: $name ──${RESET}"
    PASSED=$((PASSED+1))
  else
    echo -e "${RED}── FAIL: $name ──${RESET}"
    FAILED=$((FAILED+1))
    FAILED_NAMES+=("$name")
    [[ -n "$out" ]] && _annotate_failure "$name" "$out"
  fi
  [[ -n "$out" ]] && rm -f "$out"
  echo ""
}

# ── 병렬 실행 ─────────────────────────────────────────────────────────────────
# HARNESS_TEST_JOBS=1(기본)이면 아래 풀을 쓰지 않는다 — 동작이 예전과 같다.
# N>1 이면 각 시험을 자식으로 띄우고, 출력·판정을 **등록 순서대로** 모아 낸다.
# 순서를 유지하는 이유: 사람이 읽는 로그가 실행마다 뒤바뀌면 diff 를 못 뜬다.
# 기본은 **병렬** — 돌릴 때마다 그 컴퓨터의 코어 수를 읽어 **절반**을 쓴다(상한 없음).
# 설치 시험이 CPU 를 많이 써서 코어를 전부 쓰면 서로 다툰다. 22코어면 11, 4코어 CI 면 2.
# 순차로 돌리려면 HARNESS_TEST_JOBS=1.
_default_jobs() { local n; n=$(( $(nproc 2>/dev/null || echo 2) / 2 )); (( n < 1 )) && n=1; echo "$n"; }
JOBS="${HARNESS_TEST_JOBS:-$(_default_jobs)}"

# ── 샤드 — CI 가 서버 여러 대에 나눠 돌릴 때 이 서버의 몫만 돈다. HARNESS_TEST_SHARD="몇번째/몇대"(예 2/4).
# 비어 있으면 1/1(전부). 번갈아 나누면 무거운 설치 시험이 한 서버에 몰렸다(2026-09-27 실측 7·3·2·5개) —
# 시험마다 **설치 횟수로 무게**를 재어 무거운 것부터 가장 한가한 서버에 배정한다(결정적: 같은 입력 → 같은 배정).
SHARD_I=1; SHARD_N=1
if [[ -n "${HARNESS_TEST_SHARD:-}" ]]; then
  if [[ "$HARNESS_TEST_SHARD" =~ ^([0-9]+)/([0-9]+)$ ]] && (( BASH_REMATCH[2] >= 1 && BASH_REMATCH[1] >= 1 && BASH_REMATCH[1] <= BASH_REMATCH[2] )); then
    SHARD_I="${BASH_REMATCH[1]}"; SHARD_N="${BASH_REMATCH[2]}"
  else
    echo "[run-all] HARNESS_TEST_SHARD 값이 잘못됐다: '$HARNESS_TEST_SHARD' (예: 2/4)" >&2; exit 2
  fi
fi
_shard_select() {
  (( SHARD_N == 1 )) && { printf '%s\n' "$@"; return 0; }
  local t w
  for t in "$@"; do
    w=$(grep -cE '(project-claude|update-all)\.sh|^[[:space:]]*install( |\()' "$TESTS_DIR/$t" 2>/dev/null || true)
    printf '%s %s\n' "$(( ${w:-0} + 1 ))" "$t"
  done | sort -k1,1nr -k2,2 | awk -v n="$SHARD_N" -v me="$SHARD_I" '
    { best = 1; for (i = 2; i <= n; i++) if (load[i] < load[best]) best = i
      load[best] += $1; if (best == me) print $2 }'
}
# 실제로 쓰는 값을 자식에게 넘긴다 — 기본값을 여기서 올려도 자식 시험(run-all-parallel-test 의
# 속도 단언 가드)이 바깥이 병렬인지 알 수 있다(2026-09-23 리뷰 지적).
export HARNESS_TEST_JOBS="$JOBS"

# ── 시험별 소요 시간 ──────────────────────────────────────────────────────────
# 병렬 실행 때마다 시험별 초를 남기고, 다음 실행은 긴 것부터 시작한다. 기계마다 다르므로 .harness/ 에 둔다
# (.gitignore 대상 — 커밋하지 않는다). 이번에 안 돈 시험(샤드 밖 등)의 옛 기록은 지우지 않고 남긴다.
DURATIONS_FILE="$REPO_ROOT/.harness/test-durations.tsv"

_start_order() { # _start_order <이름...> → 시작할 순서대로 인덱스를 한 줄씩
  local -A dur=(); local s t i=0
  [[ -f "$DURATIONS_FILE" ]] && while IFS=$'\t' read -r s t; do [[ -n "$t" ]] && dur[$t]=$s; done < "$DURATIONS_FILE"
  for t in "$@"; do printf '%s\t%s\n' "${dur[$t]:-999999}" "$i"; i=$((i+1)); done \
    | sort -t$'\t' -k1,1nr -k2,2n | cut -f2
}

_save_durations() { # _save_durations <이름...> — 이번 기록으로 덮고, 나머지 옛 기록은 유지
  local -A dur=(); local s t i=0
  [[ -f "$DURATIONS_FILE" ]] && while IFS=$'\t' read -r s t; do [[ -n "$t" ]] && dur[$t]=$s; done < "$DURATIONS_FILE"
  for t in "$@"; do [[ -s "$TMP_PARALLEL/$i.out.sec" ]] && dur[$t]="$(cat "$TMP_PARALLEL/$i.out.sec")"; i=$((i+1)); done
  mkdir -p "$(dirname "$DURATIONS_FILE")" 2>/dev/null || return 0
  { for t in "${!dur[@]}"; do printf '%s\t%s\n' "${dur[$t]}" "$t"; done; } | sort -t$'\t' -k1,1nr -k2,2 > "$DURATIONS_FILE.tmp" \
    && mv "$DURATIONS_FILE.tmp" "$DURATIONS_FILE"
  echo "[run-all] 가장 오래 걸린 시험: $(head -3 "$DURATIONS_FILE" | awk -F'\t' '{printf "%s(%ss) ", $2, $1}')"
}

run_registered_parallel() { # run_registered_parallel <이름...>
  local names=("$@") pool="$TMP_PARALLEL" i=0
  local -a outs=() rcs=()
  for name in "${names[@]}"; do
    outs+=("$pool/$i.out"); rcs+=("$pool/$i.rc"); i=$((i+1))
  done
  # **시작**은 지난번에 오래 걸린 시험부터 한다 — 긴 시험이 늦게 시작하면 혼자 꼬리를 잡는다
  # (2026-09-23 실측: 단독 107초짜리 harness-eval-test 가 마지막까지 남았다). **출력**은 여전히 등록 순서다.
  local -a order; mapfile -t order < <(_start_order "${names[@]}")
  for i in "${order[@]}"; do
    name="${names[$i]}"
    if _is_skipped "$name"; then
      printf 'SKIP' > "${rcs[$i]}"; : > "${outs[$i]}"; continue
    fi
    while [[ $(jobs -rp | wc -l) -ge $JOBS ]]; do wait -n 2>/dev/null || break; done
    (
      rc=0; t0=$(date +%s)
      # 시험 자체 출력(.body)과 머리·꼬리 줄을 붙인 블록(.out)을 나눠 둔다. CI 실패 주석은 순차 경로처럼
      # **시험 자체 출력만** 받아야 한다 — 블록을 넘기면 `── FAIL:` 머리줄까지 주석에 한 번 더 찍힌다
      # (2026-09-27 CI 실측: 병렬 판정 집합에 FAIL 이 두 번 잡혀 run-all-parallel-test 가 CI 에서만 떨어졌다).
      bash "$TESTS_DIR/$name" > "${outs[$i]}.body" 2>&1 || rc=$?
      { echo -e "${BOLD}── RUN: $name ──${RESET}"
        cat "${outs[$i]}.body"
        if [[ $rc -eq 0 ]]; then echo -e "${GREEN}── PASS: $name ──${RESET}"
        else echo -e "${RED}── FAIL: $name ──${RESET}"; fi
        echo ""
      } > "${outs[$i]}" 2>&1
      printf '%s' "$rc" > "${rcs[$i]}"
      echo $(( $(date +%s) - t0 )) > "${outs[$i]}.sec"
      # 진행을 그 자리에서 한 줄 알린다. 본문은 뒤에서 등록 순서대로 몰아 내지만,
      # 그동안 아무것도 안 찍히면 밖에서는 멎은 것과 구분이 안 된다(2026-09-23 실측: 사용자가 5분 뒤 중단).
      # 색 변수는 '\033[..m' 글자 그대로다 — %s 가 아니라 %b 로 풀어야 색이 된다(2026-09-23 리뷰 지적)
      if [[ $rc -eq 0 ]]; then printf '  %b✔%b %s\n' "$GREEN" "$RESET" "$name" >&2
      else printf '  %b✘%b %s\n' "$RED" "$RESET" "$name" >&2; fi
    ) &
  done
  wait
  _save_durations "${names[@]}"
  # 집계·출력은 등록 순서로 — 실행 순서와 무관하게 로그가 같은 모양이 된다
  i=0
  for name in "${names[@]}"; do
    local rc; rc="$(cat "${rcs[$i]}" 2>/dev/null || echo 1)"
    if [[ "$rc" == "SKIP" ]]; then
      echo -e "${YELLOW}── SKIP: $name ──${RESET}"; SKIPPED=$((SKIPPED+1))
    else
      TOTAL=$((TOTAL+1))
      cat "${outs[$i]}"
      if [[ "$rc" == "0" ]]; then PASSED=$((PASSED+1))
      else
        FAILED=$((FAILED+1)); FAILED_NAMES+=("$name")
        [[ "${GITHUB_ACTIONS:-}" == "true" ]] && _annotate_failure "$name" "${outs[$i]}.body"
      fi
    fi
    i=$((i+1))
  done
}

# 실패한 테스트 이름과 출력 끝부분을 GitHub annotation 으로 남긴다.
# annotation 은 공개 API(check-runs/<id>/annotations)로 읽혀 로그 권한 없이 원인을 볼 수 있다.
ANNOTATE_TAIL_LINES=20   # annotation 한 건에 담을 출력 끝 줄 수 — 단언 실패 줄과 직전 맥락이 들어가는 폭
_annotate_failure() { # _annotate_failure <이름> <출력 파일>
  local name="$1" file="$2" body
  body="$(tail -n "$ANNOTATE_TAIL_LINES" "$file" | sed 's/\x1b\[[0-9;]*m//g')"
  body="${body//'%'/'%25'}"; body="${body//$'\r'/'%0D'}"; body="${body//$'\n'/'%0A'}"
  echo "::error title=run-all FAIL: ${name}::${body}"
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
  hermes-persona-source-test.sh
  hermes-persona-store-test.sh
  hermes-persona-extract-test.sh
  hermes-persona-distill-test.sh
  hermes-persona-score-test.sh
  hermes-persona-inject-test.sh
  hermes-yield-integrity-test.sh
  hermes-recall-marker-integrity-test.sh
  doc-counts-autofix-test.sh
  hermes-privacy-scrub-test.sh
  hermes-ask-test.sh
  hermes-skill-write-test.sh
  cli-prompt-stdin-test.sh
  hermes-rule-candidates-test.sh
  hermes-evolve-vocab-test.sh
  evolve-hint-source-test.sh
  workflow-failure-notice-test.sh
  windows-smoke.sh
  hermes-pipeline-test.sh
  precompact-summary-test.sh
  manifest-tracking-test.sh
  claude-config-scan-test.sh
  context-budget-test.sh
  edit-factcheck-rate-test.sh
  eval-reminder-test.sh
  hermes-loop-test.sh
  hermes-redact-test.sh
  hermes-redact-boundary-test.sh
  hermes-secret-masking-test.sh
  check-secrets-answerkey-test.sh
  check-secrets-code-expr-test.sh
  check-secrets-label-exempt-test.sh
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
  hermes-identity-guard-test.sh
  hermes-soul-approval-test.sh
  hermes-sync-test.sh
  tool-installers-test.sh
  hermes-redact-pii-test.sh
  sync-autoenable-test.sh
  hermes-roster-test.sh
  hermes-agent-mention-test.sh
  hermes-agent-room-test.sh
  hermes-hag-test.sh
  hermes-hag-rooms-test.sh
  hermes-agent-summary-test.sh
  hermes-carry-knowledge-test.sh
  hermes-privacy-review-test.sh
  hermes-chat-test.sh
  hermes-statusline-test.sh
  hermes-summon-guard-test.sh
  hermes-soul-inject-test.sh
  hermes-role-templates-test.sh
  harness-doctor-test.sh
  harness-eval-test.sh
  hermes-memory-events-test.sh
  hermes-handoff-test.sh
  hermes-teaching-test.sh
  hermes-dashboard-test.sh
  hermes-repo-sync-test.sh
  git-ignore-judge-test.sh
  preset-lock-tracked-test.sh
  hermes-skill-layers-test.sh
  hermes-skill-inject-test.sh
  hermes-skill-extends-test.sh
  hermes-propose-test.sh
  hermes-crystallize-reversed-test.sh
  hermes-skill-yield-test.sh
  hermes-cleanup-step5-test.sh
  memory-symlink-roundtrip-test.sh
  hermes-mesh-consume-test.sh
  hermes-mesh-gate-test.sh
  run-all-orphan-guard-test.sh
  run-all-parallel-test.sh
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

# 추정하지 않으려고 이 서버의 조건을 첫 줄에 남긴다 — CI 가 왜 느린지 로그만으로 알 수 있게.
echo "[run-all] 코어 $(nproc 2>/dev/null || echo ?) · 병렬 $JOBS · 샤드 $SHARD_I/$SHARD_N"

# 정적·무결성 검사는 저장소 전체를 한 번 보면 되므로 **1번 샤드만** 돈다.
if (( SHARD_I == 1 )); then
run_step "고아 테스트 검사" orphan_test_check
run_step "bash -n (셸 문법 전수)" bash_syntax_check
run_step "python3 -m py_compile (scripts + lib)" python_compile_check

# ── 2. 무결성 검사 ────────────────────────────────────────────────────────────

run_step "preset-integrity-test.sh" bash "$TESTS_DIR/preset-integrity-test.sh"
run_step "sync-plugins.sh --check" bash "$REPO_ROOT/scripts/sync-plugins.sh" --check
fi

# ── 3. 통합 테스트 ────────────────────────────────────────────────────────────

mapfile -t MY_TESTS < <(_shard_select "${REGISTERED_TESTS[@]}")
if [[ "$JOBS" -gt 1 ]] 2>/dev/null; then
  TMP_PARALLEL="$(mktemp -d)"   # 정리는 위의 _cleanup_runall 이 함께 맡는다
  run_registered_parallel "${MY_TESTS[@]}"
else
  for t in "${MY_TESTS[@]}"; do
    run_step "$t" bash "$TESTS_DIR/$t"
  done
fi

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
