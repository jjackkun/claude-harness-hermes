#!/usr/bin/env bash
# UserPromptSubmit hook — 가장 최근 사람 프롬프트에 SOUL 승인 의사가 있는지를 남긴다.
# (계획 2026-09-20-soul-self-approval-gap 목표 1. identity-guard 가 초안 표시 줄 삭제·approve-soul 을 판정할 때 읽는다.)
#
# 왜: "초안 표시 줄을 지우면 승인" 은 누가 지웠는지 묻지 않는다. 사람의 말이 있는 턴에만 승인이 되게 하려면
#     그 말이 있었는지를 PreToolUse 가 알 수 있어야 한다 — PreToolUse 는 프롬프트를 못 본다.
# 남기는 것: .hermes/.soul-approval-intent  {"ts": <epoch>, "approve": true|false}  — 매 프롬프트 덮어쓴다(최근 프롬프트 기준).
# 규칙: "승인"·approve 가 있고 부정형(승인하지 마·승인 금지·don't approve …)이 아니면 true. 애매하면 false(막는 쪽).
# stdout 은 세션 문맥으로 주입되므로 **아무것도 내지 않는다.** hermes 프로젝트(.hermes/agents.json)가 아니면 아무것도 안 한다. 항상 exit 0.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
PROJECT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
[[ -f "$PROJECT/.hermes/agents.json" ]] || exit 0
printf '%s' "$INPUT" | SAI_OUT="$PROJECT/.hermes/.soul-approval-intent" python3 -c '
import json, os, re, sys, time
try:
    prompt = str(json.load(sys.stdin).get("prompt") or "")
except Exception:
    prompt = ""
pos = re.search(r"승인|approve", prompt, re.I) is not None
neg = re.search(r"승인\S{0,4}\s*(하지|말고|말아|마라|마\b|금지|안\s*돼|없이)|(do\s*not|don.?t|never|without)\s+approv", prompt, re.I) is not None
out = os.environ["SAI_OUT"]
tmp = out + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump({"ts": int(time.time()), "approve": bool(pos and not neg)}, fh)
os.replace(tmp, out)
' >/dev/null 2>&1 || true
exit 0
