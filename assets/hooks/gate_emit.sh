#!/usr/bin/env bash
# 셸 훅이 게이트 판정 1건을 기록할 때 쓰는 호출 규약.
#
# 근거: docs/design-docs/core-beliefs.md — Provisional 룰의 발화율 관측.
#
# 단일 책임: **모듈 탐색과 인자 조립**. 레코드 형식과 저장 위치의 주인은 `gate_event.py` 다.
# 이 파일이 스키마를 알면 정의가 둘이 되고, 그러면 반드시 갈라진다.
#
# 왜 별도 파일인가: 훅은 서로를 source 하지 않지만 **같은 디렉터리의 형제 파일**은 쓴다
#   (`size-warn` → `iface_width.py`, `plan-declare` → `plan_state.py`).
#   같은 9줄을 훅 7개에 복사하면 호출 규약이 갈라진다.
#
# 사용법:
#   source "$(dirname "$0")/gate_emit.sh"   # 실패해도 훅은 계속된다
#   gate_emit R-size warn posttooluse "$FILE_PATH" "520줄 > 500"
#
# **판정이 실제로 일어난 지점에서만 부른다.** 대상 아님으로 조기 반환하는 경로
# (확장자 불일치, 기존 파일, 계획 부재 등)에서 부르면 분모가 오염된다 —
# 발화율은 "룰을 평가한 횟수" 분의 "발화한 횟수" 이지, 훅이 실행된 횟수가 아니다.

# 이미 정의돼 있으면 덮어쓰지 않는다 (중복 source 방지).
if ! declare -F gate_emit >/dev/null 2>&1; then

_GATE_EVENT_MOD=""
for _gate_cand in \
  "$(dirname "${BASH_SOURCE[0]}")/gate_event.py" \
  "scripts/hooks/gate_event.py" \
  ".git/hooks/gate_event.py"
do
  if [[ -f "$_gate_cand" ]]; then
    _GATE_EVENT_MOD="$_gate_cand"
    break
  fi
done
unset _gate_cand

# 쌓아 두었다가 훅이 끝날 때 **한 번에** 쓴다.
# 한 훅이 축을 둘 이상 판정할 때 축마다 프로세스를 띄우면 관측 비용이 게이트 비용을 넘는다
# (실측 2026-09-03: 기동 1회 21ms, size-warn 훅 자체가 32ms — 두 번 띄우면 +134%).
_GATE_PENDING=()

# gate_add <rule> <verdict> <stage> [path] [detail] — 기록할 판정을 쌓는다.
gate_add() {
  [[ -n "$_GATE_EVENT_MOD" ]] || return 0
  local rule="${1:-}" verdict="${2:-}" stage="${3:-}" path="${4:-}" detail="${5:-}"
  [[ -n "$rule" && -n "$verdict" ]] || return 0
  [[ ${#_GATE_PENDING[@]} -gt 0 ]] && _GATE_PENDING+=("+")
  _GATE_PENDING+=(--rule "$rule" --verdict "$verdict")
  [[ -n "$stage" ]] && _GATE_PENDING+=(--stage "$stage")
  [[ -n "$path" ]] && _GATE_PENDING+=(--path "$path")
  [[ -n "$detail" ]] && _GATE_PENDING+=(--detail "$detail")
  return 0
}

# gate_flush — 쌓인 판정을 프로세스 1회로 기록한다. 훅 종료 시 자동 호출된다.
gate_flush() {
  [[ -n "$_GATE_EVENT_MOD" ]] || return 0
  [[ ${#_GATE_PENDING[@]} -gt 0 ]] || return 0
  python3 "$_GATE_EVENT_MOD" emit "${_GATE_PENDING[@]}" >/dev/null 2>&1 || true
  _GATE_PENDING=()
  return 0
}

# gate_emit <rule> <verdict> <stage> [path] [detail] — 축이 하나뿐인 훅용 (쌓고 즉시 flush).
gate_emit() {
  gate_add "$@"
  gate_flush
}

# 조기 `exit 0` 로 빠져나가는 훅이 많다. 쌓인 것을 잃지 않도록 종료 시 flush 한다.
# 이미 EXIT trap 이 걸린 훅은 건드리지 않는다 — 남의 정리 코드를 덮어쓰면 그쪽이 조용히 깨진다.
if [[ -z "$(trap -p EXIT)" ]]; then
  trap gate_flush EXIT
fi

fi
