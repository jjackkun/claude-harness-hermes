# tag-every-memory-with-agent-source
<!-- hermes:auto-generated version:1 created:2026-09-17 -->

## 문제 상황
기억(memory)이나 이벤트를 저장할 때 **에이전트 메타데이터(agent_id, agent_type)를 함께 기록하지 않으면**, 나중에 그 기억을 재사용할 때 원래 출처와 신뢰도를 추적 불가능. 특히 여러 에이전트가 관여한 작업에서 "누가 이 판단/기억을 만들었는가"가 불명확해져 기억의 재사용성 저하.

## 규칙
- [ ] 모든 메모리/이벤트 레코드에 `agent_id`, `agent_type` 칼럼 필수 포함
- [ ] 이벤트 저장 시 3층 구조 강제: (에이전트 주장값, 기계 검증값, 사람 수용값)
- [ ] 에이전트 출처 없는 기억은 DB 저장 전 거부 — 즉시 오류 반환
- [ ] 기억 검색/재사용 시 agent_id·agent_type 함께 반환 — 출처 표시 강제

## 근거
- 감지 횟수: 6회
- 패턴 키: event-kind-memory-added
