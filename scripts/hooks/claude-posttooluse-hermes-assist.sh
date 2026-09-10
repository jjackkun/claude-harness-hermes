#!/usr/bin/env bash
# PostToolUse(Bash) hook — 에이전트가 터미널 실패에 부딪힌 순간 관련 헤르메스 스킬을 주입한다.
#
# 근거: docs/superpowers/specs/2026-07-09-hermes-injection-trigger-design.md (C1)
#       assets/hooks/claude-settings-hooks.json — "어려움을 신호로 간주"
#       docs/audits/2026-07-08-hermes-skill-utilization-gap.md — 주입 원장 3행, helpful 0
#
# 동작 (2단계 게이트):
#   1단계 — JSON 원문을 grep. 신호가 없으면 python 을 아예 띄우지 않는다(정상 경로 비용 ≈ 0).
#   2단계 — python 으로 파싱해 tool_name==Bash 이고 tool_response 안에서 매칭되는지 재확인.
#           1단계는 `grep 401 access.log` 같은 명령어 문자열에도 반응하므로 여기서 걸러낸다.
#
# stdout 은 에이전트 컨텍스트로 들어간다. 진단 로그를 절대 stdout 에 쓰지 않는다.
# 항상 exit 0 (비차단).
#
# 등록: presets/workflow/hermes.conf 의 POST_TOOL_USE_HOOKS (matcher: Bash)

set -uo pipefail

# 재귀 방지 — hermes-search 가 내부적으로 claude -p 를 띄울 때 설정하는 변수.
[[ "${HERMES_DISABLED:-0}" == "1" ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

_repo_root="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)" || exit 0
cd "${CLAUDE_PROJECT_DIR:-$_repo_root}" 2>/dev/null || exit 0

_db="$PWD/.hermes/state.db"
_search="$_repo_root/scripts/hermes-search.py"
[[ -f "$_db" && -f "$_search" ]] || exit 0

_payload="$(cat /dev/stdin 2>/dev/null || true)"
[[ -n "$_payload" ]] || exit 0

# 터미널 실패 신호 — "에이전트가 접근 방식을 바꿔야만 넘어갈 수 있는 실패"만 포함한다 (설계 §4.3).
# 대소문자 구분. -i 를 쓰면 FAILED 가 로그의 일상적인 'failed' 까지 잡아 정밀도가 무너진다.
# 기각: error:/Error(비종결적·상시 등장), No such file or directory(에이전트가 즉시 자기 수정).
_SIGNAL_RE='\b401\b|\b403\b|[Uu]nauthorized|[Ff]orbidden|[Pp]ermission denied|command not found|Traceback \(most recent call last\)|\bFAILED\b|AssertionError'

# 1단계 게이트 — 원문 grep. 미매칭이면 여기서 끝.
# 파이프(printf | grep -q) 금지: set -o pipefail 하에서 grep -q 가 조기 매칭 시
# 즉시 종료하면 좌변 printf 가 SIGPIPE(141)로 죽고 pipefail 이 그 상태를 파이프라인
# 종료코드로 승격시켜 `|| exit 0` 가 오작동한다(신호를 찾고도 조용히 무주입).
# GNU grep 에서 재현되는 환경 의존 버그이므로 히어스트링으로 파이프 자체를 없앤다.
grep -Eq "$_SIGNAL_RE" <<<"$_payload" || exit 0

# 2단계 — 정밀 재검사 + 질의 조립. 성공 시 2줄 출력(session_id, query).
_parsed="$(printf '%s' "$_payload" | HERMES_SIGNAL_RE="$_SIGNAL_RE" python3 -c '
import json, os, re, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if str(d.get("tool_name", "")).lower() != "bash":
    sys.exit(0)

resp = d.get("tool_response") or {}
if isinstance(resp, dict):
    text = str(resp.get("stdout", "")) + "\n" + str(resp.get("stderr", ""))
else:
    text = str(resp)

rx = re.compile(os.environ["HERMES_SIGNAL_RE"])
hit = next((ln for ln in text.splitlines() if rx.search(ln)), "")
if not hit:
    sys.exit(0)

cmd = str((d.get("tool_input") or {}).get("command", ""))
# 질의 순서 고정 — search_db 가 keywords[:5] 로 자르므로 신호 줄을 먼저 둔다.
# 명령어를 앞에 두면 정작 신호 단어(401, Unauthorized)가 잘려나간다.
print(d.get("session_id", ""))
print((hit.strip() + " " + cmd).replace("\n", " "))
' 2>/dev/null || true)"

[[ -n "$_parsed" ]] || exit 0
_sid="$(printf '%s\n' "$_parsed" | sed -n '1p')"
_query="$(printf '%s\n' "$_parsed" | sed -n '2p')"
[[ -n "$_query" ]] || exit 0

_out="$(python3 "$_search" \
  --db "$_db" --query "$_query" --session-id "$_sid" \
  --skills-dir "$PWD/.claude/skills" --global-skills-dir "$HOME/.hermes/mesh/skills" --max 1 \
  --source assist --no-fallback --once-per-session 2>>"$PWD/.hermes/hooks.log" || true)"

[[ -n "$_out" ]] && printf '%s\n' "$_out"
exit 0
