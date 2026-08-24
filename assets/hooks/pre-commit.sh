#!/usr/bin/env bash
# git pre-commit hook — 4단 검사 (R-size / R-fmt / R-lint / R-test) + R-struct / R-secret / R-plan.
#
# "4단 검사" 문구는 uninstall 이 하네스 설치본을 식별하는 마커다 — 바꾸지 말 것
# (lib/uninstall_helpers.sh `uninstall_pre_commit`, uninstall.sh 미리보기).
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
# 조기 종료 판정에는 rename 을 포함한 전체 스테이징 여부를 쓴다.
# 순수 rename(git mv)만 있는 커밋은 ACM 에 잡히지 않아 STAGED 가 비는데, R-retro 는
# 바로 그 경우를 봐야 한다(2026-08-13 실측). STAGED 자체에 R 을 넣지 않는 이유는
# 그러면 R-size 부터 R-secret 까지 모든 검사의 범위가 함께 바뀌기 때문이다.
[[ -z "$(git diff --cached --name-only)" ]] && exit 0

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

# R-size 대상. `.vue` 포함(2026-08-07) — SFC 도 "한 파일 = 한 책임"의 대상이다.
# 새 정책이 아니라 누락 보정이다: 이 저장소의 review-reminder·prettier-warn·dead-file-warn·
# codex size-warn 은 이미 .vue 를 검사하고, R-size 두 훅만 빠져 있었다.
# .vue 가 없는 프로젝트에선 no-op 이라 부작용이 없다.
CHECKABLE=$(filter_files '\.(py|js|jsx|ts|tsx|svelte|vue)$')
JS_TS=$(filter_files '\.(js|jsx|ts|tsx|svelte)$')
PY_FILES=$(filter_files '\.py$')

# 계획 축 전용. R-size 를 구동하는 CHECKABLE 과 분리한다 —
# "계획을 세울 만한 작업 코드"와 줄 수 검사의 대상은 같은 집합이 아니다.
# 하네스 생성물은 뺀다: 재설치가 scripts/hooks/ 를 덮어쓰므로 포함하면
# 하네스 갱신 커밋 자체가 자기 게이트에 걸린다(아래 R-fmt 주석의 prettier 사고와 같은 종류).
# .md 는 넣지 않는다 — 문서 수정마다 계획서를 요구하면 오탈자에도 걸려 우회가 상시화된다.
HARNESS_MANAGED_RE='^scripts/(hooks|codex-hooks)/'
WORK_FILES=$(filter_files '\.(py|js|jsx|ts|tsx|svelte|vue|sh|mjs|go|rs|java|rb|php)$' \
  | grep -vE "$HARNESS_MANAGED_RE" || true)

# 계획서 판정 모듈. pre-commit 옆에 설치기가 복사한다.
PLAN_STATE="$(dirname "$0")/plan_state.py"
PLAN_STATE_OK=1

# R-fmt 대상에서 **하네스 생성물**을 뺀다.
# 이 파일들은 손으로 쓰는 소스가 아니라 설치 스크립트가 통째로 만든 산출물이고,
# 서식의 주인은 프로젝트의 .prettierrc 가 아니라 생성기다. 프로젝트마다 prettier
# 설정이 다르므로 생성기가 전부에 맞출 수 없다 — 맞추려 들면 재설치할 때마다
# 자기 게이트에 자기가 걸려 커밋이 막힌다(실제로 3개 프로젝트에서 발생).
# `.claude/memory/` 도 같은 부류다 — 기억 시스템이 쓰는 산출물이지 손으로 쓰는 문서가 아니다.
GENERATED_RE='^(CLAUDE\.md|AGENTS\.md|\.claude/(settings(\.local)?\.json|\.dev-setting-manifest\.json)|\.codex/settings(\.local)?\.json)$|^\.claude/memory/'
PRETTIER_FILES=$(filter_files '\.(js|jsx|ts|tsx|svelte|json|css|scss|md|yaml|yml)$' \
  | grep -vE "$GENERATED_RE" || true)

FAIL=0
VIOLATIONS=()
# 차단하지 않는 경고. VIOLATIONS 와 분리하는 이유 — VIOLATIONS 는 FAIL=1 일 때만
# 출력되므로, 경고 등급 위반이 단독 발생하면 아무것도 보이지 않는다.
# (2026-08-13 확인: R-plan-missing 이 그 상태로 방치돼 있었다.)
WARNINGS=()

