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
표 끝에는 **방 열기** 구역이 이미 붙어 있다(호출명 있는 재직자마다 `claude --agent <호출명> --name <방이름>`) — 그것도 고치지 말고 그대로 둔다.
덧붙일 말은 한 줄이다: 한 번 시키는 일은 `@<호출명 앞부분>` 으로, **이어서 일할 때는 방을 연다**(매번 `@` 로 부르면 맥락이 끊긴다).
표 대신 오류가 나왔으면 그 줄을 그대로 보이고, `python3 scripts/hermes-agent.py list` 로 명부가 읽히는지 확인하자고 한 줄 제안한다.

이 방(세션)에 누가 불렸는지는 `/hermes-room` 이다.
