---
name: hermes-roster
description: 헤르메스 명부 전원을 표로 보인다 — 이름 · @호출명 · 상태 · 분야/직급/조직 · 최근 불린 때. 사용자가 /hermes-roster 를 칠 때만 쓴다.
disable-model-invocation: true
---

# /hermes-roster — 명부 전원

아래 표는 이 명령을 부른 순간 `hermes-agent.py roster` 가 명부(`.hermes/agents.json`)와 작업 이력에서 뽑은 결과다.

!`python3 "${CLAUDE_PROJECT_DIR}/scripts/hermes-agent.py" --project "${CLAUDE_PROJECT_DIR}" roster 2>&1`

## 답하는 법

위 표를 **고치지 말고 그대로** 코드 블록으로 보여 준다. 숫자·이름을 다시 세거나 추측으로 채우지 않는다 — 표가 곧 사실이다.
표 아래에 한 줄만 덧붙인다: 부르는 법(`@<호출명 앞부분>` 을 쳐서 목록에서 고르기, 또는 한글 이름으로 "…한테 …시켜").
표 대신 오류가 나왔으면 그 줄을 그대로 보이고, `python3 scripts/hermes-agent.py list` 로 명부가 읽히는지 확인하자고 한 줄 제안한다.

이 방(세션)에 누가 불렸는지는 `/hermes-room` 이다.
