#!/usr/bin/env bash
# lib/pyenv_bypass.sh
# Responsibility: pyenv shim 을 건너뛰고 대상 폴더 기준의 실제 python3 를 PATH 앞에 둔다.
# 쓰는 곳: lib/common.sh(설치기) · tests/run-all.sh(시험 러너). Sourced, not executed directly.

# ── pyenv shim 우회 ───────────────────────────────────────────────────────────
# shim 은 python3 를 부를 때마다 어느 버전을 쓸지 따지고, 그 과정이 이 환경에서 비정상적으로
# 느리다(2026-09-23 실측: 셔임 112ms vs 실제 19ms, 6배. 내부에서 grep 을 수만 번 돈다).
# 설치 한 번이 python3 를 286번 부르므로 그대로 쌓인다 — 설치 36.6초 중 26초가 이 비용이었다.
# `pyenv which` 가 **셔임이 고를 바로 그 바이너리**를 주므로 버전은 같고 따지는 단계만 건너뛴다.
# 끄기: HARNESS_NO_PYENV_BYPASS=1
# **실행 폴더($PWD) 기준으로 고른다 — shim 이 하던 그대로다.** 설치 **대상** 폴더 기준으로
# 고르면 안 된다: 여기서 도는 python 은 대상 프로젝트의 코드가 아니라 **공장의 설치 도구**이고,
# 대상이 `.python-version` 에 옛 버전(예: 3.7)을 박아 두면 설치 도구가 그 버전으로 돌다가 깨진다
# (2026-09-23 리뷰 지적 — 한때 대상 기준으로 바꿨다가 되돌렸다).
# 한계: 한 프로세스 안에서는 시작 시점의 폴더로 고정된다. 도중에 cd 한 뒤의 python3 호출도
# 같은 버전을 쓴다(shim 은 호출마다 다시 골랐다). 설치기는 python 을 부르며 폴더를 옮기지 않는다.
harness_pyenv_bypass() {
  local real
  [[ "${HARNESS_NO_PYENV_BYPASS:-0}" == "1" ]] && return 0
  # ① 앞선 우회를 **먼저** PATH 에서 뺀다. 순서가 중요하다 — 빼지 않고 셔임 검사를 하면
  #    python3 가 이미 우회 경로를 가리켜 "셔임 아님" 으로 빠져나가고, 다음 프로젝트는 앞
  #    프로젝트의 버전을 그대로 쓴다(2026-09-23 리뷰 지적: 프로젝트별 재계산이 실제로는 안 돌았다).
  #    폴더는 **이 프로세스가 만든 것만** 지운다 — 부모에게서 물려받은 것은 부모가 정리한다.
  if [[ -n "${_HARNESS_PYBIN:-}" ]]; then
    PATH="${PATH//"$_HARNESS_PYBIN:"/}"
    [[ "${_HARNESS_PYBIN_PID:-}" == "$$" ]] && rm -rf "$_HARNESS_PYBIN"
    unset _HARNESS_PYBIN _HARNESS_PYBIN_PID
  fi
  # ② 이제 진짜 python3 가 셔임인지 본다
  [[ "$(command -v python3 2>/dev/null)" == *"/.pyenv/shims/"* ]] || return 0
  real="$(pyenv which python3 2>/dev/null || true)"   # 지금 폴더 기준 — shim 과 같은 답
  [[ -x "$real" ]] || return 0
  _HARNESS_PYBIN="$(mktemp -d)"; _HARNESS_PYBIN_PID=$$
  ln -sf "$real" "$_HARNESS_PYBIN/python3"
  ln -sf "$real" "$_HARNESS_PYBIN/python"
  PATH="$_HARNESS_PYBIN:$PATH"; export PATH _HARNESS_PYBIN _HARNESS_PYBIN_PID
}

# harness_pyenv_cleanup — 이 프로세스가 만든 우회 폴더만 지운다. 설치기·러너의 EXIT 에서 부른다.
# 자식 프로세스는 _HARNESS_PYBIN 을 물려받지만 PID 가 달라 부모 폴더를 지우지 않는다.
harness_pyenv_cleanup() {
  [[ -n "${_HARNESS_PYBIN:-}" && "${_HARNESS_PYBIN_PID:-}" == "$$" ]] && rm -rf "$_HARNESS_PYBIN"
  return 0
}
