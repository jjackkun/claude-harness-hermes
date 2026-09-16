#!/usr/bin/env bash
# PreToolUse(Bash) hook — AI 세션 안에서 열쇠를 만들거나 입력하는 명령을 막는다 (T-11).
#
# 열쇠는 사람이 AI 세션 **밖**에서만 다룬다. 세션 안에서 만들면 비밀열쇠가 대화 원문에
# 찍히고, 그 원문은 저장·이식된다. 막는 것은 세 가지뿐이다:
#   1. age-keygen              — 열쇠 생성
#   2. AGE-SECRET-KEY-         — 비밀열쇠 문자열을 명령줄에 직접 넣는 것
#   3. hermes-keys.sh init|emergency|rotate-master — 열쇠를 만드는 하위 명령
# hermes-keys.sh doctor · add-computer · revoke 는 열쇠를 만들지 않으므로 통과한다.
# 설계: docs/hermes-universe/design/protection/encryption-keys.md
# 계획: docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 5
#
# 출력: 차단 시 stderr 에 [key-guard BLOCK] … 을 내고 exit 2 (Claude Code 가 도구 호출을 거부한다).

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

# 판정은 파이썬 한 번으로 — 따옴표 안 문자열(커밋 메시지·echo 본문)은 명령이 아니므로
# 명령 이름 검사에서 뺀다. 2026-09-16 실측: 이 가드가 "age-keygen" 을 언급한 커밋 메시지를
# 막았다. 비밀열쇠는 따옴표 안에 있어도 막되, 문서에 적는 접두어 'AGE-SECRET-KEY-' 만으로는
# 막지 않고 실제 열쇠 길이(Bech32 50자 이상)일 때만 막는다.
reason="$(printf '%s' "$INPUT" | python3 -c '
import json, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if d.get("tool_name") != "Bash":
    sys.exit(0)
cmd = d.get("tool_input", {}).get("command", "") or ""
if not cmd:
    sys.exit(0)
# 실제 비밀열쇠 — 따옴표 안팎을 가리지 않는다
if re.search(r"AGE-SECRET-KEY-1[AC-HJ-NP-Z02-9]{50,}", cmd):
    print("실제 비밀열쇠(AGE-SECRET-KEY-1…)가 명령줄에 있음"); sys.exit(0)
# 명령 이름 검사 — 따옴표 안은 지운다
bare = re.sub(r"\"(?:\\\\.|[^\"\\\\])*\"|\x27[^\x27]*\x27", " ", cmd)
if re.search(r"(^|[^A-Za-z0-9_./-])age-keygen(?![A-Za-z0-9_-])", bare) or re.search(r"(^|/)age-keygen(?![A-Za-z0-9_-])", bare):
    print("age-keygen 으로 열쇠를 만드는 명령"); sys.exit(0)
if re.search(r"hermes-keys\.sh\s+(init|emergency|rotate-master)(?![A-Za-z0-9-])", bare):
    print("hermes-keys.sh 의 열쇠 생성 명령"); sys.exit(0)
if re.search(r"hermes-sync\.py\b[^;&|]*\btombstone(?![A-Za-z0-9-])", bare):
    print("hermes-sync.py tombstone(기억 물리 삭제, G-5)"); sys.exit(0)
' 2>/dev/null)"
[[ -n "$reason" ]] || exit 0

cat >&2 <<EOF
[key-guard BLOCK] $reason — 열쇠는 AI 세션 밖에서 사람이 다룹니다 (T-11).
  → 터미널을 따로 열어 직접 실행하십시오: scripts/hermes-keys.sh <명령>
  → 세션 안에서 허용되는 것: hermes-keys.sh doctor · add-computer · revoke
  근거: docs/hermes-universe/design/protection/encryption-keys.md
EOF
exit 2
