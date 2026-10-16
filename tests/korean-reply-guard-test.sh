#!/usr/bin/env bash
# 한국어 답변 가드 시험 — Stop 훅이 영어 위주 답변만 막고, 오탐·무한 반복이 없는지 잰다.
#
#   G1 영어 위주 작업 끝 보고 → 막음 (last_assistant_message 경로 · transcript 경로)
#   G2 한국어 본문 + 코드·경로·식별자 표·인용 오류 문구 / 영어 질문 / 영어 산출물 요청 / 짧은 답 → 통과
#   G3 같은 턴 두 번째 Stop · stop_hook_active · stdin 비어 옴(최근 transcript 대체) · 끄기 스위치
#   G4 디스패처 경유로 매 턴 한국어 한 줄이 붙는다
#
# transcript 는 실측 구조를 재현한다 — assistant 블록마다 한 줄, 사이에 다른 type 줄.
# 근거: docs/exec-plans/completed/2026-10-16-korean-reply-guard-plan.md §2-bis
#
# 실행: bash tests/korean-reply-guard-test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/assets/hooks/claude-stop-korean-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

# 훅 실행 디렉터리 — 설치된 모양(scripts/hooks/ 에 훅과 판정 모듈이 나란히)
PROJ="$TMP/proj"
mkdir -p "$PROJ/scripts/hooks"
cp "$HOOK" "$REPO_ROOT/assets/hooks/korean_reply_check.py" "$PROJ/scripts/hooks/" 2>/dev/null
export CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$TMP/cfg"
unset KOREAN_GUARD_DISABLED

