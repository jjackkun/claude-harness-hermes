---
name: hermes-room
description: 지금 이 방(세션)에서 불린 에이전트를 보인다 — 명부 에이전트는 이름·횟수·마지막 시각, 명부 밖은 종류별 건수, 내부 보조 호출은 건수만. 사용자가 /hermes-room 을 칠 때만 쓴다.
disable-model-invocation: true
---

# /hermes-room — 이 방의 에이전트

"방" 은 이 세션이고, 에이전트가 "방에 있다" 는 **이 방에서 불린 적 있음**이다(소환·`@agent-<slug>` 모두).
아래는 이 명령을 부른 순간 `hermes-agent.py room` 이 작업 이력에서 이 세션만 골라 뽑은 결과다.

!`python3 "${CLAUDE_PROJECT_DIR}/scripts/hermes-agent.py" --project "${CLAUDE_PROJECT_DIR}" room --session "${CLAUDE_SESSION_ID}" 2>&1`

## 답하는 법

위 결과를 **고치지 말고 그대로** 코드 블록으로 보여 준다. 이 대화에서 기억나는 호출로 목록을 보태거나 빼지 않는다 —
이력에 남은 것만이 사실이고, 기억과 다르면 그 차이 자체가 알릴 거리다.
"내부 보조 호출" 은 Claude Code 가 안에서 띄운 것이라 이름이 없다. 사용자가 부른 것이 아님을 한 줄로 덧붙인다.
명부 에이전트가 없으면 부르는 법 한 줄(`@<호출명 앞부분>`, 전체 명부는 `/hermes-roster`)로 끝낸다.
