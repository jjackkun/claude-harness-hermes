#!/usr/bin/env bash
# PreToolUse(Bash) hook — 세션 안에서 `claude -p` 를 직접 띄우는 것을 막는다 (계획 4 목표 7).
#
# 직접 띄우면 그 세션은 명부 id 없이 돈다(RV-06 위반). 러너(hermes-summon.py · hermes-loop-run.sh ·
# hermes-cron-run.sh)는 토큰을 발급해 .hermes/summons/<nonce>.pending 을 남기므로,
# 판정은 **명령줄 모양이 아니라 pending 파일의 존재**로 한다 — 러너 이름을 흉내 낸
# `bash -c 'exec hermes-loop-run.sh …; claude -p …'` 는 pending 이 없어 막힌다.
# 러너를 부르는 명령 자체(`python3 scripts/hermes-summon.py run …`)에는 `claude -p` 가 없어 통과한다.
#
# 출력: 차단 시 [summon-guard BLOCK] … + exit 2.

set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
HIT="$(printf '%s' "$INPUT" | python3 -c '
import json, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if d.get("tool_name") != "Bash":
    sys.exit(0)
cmd = d.get("tool_input", {}).get("command", "") or ""
LAUNCH = r"(^|[^A-Za-z0-9_./-])claude\s+(-p|--print)(?![A-Za-z0-9_-])"
# `bash -c "…"` / `sh -c \x27…\x27` 의 따옴표 안은 **명령**이다 — 먼저 꺼내 검사한다.
inner = re.findall(r"(?:^|\s)(?:bash|sh|zsh|dash)\s+-c\s+(?:\"((?:\\\\.|[^\"\\\\])*)\"|\x27([^\x27]*)\x27)", cmd)
scripts = [a or b for a, b in inner]
# 그 밖의 따옴표 안(커밋 메시지·echo 본문)은 명령이 아니다.
bare = re.sub(r"\"(?:\\\\.|[^\"\\\\])*\"|\x27[^\x27]*\x27", " ", cmd)
if any(re.search(LAUNCH, s) for s in scripts + [bare]):
    print("hit")
' 2>/dev/null)"
[[ "$HIT" == "hit" ]] || exit 0

# 살아 있는 pending 토큰이 하나라도 있으면 러너가 띄우는 중이다 → 통과
shopt -s nullglob
pending=("$PROJECT_DIR"/.hermes/summons/*.pending)
shopt -u nullglob
[[ ${#pending[@]} -gt 0 ]] && exit 0

cat >&2 <<MSG
[summon-guard BLOCK] 세션 안에서 claude -p 를 직접 띄울 수 없습니다 — 명부 id 없는 세션이 됩니다(RV-06).
  → 소환은 러너로: python3 scripts/hermes-summon.py run <에이전트> --task "…"
  → 루프는 러너로: scripts/hermes-loop-run.sh <프로젝트> "<목표>"
  근거: docs/hermes-universe/design/agent/identity.md §7
MSG
exit 2
