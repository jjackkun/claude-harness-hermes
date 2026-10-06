# agent-roster-by-scope
<!-- hermes:auto-generated version:1 created:2026-10-06 -->

## 문제 상황
헤르메스 에이전트 명부를 조회할 때 전체 명부와 현재 세션의 에이전트를 구분하지 않으면, 같은 정보를 반복 생성하고 상태 관리가 분산된다. 세션별/프로젝트별 scope를 명확히 분리하지 않으면 패널·스킬·상태 파일이 중복되고 유지보수가 어려워진다.

## 규칙
- [ ] `/hermes-roster` — 전체 에이전트 명부 표시 (python3 scripts/hermes-agent.py --project . roster)
- [ ] `/hermes-room` — 현재 세션에서 호출된 에이전트만 표시 (.hermes/room.json)
- [ ] 상태 파일 구분: .hermes/hag/on.json (프로젝트별 켜짐), .hermes/room.json (세션별 방)
- [ ] 명부 표 재구성 금지 — CLI 도구 출력을 마크다운으로만 래핑
- [ ] /hermes-roster 실행 후 방 여는 방법(/hermes-room) 안내 추가

## 근거
- 감지 횟수: 5회
- 패턴 키: hermes-roster
