# Agent Session Rooms

## 문제 상황

명부 에이전트(`@agent-backlog-manager` 등)와 이어서 일할 때, `@` 호출마다 새로 부르면 대화 맥락이 끊깁니다. 사용자의 원문도 나(Claude)를 거쳐 에이전트가 받으므로, 직접 대화가 아닙니다. 공식 문서: "The @-mention controls which subagent Claude invokes, not what prompt it receives."

## 규칙

- [ ] 명부 에이전트와 **이어서 일할** 때는 `claude --agent <slug> --name <방이름>` 으로 "방"을 열기
- [ ] 나중에 돌아오려면 `claude --resume <방이름>` 사용 (매번 `@` 호출하지 않기)
- [ ] 이 방에 불린 에이전트는 `/hermes-room` 명령으로 확인
- [ ] 상태줄에는 "지금 일하는 중" 과 "이 방에서 불린" 명부 에이전트만 표시 (도구·보조 건수는 `/hermes-room` 상세 보기로)

## 근거

- 감지 횟수: 3회 이상
- 패턴 키: 에이전트
- 기록: `hermes-chat` 백로그 논의 → 불편함 4가지 지적 → 공식 문서 확인 → 개선안 제시
