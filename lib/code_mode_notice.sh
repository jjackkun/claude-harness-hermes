#!/usr/bin/env bash
# Code Mode 안내 — setup·update-all 이 끝날 때 한 번, 이 컴퓨터에서 Code Mode 가 꺼져 있으면 켜는 법을 한 줄로 알린다.
# 왜: Code Mode 는 사용자 설정(~/.claude/settings.json 의 env)에서만 켜진다. 공장은 사용자 전역 설정을 고치지 않으므로
#     새 컴퓨터에서는 꺼진 채로 남고 아무도 알려 주지 않는다. 읽기만 하고 아무것도 고치지 않는다. 언제나 0 으로 끝난다.
# 계획: docs/exec-plans/completed/2026-11-16-code-mode-notice.md · 실측: docs/audits/2026-11-16-code-mode-hooks.md
set -uo pipefail

MIN_VERSION="2.1.323"
MODE_VAR="CLAUDE_CODE_EXPERIMENTAL_CODE_MODE"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

find_claude() {
  if [[ -n "${CODE_MODE_NOTICE_CLAUDE:-}" ]]; then [[ -x "$CODE_MODE_NOTICE_CLAUDE" ]] && echo "$CODE_MODE_NOTICE_CLAUDE"; return; fi
  command -v claude 2>/dev/null && return
  [[ -x "$HOME/.local/bin/claude" ]] && echo "$HOME/.local/bin/claude"
}

# 사용자 설정의 env 값: 값 · 빈 문자열(없음) · "?"(읽지 못함)
settings_value() {
  [[ -f "$SETTINGS" ]] || return 0
  python3 -I - "$SETTINGS" "$MODE_VAR" <<'PY' 2>/dev/null || echo "?"
import json, sys
env = json.load(open(sys.argv[1], encoding="utf-8")).get("env") or {}
print(env.get(sys.argv[2], ""))
PY
}

version_at_least() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }

main() {
  [[ -n "${!MODE_VAR:-}" ]] && return 0                # 셸에서 이미 켰거나 껐다
  local claude ver value
  claude=$(find_claude) || return 0
  [[ -n "$claude" ]] || return 0
  ver=$("$claude" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [[ -n "$ver" ]] || return 0
  value=$(settings_value)
  if [[ "$value" == "?" ]]; then
    echo "ℹ Code Mode: $SETTINGS 를 읽지 못해 켜짐 여부를 확인하지 않았습니다(JSON 확인)."
    return 0
  fi
  [[ -n "$value" ]] && return 0                       # 1(켬) 또는 0(일부러 끔)
  if version_at_least "$ver" "$MIN_VERSION"; then
    echo "ℹ Code Mode 가 이 컴퓨터에서 꺼져 있습니다(도구를 코드로 묶어 불러 사용량을 줄이는 실험 기능, 터미널 claude 전용). 컴퓨터마다 한 번, $SETTINGS 의 \"env\" 에 \"$MODE_VAR\": \"1\" 을 넣으면 켜집니다."
  else
    echo "ℹ Code Mode: 이 컴퓨터의 클로드 코드는 $ver 입니다. $MIN_VERSION 이상(claude update)이면 켤 수 있습니다(컴퓨터마다 사용자 설정 한 줄)."
  fi
}

main
exit 0
