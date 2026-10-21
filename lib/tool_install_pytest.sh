#!/usr/bin/env bash
# pytest 를 **그 프로젝트의 가상환경에만** 설치한다. tool_installers.sh 가 source 한다.
# 왜 가상환경: 파이썬 패키지를 전역(시스템·apt·~/.local)에 깔면 다른 프로젝트의 파이썬 환경에 영향을 준다
# (사용자 지시 2026-10-21). sudo 도 쓰지 않는다 — 비밀번호 대기로 설치기가 멈출 일이 없다.
# 계획: docs/exec-plans/active/2026-10-21-pytest-required-bin.md

# 핀 — 소우주에서 실제로 도는 pytest(terminal-shipping backend/.venv)의 판(2026-10-21 실측). 공급망 원칙.
_PYTEST_SPEC="pytest==9.1.1"
# R-test 가 고르는 순서와 같다(assets/hooks/pytest_gate.sh PYTEST_VENV_DIRS). 다르면 깐 것을 게이트가 못 쓴다.
_PYTEST_VENV_DIRS=(backend/.venv backend/venv .venv venv)
_PYTEST_RESULT=""   # present | installed | skipped | failed

# R-test 가 돌 프로젝트인가 — tests/ 또는 backend/tests/ 아래 파이썬 시험 파일이 있다
_pytest_needed() {   # <project>
  local d
  for d in "$1/tests" "$1/backend/tests"; do
    [[ -d "$d" ]] || continue
    [[ -n "$(find "$d" -maxdepth 4 \( -name 'test_*.py' -o -name '*_test.py' \) -print -quit 2>/dev/null)" ]] && return 0
  done
  return 1
}

_pytest_venv_of() {   # <project> → 첫 가상환경 폴더(절대 경로), 없으면 빈 문자열
  local d
  for d in "${_PYTEST_VENV_DIRS[@]}"; do [[ -x "$1/$d/bin/python" ]] && { echo "$1/$d"; return 0; }; done
  return 0   # 못 찾음도 정상 — 마지막 [[ -x ]] 의 1 이 새면 set -e 인 설치기가 조용히 죽는다(2026-10-21 zeroday-frontend)
}

# 있음 = 실행된다. `bin/pytest` 파일만 남고 모듈이 없는 가상환경이 있다(2026-10-21 실측 3곳).
_pytest_runs_in() { [[ -x "$1/bin/pytest" ]] && "$1/bin/pytest" --version >/dev/null 2>&1; }

_pytest_ensure() {   # <project> → _PYTEST_RESULT 를 정한다. 실패해도 0 (설치기를 세우지 않는다)
  local project="$1" venv rel
  if ! _pytest_needed "$project"; then
    _PYTEST_RESULT=skipped; log_info "  pytest: 파이썬 시험이 없는 프로젝트 — 가상환경을 만들지 않습니다"; return 0
  fi
  venv="$(_pytest_venv_of "$project")"
  if [[ -n "$venv" ]] && _pytest_runs_in "$venv"; then _PYTEST_RESULT=present; return 0; fi
  if [[ -z "$venv" ]]; then
    venv="$project/.venv"
    if ! python3 -m venv "$venv" >/dev/null 2>&1; then
      _PYTEST_RESULT=failed
      log_warn "  pytest: 가상환경을 만들지 못했습니다 — 프로젝트 폴더에서 손으로: python3 -m venv .venv && .venv/bin/python -m pip install $_PYTEST_SPEC"
      return 0
    fi
  fi
  rel="${venv#"$project"/}"
  if "$venv/bin/python" -m pip install -q "$_PYTEST_SPEC" >/dev/null 2>&1 && _pytest_runs_in "$venv"; then
    _PYTEST_RESULT=installed; log_info "  tool → $_PYTEST_SPEC → $rel (이 프로젝트 가상환경에만)"
  else
    _PYTEST_RESULT=failed; log_warn "  pytest: $rel 에 설치하지 못했습니다 — 프로젝트 폴더에서 손으로: $rel/bin/python -m pip install $_PYTEST_SPEC"
  fi
  return 0
}
