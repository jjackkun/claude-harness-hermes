# event-driven-summon-adoption
<!-- hermes:auto-generated version:1 created:2026-09-29 -->

## 문제 상황
자동 소환 규칙을 정할 때 "모델 판정" vs "규칙 신호만" 중 혼동이 있었음.
기억 적립을 프롬프트 지시로 자동화하면서 ECC 도구 로그를 직접 읽으려는 시도 발생.

## 규칙
- [ ] 자동 소환은 **규칙 신호만** (이벤트: @멘션, 배정, 기한, idle 주기)
- [ ] 모델 판정 추가 금지 — fail-open 거부
- [ ] 기억 적립은 프롬프트 `memory note` 자동 호출로만 수행
- [ ] ECC 도구 로그를 직접 관찰하지 않는다 (R3·비용)

## 근거
- 감지 횟수: 1회 (09-19 채택 결정 → 09-27 구현)
- 패턴 키: cumora-adoption-decision
