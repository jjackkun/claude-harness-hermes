# base-hermes-agent-invocation
<!-- hermes:auto-generated version:1 created:2026-09-29 -->

## 문제 상황
헤르메스 방(named session)에서 에이전트를 소환할 때 호출 형식이 명확하지 않았으며, hermes-agent 스킬(자연어 입력)과 --agent 플래그(직접 호출)의 용도 차이를 구분 필요.

## 규칙
- [ ] 헤르메스 방을 열고 에이전트를 소환할 때는 항상 `claude --agent <호출명> --name <방이름>` 형식 사용
- [ ] hermes-agent 스킬은 자연어("에이전트 뽑자", "한 명 입사")로 명부 조회 후 자동 배정할 때 사용
- [ ] --agent 플래그는 이미 호출명을 알 때 직접 방을 열 때 사용
- [ ] 에이전트 명부와 방 명령(/hermes-roster, /hermes-room) 아래에 호출 방법 예시 문서화

## 근거
- 감지 횟수: 3회
- 패턴 키: hermes-chat-base-command
