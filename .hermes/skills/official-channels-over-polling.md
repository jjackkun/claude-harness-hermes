# official-channels-over-polling
<!-- hermes:auto-generated version:1 created:2026-10-20 -->

## 문제 상황
폴링 기반 솔루션이 필요할 때 공식 이벤트 기반 기능(Claude Channels, webhook 등)을 먼저 검증하지 않고 기존 폴링 방식을 채택하거나, 검증 없이 전환하려 함.

## 규칙
- [ ] 폴링 아키텍처 필요 시 공식 이벤트 기반 대안(Channels 등) 먼저 조사
- [ ] 공식 기능 실측: 응답 시간, 토큰 소비, 안정성 측정
- [ ] 기존 방식과의 성능 비교표 작성 (정성·정량 모두)
- [ ] 기능 상태 확인 (production·preview·research) 및 규약 변경 가능성 기록
- [ ] 선택 근거를 아키텍처 문서에 명시 후 구현 시작

## 근거
- 감지 횟수: 1회
- 패턴 키: channels-event-driven-no-polling