# mk_transcript <파일> <사용자 글> <답변 글> [thinking-only]
mk_transcript() {
  python3 - "$@" <<'PY'
import json, sys
out, user, reply = sys.argv[1], sys.argv[2], sys.argv[3]
thinking_only = len(sys.argv) > 4
rows = [
    {"type": "user", "message": {"role": "user", "content": "이전 질문입니다"}},
    {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "이전 답변입니다. 잘 끝났습니다."}]}},
    {"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": user}]}},
    {"type": "attachment", "attachment": {"type": "hook", "content": "[Harness Reminders] English reminder text here"}},
    {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "thinking", "thinking": "Let me think about this in English for a long while before answering the user."}]}},
    {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "ls"}}]}},
    {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "README.md and some English tool output that is long enough"}]}},
    {"type": "system", "content": "system line"},
]
if not thinking_only:
    rows.append({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": reply}]}})
rows.append({"type": "cost-state", "value": 1})
with open(out, "w") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
}

# payload <transcript> [last_assistant_message] [stop_hook_active]
payload() {
  python3 -c 'import json,sys
d={"hook_event_name":"Stop","transcript_path":sys.argv[1],"stop_hook_active":sys.argv[3]=="1"}
if sys.argv[2]: d["last_assistant_message"]=sys.argv[2]
print(json.dumps(d,ensure_ascii=False))' "$1" "${2:-}" "${3:-0}"
}

# run <payload> → "block" | "pass"
run() {
  local out
  out="$(printf '%s' "$1" | bash "$PROJ/scripts/hooks/claude-stop-korean-guard.sh" 2>/dev/null)"
  if grep -q '"decision": *"block"' <<<"$out"; then echo block; else echo pass; fi
}
reset_state() { rm -f "$PROJ/.hermes/korean-guard.last"; }

ENG_REPORT='Experiment 7b passed. The Claude inside the VM finished subscription login and answered, using the in-app flow (decision D4). That completes the Phase 0 measurements; all 7 pass criteria were met on this PC.

| # | What was measured | Result |
|---|---|---|
| 1 | User effort | 1 admin approval (group add) + 1 re-login |
| 2 | VM boot | 1.06 s |
| 6 | Network | Goes only through the app; addresses outside the allowlist are blocked |

**Fixes needed when this becomes the product**
- **Login persistence:** this test kept the login in VM memory, so it disappears when the VM shuts down.
- **Allowlist:** at minimum `api.example.com`. If we use MCP, also review the proxy.

result: Phase 0 measured; all 7 criteria passed.

Next action: decide whether to compare the service-based approach.'

ENG_REPORT2='All done. I updated the plan, moved the finished items to the completed section, and committed the change. The tests pass and the gate reported no warnings. Decisions I made for you: kept the old layout because changing it would break two callers. Next: review the diff and tell me if the wording is right.'

KO_CODE='`src/auth.ts:42` 의 `verifyToken` 호출을 지우면 됩니다. 바꾼 뒤 시험을 돌렸고 모두 통과했습니다.

```python
def verify_token(token: str) -> bool:
    return token.startswith("Bearer ") and len(token) > 7  # English comment that is fairly long
```

| 파일 | 바뀐 것 |
|---|---|
| `src/auth/verify_token.ts` | `verifyToken` → `checkBearerToken` |
| `src/auth/session_store.ts` | `SessionStore.invalidateAll` 추가 |

경로: /home/user/project/src/auth/verify_token.ts, 문서: https://example.com/docs/authentication/bearer-tokens
다음 행동: `npm test` 를 돌려 주십시오.'

KO_QUOTE='원인은 의존성 버전 충돌입니다. 설치기가 남긴 오류는 다음과 같습니다.

> ERROR: Cannot install package-a==1.2.0 and package-b==3.4.1 because these package versions have conflicting dependencies.
> The conflict is caused by: The user requested urllib3 and botocore depends on an older version of it.

그래서 package-b 를 한 단계 낮추면 해결됩니다. 낮춘 뒤 다시 설치해 보니 오류 없이 끝났습니다.'

echo "== G1. 영어 위주 보고는 막는다 =="
T="$TMP/t1.jsonl"; mk_transcript "$T" "결과 정리해 줘" "$ENG_REPORT"
reset_state; assert "transcript 경로 — 실제 영어 보고 1" block "$(run "$(payload "$T")")"
reset_state; assert "last_assistant_message 경로 — 실제 영어 보고 1" block "$(run "$(payload "$TMP/none.jsonl" "$ENG_REPORT")")"
T="$TMP/t1b.jsonl"; mk_transcript "$T" "커밋까지 해 줘" "$ENG_REPORT2"
reset_state; assert "영어 보고 2" block "$(run "$(payload "$T")")"
OUT="$(reset_state; printf '%s' "$(payload "$T")" | bash "$PROJ/scripts/hooks/claude-stop-korean-guard.sh" 2>/dev/null)"
assert "reason 에 한국어로 다시 쓰라는 말" 1 "$(grep -c '한국어로 다시' <<<"$OUT")"
assert "출력이 유효한 JSON" ok "$(python3 -c 'import json,sys; json.loads(sys.stdin.read()); print("ok")' <<<"$OUT" 2>/dev/null)"

echo "== G2. 오탐 없음 =="
T="$TMP/t2.jsonl"; mk_transcript "$T" "어디를 고치면 돼?" "$KO_CODE"
reset_state; assert "한국어 + 코드 블록·경로·URL·식별자 표" pass "$(run "$(payload "$T")")"
T="$TMP/t3.jsonl"; mk_transcript "$T" "설치가 왜 실패해?" "$KO_QUOTE"
reset_state; assert "한국어 + 인용한 영어 오류 문구" pass "$(run "$(payload "$T")")"
T="$TMP/t4.jsonl"; mk_transcript "$T" "Can you summarize what changed in the release and why it matters?" "$ENG_REPORT2"
reset_state; assert "사용자가 영어로 물음" pass "$(run "$(payload "$T")")"
T="$TMP/t5.jsonl"; mk_transcript "$T" "README 를 영어로 써 줘" "$ENG_REPORT2"
reset_state; assert "사용자가 영어 산출물 요청" pass "$(run "$(payload "$T")")"
T="$TMP/t5b.jsonl"; mk_transcript "$T" "이 문단 in English 로 바꿔" "$ENG_REPORT2"
reset_state; assert "사용자가 in English 요청" pass "$(run "$(payload "$T")")"
T="$TMP/t6.jsonl"; mk_transcript "$T" "끝났어?" "Done."
reset_state; assert "짧은 영어 한 줄" pass "$(run "$(payload "$T")")"
T="$TMP/t7.jsonl"; mk_transcript "$T" "정리해 줘" "" thinking-only
reset_state; assert "마지막 assistant 가 thinking 뿐" pass "$(run "$(payload "$T")")"

echo "== G3. 같은 턴은 두 번 막지 않는다 · stdin 이 비어도 동작 =="
T="$TMP/t8.jsonl"; mk_transcript "$T" "결과 정리해 줘" "$ENG_REPORT"
reset_state
assert "첫 Stop 은 막는다" block "$(run "$(payload "$T")")"
assert "같은 답변 두 번째 Stop 은 통과" pass "$(run "$(payload "$T")")"
T2="$TMP/t8b.jsonl"; mk_transcript "$T2" "다른 세션 질문" "$ENG_REPORT2"
assert "다른 세션(transcript)의 턴은 따로 막는다" block "$(run "$(payload "$T2")")"
assert "세션이 번갈아도 첫 세션 같은 턴은 다시 막지 않는다" pass "$(run "$(payload "$T")")"
reset_state
assert "stop_hook_active=true 면 통과" pass "$(run "$(payload "$T" "" 1)")"
# stdin 비어 옴 → ~/.claude/projects/<프로젝트 경로 이름>/ 의 최근 transcript 로 대체
ENC="$(python3 -c 'import re,sys; print(re.sub(r"[^A-Za-z0-9]","-",sys.argv[1]))' "$PROJ")"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$ENC"
mk_transcript "$CLAUDE_CONFIG_DIR/projects/$ENC/old.jsonl" "정리해 줘" "$KO_QUOTE"; touch -d '1 hour ago' "$CLAUDE_CONFIG_DIR/projects/$ENC/old.jsonl"
mk_transcript "$CLAUDE_CONFIG_DIR/projects/$ENC/new.jsonl" "정리해 줘" "$ENG_REPORT"
reset_state; assert "stdin 비면 최근 transcript 로 같은 판정(막음)" block "$(run "")"
assert "stdin 비고 같은 답변 두 번째 → 통과" pass "$(run "")"
reset_state; assert "stdin 이 JSON 이 아니어도 대체 경로" block "$(run "not-json")"
reset_state; assert "끄기 스위치 KOREAN_GUARD_DISABLED=1" pass "$(KOREAN_GUARD_DISABLED=1 run "$(payload "$T")")"
T="$TMP/t9.jsonl"; printf '{"type":"session_meta","payload":{}}\n{"type":"response_item","payload":{"role":"assistant"}}\n' > "$T"
reset_state; assert "Claude 형식이 아닌 transcript(Codex) 는 통과" pass "$(run "$(payload "$T")")"
reset_state; assert "transcript 경로가 없는 파일이면 통과" pass "$(run "$(payload "$TMP/missing.jsonl")")"

echo "== G4. 디스패처 경유 매 턴 한국어 한 줄 =="
D="$TMP/dispatch"; mkdir -p "$D"
cp "$REPO_ROOT/assets/hooks/claude-userpromptsubmit-dispatch.sh" "$REPO_ROOT/assets/hooks/claude-userpromptsubmit-korean.sh" "$D/" 2>/dev/null
OUT="$(printf '%s' '{"prompt":"정리해 줘"}' | bash "$D/claude-userpromptsubmit-dispatch.sh" 2>/dev/null)"
assert "한국어 답변 한 줄이 붙는다" 1 "$(grep -c '\[한국어\]' <<<"$OUT")"
assert "한 줄뿐이다(매 턴 비용 최소)" 1 "$(grep -c . <<<"$OUT")"
OUT="$(printf '%s' '{"prompt":"x"}' | KOREAN_GUARD_DISABLED=1 bash "$D/claude-userpromptsubmit-dispatch.sh" 2>/dev/null)"
assert "끄기 스위치면 붙지 않는다" 0 "$(grep -c '\[한국어\]' <<<"$OUT")"

echo
echo "결과: 통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]]