# 모듈 부재 원인을 구분해 알린다 — 뭉뚱그리면 사용자가 재설치를 반복해도
# 해결되지 않는 삽질을 한다. 조용히 건너뛰지 않는 것이 핵심이다.
if [[ ! -f "$PLAN_STATE" ]]; then
  PLAN_STATE_OK=0
  WARNINGS+=("
[R-plan] 계획 축 검사 3개를 건너뜀 — plan_state.py 없음 (재설치 필요)")
elif ! command -v python3 >/dev/null 2>&1; then
  PLAN_STATE_OK=0
  WARNINGS+=("
[R-plan] 계획 축 검사 3개를 건너뜀 — python3 없음 (인터프리터 설치 필요)")
fi

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
  # ANSI 색상 코드를 벗겨 저장한다. prettier 는 파이프에서도 색을 넣는 경우가 있어
  # `^\[warn\]` 매칭이 빗나가고, 그러면 "위반 파일: (추출 실패)" 만 남아 **무엇을
  # 고쳐야 하는지 알 수 없는 차단**이 된다 — 사람이 --no-verify 로 도망가는 경로다.
  PRETTIER_OUT=$(echo "$PRETTIER_FILES" | xargs pnpm exec prettier --check 2>&1 \
    | sed 's/\x1b\[[0-9;]*m//g') || {
    VIOLATIONS+=("$(cat <<EOF

[R-fmt] prettier 포맷팅 위반.

위반 파일:
$(echo "$PRETTIER_OUT" | grep -E '^\[warn\] ' | grep -v 'Code style issues' || echo '(파일 목록 추출 실패 — 직접 확인)')
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
    # 세 상태를 구분한다. 예전에는 "실패" 와 "실행 불가" 가 한 덩어리였고,
    # "수집 0개" 는 조용히 통과라 게이트가 죽은 줄 아무도 몰랐다.
    #
    # (a) 실행 불가 — pytest 가 자기 모듈도 import 못 하는 상태. 차단하지 않는다.
    #     도구가 못 뜬 것을 "테스트 실패" 로 보고하면 사람이 코드를 뒤지게 된다.
    #     실측: HOME 이 바뀌어 user-site 가 사라지면 실행 파일은 있는데 import 가 깨진다.
    if ! "$PYTEST_BIN" --version >/dev/null 2>&1; then
      WARNINGS+=("
[R-test] pytest 실행 불가 — 이번 커밋의 파이썬 변경은 검증되지 않았다.
  \$($PYTEST_BIN --version) 이 실패한다. 설치가 깨졌거나 인터프리터가 바뀌었다.
  근거: docs/design-docs/core-beliefs.md#r-test")
    else
      # 종료코드 캡처. 0=통과, 5=수집 0개.
      PYTEST_OUT=$("$PYTEST_BIN" "$PYTEST_DIR" -q 2>&1) && PYTEST_RC=0 || PYTEST_RC=$?
      if [[ "$PYTEST_RC" -eq 5 ]]; then
        # (b) 수집 0개 — 차단하지 않는다. 파이썬 없는 프로젝트도 설치 대상이므로
        #     막으면 안 된다. 다만 조용히 넘기면 게이트가 죽은 줄 모른다.
        #     이 저장소가 실제로 그 상태였다: 테스트 0개인 채로 R-test 가 늘 통과했다.
        WARNINGS+=("
[R-test] 스테이징된 .py 가 있으나 수집된 테스트가 0개다.
  이 커밋의 파이썬 변경은 어떤 테스트로도 검증되지 않는다.
  근거: docs/design-docs/core-beliefs.md#r-test")
      elif [[ "$PYTEST_RC" -ne 0 ]]; then
        # (c) 실제 실패 — 차단.
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
fi

# 4-bis. R-cx — 순환 복잡도 (라쳇)
#
# R-size 는 파일 크기만 본다. 500줄을 지키면서 복잡도 48 짜리 함수를 쓰는 것이
# 통과하고 있었다. 임계 12 는 이 저장소 함수 295개의 분포 절벽(11:11개 → 12:4개)에서
# 나왔다. 기존 위반 파일은 .cxbaseline 이 현재값을 동결하므로 막히지 않고,
# 그보다 나빠질 때만 차단된다 — 일괄 적용하면 파일의 43% 가 막혀 우회가 상시화된다.
#
# 모듈 부재는 조용히 넘기지 않는다. R-test 가 파이썬 테스트 0개인 상태로 몇 달간
# 아무것도 막지 않으면서 통과 표시를 내고 있었다 — 게이트가 죽은 줄 모르는 것이 최악이다.
CHECK_CX="$(dirname "$0")/complexity.py"
if [[ -n "$PY_FILES" ]]; then
  if [[ ! -f "$CHECK_CX" ]]; then
    WARNINGS+=("
[R-cx] 복잡도 검사를 건너뜀 — complexity.py 없음 (재설치 필요)")
  elif ! command -v python3 >/dev/null 2>&1; then
    WARNINGS+=("
[R-cx] 복잡도 검사를 건너뜀 — python3 없음 (인터프리터 설치 필요)")
  else
    CX_OUT=$(echo "$PY_FILES" | xargs python3 "$CHECK_CX" 2>&1) || {
      VIOLATIONS+=("$(cat <<EOF

$CX_OUT
EOF
)")
      FAIL=1
    }
    # 개선 안내는 차단 없이도 나온다 — 기준선을 낮출 기회를 놓치지 않도록.
    if [[ -n "$CX_OUT" ]] && [[ "$FAIL" -eq 0 ]]; then
      WARNINGS+=("
$CX_OUT")
    fi
  fi
fi

# 4-quater. R-cov — 어떤 테스트도 실행하지 않는 파일을 고치는가 (경고)
#
# 임계를 두지 않는다. 2026-08-25 실측 분포에서 0% 와 그 다음 값 사이의 간격이
# 70.6 포인트(0 → 70.6)인 반면, 나머지 36개 파일은 70.6~100 사이에 촘촘히 이어진다.
# 두 번째로 큰 간격이 5.2 포인트뿐이라 "몇 % 이상" 을 가를 자연스러운 자리가 없다.
# 자를 곳은 하나다 — **한 번이라도 실행되는가.** R-dep 과 같은 이분 판정이라 임계가 없다.
#
# 문서 7곳의 "80%" 를 쓰지 않은 이유: 그 값을 적용하면 70.6·72.4·77.6 세 파일이 걸리는데,
# 분포상 이들은 82~86 무리와 구분되지 않는다. 근거 없는 경계다.
#
# 스위트 전체 실행에 수 분이 걸려 커밋 훅이 직접 측정할 수 없다. .cxbaseline 과 같이
# 사람이 측정하고 결과를 파일로 남긴다. 파일이 없으면 조용히 통과한다 — 미설정은 고장이 아니다.
COVBASE=".covbaseline"
if [[ -n "$PY_FILES" && -f "$COVBASE" ]]; then
  COV_DEAD=""
  while IFS= read -r f; do
    entry=$(grep -m1 -F "$f " "$COVBASE" 2>/dev/null || true)
    [[ -n "$entry" ]] || continue          # 측정 기록에 없는 새 파일은 판정하지 않는다
    [[ "${entry##* }" == 0/* ]] && COV_DEAD+="$f "
  done < <(printf '%s\n' "$PY_FILES")
  if [[ -n "$COV_DEAD" ]]; then
    WARNINGS+=("
[R-cov] 어떤 테스트도 실행하지 않는 파일을 수정한다: ${COV_DEAD% }
  → 이 변경은 스위트 전체를 돌려도 검증되지 않는다. 테스트를 붙이십시오.
     측정 갱신: $COVBASE 상단 주석 참조.
  근거: docs/design-docs/core-beliefs.md#r-cov")
  fi
fi

# 4-ter. R-dep — 모듈 의존 계약
#
# scripts/ 에 파이썬이 30개 이상인데 이들 사이의 의존 방향을 규정한 것이 없었다.
# .deprc 의 tier 는 손으로 적은 것이 아니라 실측 그래프에서 위상적으로 계산했다 —
# 새 규칙을 만드는 것이 아니라 이미 지켜지던 것을 고정한다.
# 도입 시점의 위반은 0건이므로 즉시 켜도 정상 코드가 막히지 않는다.
CHECK_DEP="$(dirname "$0")/depcheck.py"
if [[ -n "$PY_FILES" ]]; then
  if [[ ! -f "$CHECK_DEP" ]]; then
    WARNINGS+=("
[R-dep] 의존 계약 검사를 건너뜀 — depcheck.py 없음 (재설치 필요)")
  elif ! command -v python3 >/dev/null 2>&1; then
    WARNINGS+=("
[R-dep] 의존 계약 검사를 건너뜀 — python3 없음 (인터프리터 설치 필요)")
  else
    DEP_OUT=$(echo "$PY_FILES" | xargs python3 "$CHECK_DEP" 2>&1) || {
      VIOLATIONS+=("$(cat <<EOF

$DEP_OUT
EOF
)")
      FAIL=1
    }
    # R-dep-4(미등록 파일)·계약 부재는 차단하지 않는 경고다.
    if [[ -n "$DEP_OUT" ]] && [[ "$FAIL" -eq 0 ]]; then
      WARNINGS+=("
$DEP_OUT")
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

# 6. R-secret — 자격증명·개인정보 커밋 차단
#
# 다른 단계와 달리 파일 목록을 넘기지 않는다 — check-secrets.py 가 직접
# `git diff --cached` 를 읽는다. 여기서 걸러 넘기면 두 곳의 제외 규칙이
# 어긋날 때 조용히 검사 범위가 줄어든다.
#
# 왜 커밋 경계에 있어야 하는가: 마스킹(hermes_redact)은 DB·LLM 입력 경계에만
# 걸려 있어, 그 경계를 우회해 파일로 들어온 값은 잡지 못한다. git 히스토리는
# 되돌릴 수 없으므로 여기가 마지막 방어선이다.
CHECK_SECRETS="$(dirname "$0")/check-secrets.py"
if [[ -f "$CHECK_SECRETS" ]] && command -v python3 >/dev/null 2>&1; then
  SECRET_OUT=$(python3 "$CHECK_SECRETS" 2>&1) || {
    VIOLATIONS+=("$(cat <<EOF

$SECRET_OUT
EOF
)")
    FAIL=1
  }
fi

# 7. R-plan — 완료된 계획이 active/ 에 남아있으면 경고
#
# 검사 대상은 **이번 커밋에 스테이징된 계획서만**이다(2026-07-23 변경).
# 이전에는 find 로 active/ 전체를 스캔해, 커밋에 포함되지도 않은 남의 계획서가 완료 상태이면
# 무관한 커밋까지 막혔다. 여러 세션이 워킹트리를 공유하면 서로를 영구히 막는다.
# 막힌 쪽은 남의 회고를 대신 쓸 수 없어 해결책이 없고, 출구가 --no-verify 뿐이라 규율 전체가
# 무력화된다. 규칙 의도("내가 끝낸 계획을 방치하지 말 것")를 지키는 최소 범위로 좁혔다.
# 트레이드오프: 아무도 손대지 않은 방치 계획서는 못 잡는다 — 그건 주기 점검(문서 가드닝)의 몫.
ACTIVE_DIR="docs/exec-plans/active"
if (( PLAN_STATE_OK )) && [[ -d "$ACTIVE_DIR" ]]; then
  while IFS= read -r plan; do
    [[ -f "$plan" ]] || continue
    # set -e 아래에서는 `cmd; rc=$?` 가 훅 전체를 중단시킨다. 반드시 `|| rc=$?` 를 쓴다.
    rc=0; python3 "$PLAN_STATE" is-complete "$plan" || rc=$?
    case $rc in
      0)
        VIOLATIONS+=("
[R-plan] 완료된 계획이 active/ 에 남아있음: $plan
  → 회고(§8) 작성 후 \`git mv \"$plan\" \"docs/exec-plans/completed/\$(basename \"$plan\")\"\`.
     (2026-08-13 계수 규칙 변경: 마크다운 링크 불릿은 더 이상 체크박스로 세지 않는다.)
  근거: docs/design-docs/core-beliefs.md#r-plan")
        FAIL=1
        ;;
      2)
        WARNINGS+=("
[R-plan] 계획서 판정 불가: $plan — 마크다운 형식을 확인하십시오.")
        ;;
    esac
  done < <(filter_files "^${ACTIVE_DIR}/[^/]+\.md$")

  # 7-bis. R-acc-1 — §2 목표가 실행 가능한 형태인가 (경고)
  #
  # 템플릿은 §2 에 "검증 가능한 형태" 를 이미 요구하지만 형식이 없어 산문으로 채워지고,
  # 그 문장이 실제로 검증되는지는 아무도 보지 않았다. 목표마다 확인 명령을 붙이게 한다.
  #
  # 명령을 실행하지는 않는다. 계획서는 에이전트가 쓰는 파일이고, 거기 적힌 것을
  # 커밋 훅이 실행하면 게이트가 게이트 대상에게 실행 권한을 넘기는 것이 된다.
  #
  # 스테이징된 계획서만 본다 — active/ 전체를 훑으면 남의 옛 형식 계획서까지 걸려
  # 무관한 커밋이 매번 경고를 받는다. R-plan 이 2026-07-23 에 같은 이유로 좁힌 범위다.
  while IFS= read -r plan; do
    [[ -f "$plan" ]] || continue
    rc=0; BARE=$(python3 "$PLAN_STATE" goals-unverified "$plan" 2>/dev/null) || rc=$?
    [[ "$rc" -eq 0 && -n "$BARE" ]] || continue
    WARNINGS+=("
[R-acc] §2 목표에 검증 명령이 없음: $plan
$(echo "$BARE" | head -3 | sed 's/^/    /')
  → 목표마다 그것을 확인하는 명령을 붙이십시오 (예: \`bash tests/foo-test.sh\`).
  근거: docs/design-docs/core-beliefs.md#r-acc")
  done < <(filter_files "^${ACTIVE_DIR}/[^/]+\.md$")
fi

# 8. R-plan-missing / R-plan-stale — 계획서가 코드를 따라오는가 (둘 다 경고)
#
# R-plan 이 "스테이징된 계획서" 만 보는 순환 의존을 뒤집는 축이다. 차단하지 않는 이유는
# 계획서 1개일 때 차단하면 워킹트리 공유 시 상호 차단이 발생하기 때문이다
# (2026-07-23 사고, tests/harness-hooks-smoke.sh 13(a) 가 그 회귀를 고정하고 있다).
if (( PLAN_STATE_OK )) && [[ -n "$WORK_FILES" && -d "$ACTIVE_DIR" ]]; then
  ACTIVE_PLANS=()
  while IFS= read -r p; do
    ACTIVE_PLANS+=("$p")
  done < <(find "$ACTIVE_DIR" -maxdepth 1 -name '*.md' ! -name 'template.md' -type f 2>/dev/null | sort)
  STAGED_PLANS=$(filter_files "^${ACTIVE_DIR}/[^/]+\.md$")

  if [[ ${#ACTIVE_PLANS[@]} -eq 0 ]]; then
    WARNINGS+=("
[R-plan-missing] 코드 수정 있으나 active/ 에 계획 없음.
  → 단순 버그(1~2파일)면 무시. 다중 파일·설계 결정이면 docs/exec-plans/active/YYYY-MM-DD-<slug>.md 작성.
  근거: docs/design-docs/core-beliefs.md#r-plan-missing")
  elif [[ -z "$STAGED_PLANS" ]]; then
    # 일부라도 스테이징돼 있으면 통과시킨다 — 어느 계획에 속한 커밋인지 훅은 알 수 없고,
    # 경고를 남발하면 되살린 경고 채널이 다시 무시된다.
    WARNINGS+=("
[R-plan-stale] 코드는 바뀌었는데 계획서가 따라오지 않음.
  active/: ${ACTIVE_PLANS[*]}
  → 진행분을 계획서에 반영하십시오 (§2 체크박스, §6 의사결정 로그, §7 발견).
     신규 계획서라면 git add 가 필요합니다.
  근거: docs/design-docs/core-beliefs.md#r-plan-stale")
  fi
fi

# 8-bis. R-pipe — 리뷰 빚을 안은 채 커밋하는가 (경고)
#
# .claude/.review-dirty 는 2026-04-15 부터 기록만 되고 아무 판정에도 쓰이지 않았다.
# 그런데 core-beliefs.md#r-review 는 "안 지우면 commit 단계에서 차단" 이라 적고 있었다 —
# 존재하지 않는 강제를 문서가 주장한 것이다(R-test 와 같은 결함, 2026-08-24 발견).
#
# 차단이 아니라 경고인 이유: 훅은 "리뷰어를 불렀다"까지만 알 수 있고
# "리뷰가 유효했다"는 알 수 없다. 확인 못 하는 것을 차단 조건으로 삼으면
# 리뷰어를 부르고 결과를 무시하는 형식적 통과를 학습시킨다.
#
# 청산은 claude-posttooluse-review-record.sh 가 리뷰어 dispatch 시 자동으로 한다.
DIRTY_FILE=".claude/.review-dirty"
if [[ -n "$WORK_FILES" && -f "$DIRTY_FILE" ]]; then
  # 기록된 경로 중 이번 커밋에 실제로 들어간 것만 센다. 기록은 세션 단위로 누적되므로
  # 그대로 나열하면 이 커밋과 무관한 파일까지 보여 경고가 무시된다.
  DIRTY_STAGED=$(
    awk '{ print $NF }' "$DIRTY_FILE" 2>/dev/null | sort -u | while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      printf '%s\n' "$WORK_FILES" | grep -qxF "$p" && echo "$p"
    done | head -5
  )
  if [[ -n "$DIRTY_STAGED" ]]; then
    WARNINGS+=("
[R-pipe] 리뷰 기록 없이 커밋되는 파일: $(echo "$DIRTY_STAGED" | tr '\n' ' ')
  → 자연 단위가 끝났으면 code-reviewer(또는 도메인 리뷰어)를 dispatch 하십시오.
     작업 중간이면 무시해도 됩니다. 수동 청산: rm $DIRTY_FILE
  근거: docs/design-docs/core-beliefs.md#r-review")
  fi
fi

# 9. R-retro — completed/ 로 옮긴 계획서에 회고가 있는가 (경고)
#
# filter_files 를 쓸 수 없다. STAGED 는 --diff-filter=ACM 인데 git mv 는 rename(R100)
# 으로 분류돼 그 필터에 잡히지 않는다(2026-08-13 실측). 자체 git 호출을 쓰되
# STAGED 자체는 건드리지 않는다 — 바꾸면 다른 모든 검사의 범위가 함께 바뀐다.
#
# M(수정)은 뺀다. 넣으면 옛 계획서의 오타 수정도 걸려, 자기가 하지도 않은 작업의
# 회고를 지어내야 한다. 이 검사의 근거는 "completed/ 로 옮기는 행위가 완료 선언" 이다.
if (( PLAN_STATE_OK )); then
  while IFS= read -r moved; do
    [[ -n "$moved" && -f "$moved" ]] || continue
    rc=0; python3 "$PLAN_STATE" retro-empty "$moved" || rc=$?
    case $rc in
      0)
        WARNINGS+=("
[R-retro] 회고 없이 완료 처리됨: $moved
  → §8 세 항목(잘된 것 / 잘못된 것 / 다음 룰 후보) 중 최소 하나를 채우십시오.
  근거: docs/design-docs/core-beliefs.md#r-retro")
        ;;
      2)
        WARNINGS+=("
[R-retro] 회고 판정 불가: $moved — 마크다운 형식을 확인하십시오.")
        ;;
    esac

    # 9-bis. R-acc-2 — §2 목표가 미완인 채 완료 처리되는가 (경고)
    #
    # R-retro 와 같은 지점에서 발화한다. 훅을 새로 만들지 않는 이유는 판정 계기가
    # 같기 때문이다 — completed/ 로 옮기는 행위가 완료 선언이고, R-retro 가 §8 을
    # 보는 자리에서 §2 도 함께 본다.
    rc=0; GOALS=$(python3 "$PLAN_STATE" goals-pending "$moved" 2>/dev/null) || rc=$?
    if [[ "$rc" -eq 0 && -n "$GOALS" ]]; then
      WARNINGS+=("
[R-acc] 미완 목표를 남긴 채 완료 처리됨: $moved
$(echo "$GOALS" | head -3 | sed 's/^/    /')
  → 달성했으면 체크하고, 못 했으면 회고(§8)에 이유를 남기십시오.
  근거: docs/design-docs/core-beliefs.md#r-acc")
    fi
  done < <(git diff --cached --name-only --diff-filter=RA -- docs/exec-plans/completed/ 2>/dev/null || true)
fi

# 출력 — 경고가 먼저 나간다. 차단 여부와 무관하게 항상 보여야 한다.
if (( ${#WARNINGS[@]} )); then
  echo ""
  echo "────────────────────────────────────────────────────────────────────"
  echo "  하네스 경고 — 차단하지 않음. 판단은 작업자 몫."
  echo "────────────────────────────────────────────────────────────────────"
  for w in "${WARNINGS[@]}"; do echo "$w"; done
fi

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
