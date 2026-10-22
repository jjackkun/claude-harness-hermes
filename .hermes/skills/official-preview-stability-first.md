# official-preview-stability-first
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
공식 기능이 "research preview" 상태일 때, API 규약·플래그 변경 가능성을 명시하지 않고 도입하려는 경향. Channels는 공식이지만 preview 상태이므로, 기존 커스텀 솔루션(폴링) 대체 전에 안정성 조건을 먼저 정해야 함.

## 규칙
- [ ] Preview 상태 공식 기능 도입 전에 `docs/design-docs/` 에 변경 위험과 폴백 계획 명시하기
- [ ] 기존 기술(폴링) vs 공식 preview(이벤트 기반) 선택 기준을 코드 주석으로 남기기
- [ ] 규약 변경 모니터링 또는 주기적 안정성 확인 절차 설정하기

## 근거
- 감지 횟수: 0회
- 패턴 키: channels-research-preview-unstable
