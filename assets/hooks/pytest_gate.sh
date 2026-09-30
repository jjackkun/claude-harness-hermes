#!/usr/bin/env bash
# R-test 게이트가 쓰는 도우미 — pytest 고르기 · 결과 요약 읽기 · 시간/건너뜀 경고 문구.
# pre-commit 이 `$(dirname $0)` 에서 source 한다(gate_emit.sh 와 같은 부류). 없으면 pre-commit 이 옛 동작으로 돈다.
# 계획: docs/exec-plans/completed/2026-09-30-test-speed-gate.md 목표 1·2

# 프로젝트 가상환경을 먼저 — uv 가 만드는 `.venv` 가 먼저, 옛 `venv` 다음. 없으면 시스템.
# 가상환경 폴더가 **있는데** 그 안에 pytest 가 없어 시스템으로 떨어진 경우만 경고 대상이다 — 가상환경 없이
# 시스템 pytest 를 쓰는 프로젝트(이 공장처럼)는 정상이라 매 커밋 경고하면 경고 피로만 생긴다.
PYTEST_VENV_DIRS=(backend/.venv backend/venv .venv venv)
pytest_pick_bin() {
  local dir
  for dir in "${PYTEST_VENV_DIRS[@]}"; do
    [[ -x "$dir/bin/pytest" ]] && { echo "$dir/bin/pytest"; return 0; }
  done
  command -v pytest >/dev/null 2>&1 && echo "pytest"
}

pytest_unused_venv() {   # 가상환경 폴더가 있는데 pytest 가 없으면 그 폴더 이름, 아니면 빈 문자열
  local dir
  for dir in "${PYTEST_VENV_DIRS[@]}"; do
    [[ -d "$dir" && ! -x "$dir/bin/pytest" ]] && { echo "$dir"; return 0; }
  done
}

# pytest -q 출력의 마지막 요약 줄에서 "N <낱말>" 의 N 을 뽑는다. 없으면 0.
pytest_count() {   # pytest_count <출력> <passed|skipped|failed>
  local line
  line=$(printf '%s\n' "$1" | grep -E '[0-9]+ (passed|failed|skipped|error)' | tail -1)
  printf '%s\n' "$line" | grep -oE "[0-9]+ $2" | grep -oE '^[0-9]+' | head -1 || true
}

# 통과여도 알릴 것들(시간·건너뜀·시스템 대체)을 경고 문구로 돌려준다. 없으면 빈 문자열.
# 기준 초: 에이전트 도구 한도(600초)의 절반 — 전체 시험을 앞에서 기다리기 위험해지는 선. 시험은 HARNESS_RTEST_WARN_SEC 로 낮춘다.
pytest_notes() {   # pytest_notes <걸린 초> <출력>
  local secs="$1" out="$2" limit="${HARNESS_RTEST_WARN_SEC:-300}" passed skipped notes=""
  passed=$(pytest_count "$out" passed); skipped=$(pytest_count "$out" skipped)
  if (( secs > limit )); then
    notes+="
[R-test] pytest 가 ${secs}초 걸렸다(기준 ${limit}초) — 오래 걸렸다.
  CPU 를 거의 안 쓰고 오래 걸렸다면 기다림이 원인이다 — 시험 DB 가 원격(터널·다른 PC)인지 먼저 본다.
  근거: docs/design-docs/core-beliefs.md#r-test"
  fi
  if (( ${skipped:-0} > ${passed:-0} )); then
    notes+="
[R-test] 대부분 건너뜀(통과 ${passed:-0} · 건너뜀 ${skipped:-0}) — 시험 DB 가 꺼져 있거나 닿지 않을 수 있다. 통과로 기록됐지만 검증된 것은 적다.
  근거: docs/design-docs/core-beliefs.md#r-test"
  fi
  local unused
  unused=$(pytest_unused_venv)
  if [[ "${PYTEST_FROM_SYSTEM:-0}" == 1 && -n "$unused" ]]; then
    notes+="
[R-test] 가상환경($unused)이 있는데 그 안에 pytest 가 없어 시스템 pytest 로 돌았다 — 프로젝트 의존성으로 검증됐다는 보증이 없다.
  → 그 가상환경에 pytest 를 설치하십시오(uv 면 dev 의존성에 pytest).
  근거: docs/design-docs/core-beliefs.md#r-test"
  fi
  printf '%s' "$notes"
}
