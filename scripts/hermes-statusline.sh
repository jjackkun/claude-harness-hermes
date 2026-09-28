#!/usr/bin/env bash
# 헤르메스 상태줄 감싸개 — 원래 상태줄(같은 폴더의 hermes-statusline.orig 명령)을 그대로 찍고,
# 헤르메스가 깔린 프로젝트면 "이 방" 한 줄(hermes-agent.py room --line)을 더한다.
# 설치기(scripts/hermes_statusline_setup.py)가 전역 설정 폴더에 복사해 statusLine 명령으로 건다 — 사용자 상태줄 스크립트는 고치지 않는다.
# 되돌리기: settings.json 의 statusLine.command 를 hermes-statusline.orig 내용으로. 다시 걸지 않게: HERMES_STATUSLINE=0 으로 설치.
# 계획: docs/exec-plans/active/2026-09-28-agent-room-view.md 목표 6
input=$(cat)
dir="$(cd "$(dirname "$0")" && pwd)"
out=""
if [ -s "$dir/hermes-statusline.orig" ]; then
  out=$(printf '%s' "$input" | bash -c "$(cat "$dir/hermes-statusline.orig")" 2>/dev/null)
fi
{ IFS= read -r project_dir; IFS= read -r session_id; } < <(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    d = {}
print((d.get("workspace") or {}).get("project_dir") or d.get("cwd") or "")
print(d.get("session_id") or "")' 2>/dev/null)
room=""
if [ -n "${session_id:-}" ] && [ -f "${project_dir:-}/scripts/hermes-agent.py" ] && [ -f "$project_dir/.hermes/agents.json" ]; then
  room=$(timeout 1 python3 "$project_dir/scripts/hermes-agent.py" --project "$project_dir" room --session "$session_id" --line 2>/dev/null)
fi
if [ -n "$out" ] && [ -n "$room" ]; then printf '%s\n%s' "$out" "$room"; else printf '%s%s' "$out" "$room"; fi
