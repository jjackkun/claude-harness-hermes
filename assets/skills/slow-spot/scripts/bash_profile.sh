#!/usr/bin/env bash
# bash_profile.sh — bash 스크립트를 시각을 찍은 xtrace 로 한 번 돌려 추적 파일을 남긴다.
#
#   bash bash_profile.sh <추적 파일> <스크립트> [인자...]
#
# 추적 줄 모양: +@<EPOCHREALTIME>@<파일>:<줄>@<함수>@ <명령>   (trace_agg.py 가 읽는다)
# - 스크립트가 source 한 라이브러리 줄도 잡힌다. `bash 다른.sh` 로 따로 띄운 자식은 잡히지 않는다 —
#   자식이 범인으로 보이면 그 자식을 이 도구로 따로 잰다.
# - 추적은 BASH_XTRACEFD 로 따로 낸다 — 스크립트가 `2>파일` 로 표준 오류를 돌려도 그 안의 추적 줄이 빠지지 않고,
#   스크립트의 표준 출력·표준 오류는 그대로 지나간다(2026-11-25 harness-eval-test 에서 함수 안 줄이 통째로 빠졌다).
# - xtrace 는 줄마다 시각을 찍으므로 전체 시간이 1.1~1.3배 늘어난다. 비율을 보고, 절대 시간은 추적 없이 따로 잰다.
# 종료 코드는 스크립트의 것을 그대로 돌려준다.

set -u
if [[ $# -lt 2 ]]; then
  echo "사용법: bash_profile.sh <추적 파일> <스크립트> [인자...]" >&2
  exit 2
fi
trace="$1"; shift
if [[ ! -f "$1" ]]; then
  echo "스크립트가 없습니다: $1" >&2
  exit 2
fi
mkdir -p "$(dirname "$trace")"
# shellcheck disable=SC2016  # PS4 는 추적할 때 펼쳐져야 한다
exec {fd}> "$trace" || { echo "추적 파일을 열지 못했습니다: $trace" >&2; exit 2; }
PS4='+@${EPOCHREALTIME}@${BASH_SOURCE[0]##*/}:${LINENO}@${FUNCNAME[0]:-main}@ ' BASH_XTRACEFD="$fd" bash -x "$@"
rc=$?
# 끝 표식 — 시간은 "다음 추적 줄까지" 로 재므로, 이 줄이 없으면 스크립트의 마지막 명령 시간이 0 으로 사라진다.
printf '+@%s@(끝):0@main@ (끝)\n' "$EPOCHREALTIME" >&"$fd"
exec {fd}>&-
echo "추적: $trace ($(wc -l < "$trace") 줄) · 종료 코드 $rc" >&2
exit "$rc"
