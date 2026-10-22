# official-channels-adoption-checklist
<!-- hermes:auto-generated version:1 created:2026-10-20 -->

## 문제 상황
폴링 기반 기존 기술을 버리고 새 방식을 도입하기 전에, 공식 기능(Claude Channels)의 실제 동작과 안정성을 검증하지 않는 경우 발생. 공식 지원 기능을 간과하고 커스텀 솔루션으로 진행하려는 착각.

## 규칙
- [ ] 기존 폴링 방식을 대체하기 전에 Claude 공식 기능 먼저 조사 (Channels, Events API 등)
- [ ] 공식 기능이 있으면 마이그레이션 비용·안정성·token 사용량을 실측하고 문서화
- [ ] reply 도구 사용 여부와 응답 지연(예: 1.7초)을 시스템 지시에 명시
- [ ] 연구 미리보기(preview) 기능은 플래그·규약 변경 가능성을 가정하고 설계
- [ ] 첫 턴 토큰(예: 46.6K) vs 메시지당 토큰(100~250) 증분 비용 기록
- [ ] 에이전트 방(--agent 호출) 환경에서 실제 동작 확인 후 문서화

## 근거
- 감지 횟수: 1회 (2026-10-20)
- 패턴 키: channels-event-injection-idle
