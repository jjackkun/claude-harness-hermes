#!/usr/bin/env bash
# git pre-commit hook — 4단 검사 (R-size / R-fmt / R-lint / R-test) + R-plan.
#
# 메시지 형식 (2026-04-17 Opus 4.7 튜닝):
#   [룰 ID] 위반 사실 → 한 줄 권장 행동. 근거: docs/design-docs/core-beliefs.md#<anchor>.
#   메타지시(1./2./3.) 금지 — 4.7 이 글자대로 매 턴 실행 시도.
#
# 한도: ESLint max-lines (1차 경고) + MAX_LINES_HARD (2차 절대, 기본 500).
# .harnessrc 또는 환경변수로 override. 설치는 setup.sh 가 처리.

set -euo pipefail

MAX_LINES_HARD="${MAX_LINES_HARD:-500}"
[[ -f .harnessrc ]] && source .harnessrc

mapfile -t STAGED < <(git diff --cached --name-only --diff-filter=ACM)
[[ ${#STAGED[@]} -eq 0 ]] && exit 0

EXCLUDE_RE='(^|/)(node_modules|venv|\.venv|\.svelte-kit|\.next|dist|build|docs_legacy)(/|$)'

filter_files() {
  local pattern="$1"
  for f in "${STAGED[@]}"; do
    [[ "$f" =~ $EXCLUDE_RE ]] && continue
    [[ -L "$f" ]] && continue
    [[ "$f" =~ $pattern ]] && echo "$f"
  done
  return 0
}

CHECKABLE=$(filter_files '\.(py|js|jsx|ts|tsx|svelte)$')
JS_TS=$(filter_files '\.(js|jsx|ts|tsx|svelte)$')
PY_FILES=$(filter_files '\.py$')
PRETTIER_FILES=$(filter_files '\.(js|jsx|ts|tsx|svelte|json|css|scss|md|yaml|yml)$')

FAIL=0
VIOLATIONS=()

# 1. R-size
if [[ -n "$CHECKABLE" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    LC=$(wc -l < "$f")
    if (( LC > MAX_LINES_HARD )); then
      VIOLATIONS+=("$(cat <<EOF

[R-size] $f ($LC 줄 > $MAX_LINES_HARD)
  → 단일 책임 분리 / 헬퍼 추출 후 재시도. 한도 조정은 docs/audits/ 근거 후 .harnessrc.
  근거: docs/design-docs/core-beliefs.md#r-size
EOF
)")
      FAIL=1
    fi
  done <<< "$CHECKABLE"
fi

# 2. R-fmt — prettier --check
if [[ -n "$PRETTIER_FILES" ]] && command -v pnpm >/dev/null 2>&1 \
    && pnpm exec prettier --version >/dev/null 2>&1; then
  PRETTIER_OUT=$(echo "$PRETTIER_FILES" | xargs pnpm exec prettier --check 2>&1) || {
    VIOLATIONS+=("$(cat <<EOF

[R-fmt] prettier 포맷팅 위반.

위반 파일:
$(echo "$PRETTIER_OUT" | grep -E '^\[warn\]' || echo '(파일 목록 추출 실패 — 직접 확인)')
  → \`pnpm exec prettier --write <파일>\` 자동 수정. .prettierrc 단독 변경 금지.
  근거: docs/design-docs/core-beliefs.md#r-fmt
EOF
)")
    FAIL=1
  }
fi

# 3. R-lint — ESLint
if [[ -n "$JS_TS" ]] && command -v pnpm >/dev/null 2>&1 \
    && pnpm exec eslint --version >/dev/null 2>&1; then
  ESLINT_OUT=$(echo "$JS_TS" | xargs pnpm exec eslint --max-warnings 0 2>&1) || {
    VIOLATIONS+=("$(cat <<EOF

[R-lint] ESLint 위반.

$ESLINT_OUT
  → 위반 메시지의 한국어 지침을 따라 수정. eslint-disable 단독 우회 금지.
  근거: docs/design-docs/core-beliefs.md#r-lint
EOF
)")
    FAIL=1
  }
fi

# 4. R-test — pytest
if [[ -n "$PY_FILES" ]]; then
  PYTEST_DIR=""
  for cand in tests backend/tests; do
    [[ -d "$cand" ]] && PYTEST_DIR="$cand" && break
  done
  # venv pytest 우선, 없으면 시스템 pytest
  PYTEST_BIN=""
  for cand in backend/venv/bin/pytest venv/bin/pytest; do
    [[ -x "$cand" ]] && PYTEST_BIN="$cand" && break
  done
  [[ -z "$PYTEST_BIN" ]] && command -v pytest >/dev/null 2>&1 && PYTEST_BIN="pytest"
  if [[ -n "$PYTEST_DIR" ]] && [[ -n "$PYTEST_BIN" ]]; then
    # 종료코드 캡처. exit 0=통과, 5=수집 0개 → 통과로 간주. 그 외(실패/중단/에러)는 차단.
    PYTEST_OUT=$("$PYTEST_BIN" "$PYTEST_DIR" -q 2>&1) && PYTEST_RC=0 || PYTEST_RC=$?
    if [[ "$PYTEST_RC" -ne 0 && "$PYTEST_RC" -ne 5 ]]; then
      VIOLATIONS+=("$(cat <<EOF

[R-test] pytest 실패.

$(echo "$PYTEST_OUT" | tail -30)
  → 회귀면 코드를 고침. 룰 강제 테스트면 룰을 따름. 테스트 단독 비활성화 금지.
  근거: docs/design-docs/core-beliefs.md#r-test
EOF
)")
      FAIL=1
    fi
  fi
fi

# 5. R-struct — 컴포넌트 폴더/배럴 규칙 (Vue 프로젝트)
CHECK_STRUCT="$(dirname "$0")/check-component-structure.mjs"
VUE_AND_CODE=$(filter_files '\.(vue|js|jsx|ts|tsx)$')
if [[ -n "$VUE_AND_CODE" ]] && [[ -f "$CHECK_STRUCT" ]] && command -v node >/dev/null 2>&1; then
  STRUCT_OUT=$(echo "$VUE_AND_CODE" | xargs node "$CHECK_STRUCT" 2>&1) || {
    VIOLATIONS+=("$(cat <<EOF

[R-struct] 컴포넌트 구조 위반.

$STRUCT_OUT
  → 위반 메시지의 지침을 따라 폴더·배럴·import 를 수정 후 재시도.
  근거: assets/rules/web/coding-style.md §File-Organization
EOF
)")
    FAIL=1
  }
fi

# 7. R-plan — 완료된 계획이 active/ 에 남아있으면 경고
ACTIVE_DIR="docs/exec-plans/active"
if [[ -d "$ACTIVE_DIR" ]]; then
  while IFS= read -r plan; do
    [[ -f "$plan" ]] || continue
    total=$(grep -cE '^\s*-\s*\[' "$plan" 2>/dev/null || true)
    done_count=$(grep -cE '^\s*-\s*\[x\]' "$plan" 2>/dev/null || true)
    total=${total:-0}
    done_count=${done_count:-0}
    if [[ "$total" -gt 0 && "$total" -eq "$done_count" ]]; then
      VIOLATIONS+=("
[R-plan] 완료된 계획이 active/ 에 남아있음: $plan ($done_count/$total)
  → 회고(§8) 작성 후 \`git mv \"$plan\" \"docs/exec-plans/completed/\$(basename \"$plan\")\"\`.
  근거: docs/design-docs/core-beliefs.md#r-plan")
      FAIL=1
    fi
  done < <(find "$ACTIVE_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null)
fi

# 8. R-plan-missing — 코드 수정했는데 active/ 에 계획 없으면 경고
if [[ -n "$CHECKABLE" && -d "$ACTIVE_DIR" ]]; then
  PLAN_COUNT=$(find "$ACTIVE_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l)
  if [[ "$PLAN_COUNT" -eq 0 ]]; then
    VIOLATIONS+=("
[R-plan-missing] 코드 수정 있으나 active/ 에 계획 없음.
  → 단순 버그(1~2파일)면 무시. 다중 파일·설계 결정이면 docs/exec-plans/active/YYYY-MM-DD-<slug>.md 작성.
  근거: docs/design-docs/core-beliefs.md#r-plan-missing")
    # 경고만, 차단 안 함
  fi
fi

# 출력
if (( FAIL )); then
  echo ""
  echo "════════════════════════════════════════════════════════════════════"
  echo "  하네스 차단 — 아래 위반을 해결 후 재시도."
  echo "════════════════════════════════════════════════════════════════════"
  for v in "${VIOLATIONS[@]}"; do echo "$v"; done
  echo ""
  echo "════════════════════════════════════════════════════════════════════"
  echo "  --no-verify 우회 금지. 규율 변경은 docs/audits/ 근거 후."
  echo "════════════════════════════════════════════════════════════════════"
  exit 1
fi

exit 0
