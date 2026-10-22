# memory-events-as-schema
<!-- hermes:auto-generated version:1 created:2026-10-20 -->

## 문제 상황
기억 자동 적립 시 메모리 모델과 DB 스키마가 비동기가 되거나, 수동 철회 시 일관성이 깨짐.
cumora·hermes-summon 모두 이벤트 기반 자동 적립을 채택했으나, 스키마·이벤트 구조의
표준화 없이 구현하면 마이그레이션·감사가 어렵다.

## 규칙
- [ ] `memory-events` 테이블 구조를 우선 정의 (파일명, 이벤트 타입, 페이로드 스키마)
- [ ] `hermes-summon.py` 의 자동 호출 시점을 `memory-events.md` 안전장치와 정렬
- [ ] 수동 철회(철회만) 시에도 `memory-events` 에서만 제거, 별도 조작 금지
- [ ] 이벤트 타입·페이로드를 JSON Schema 로 검증 (커밋 전 테스트)

## 근거
- 감지 횟수: 0회 (이 세션에서는 신규 발견 없음, 09-20 구현 검증)
- 패턴 키: memory-system-db-ground-truth
