#!/usr/bin/env bash
# UserPromptSubmit hook — 매 턴 "사용자에게 보이는 답변은 한국어" 한 줄을 붙인다.
#
# 디스패처(claude-userpromptsubmit-dispatch.sh)가 이름 규칙으로 부른다 — 개별 등록하지 않는다.
# 출력은 매 턴 프롬프트 앞에 붙으므로 한 줄만. 끝에서 놓친 것은 Stop 훅(claude-stop-korean-guard.sh)이 막는다.
# 끄기: KOREAN_GUARD_DISABLED=1
# 계획: docs/exec-plans/completed/2026-10-16-korean-reply-guard-plan.md

[[ "${KOREAN_GUARD_DISABLED:-0}" == "1" ]] && exit 0
cat >/dev/null 2>&1 || true
echo "[한국어] 사용자에게 보이는 답변·보고는 한국어로 쓴다 — 코드·경로·명령·식별자만 원문. 긴 작업 끝 보고도 예외 없음."
exit 0
