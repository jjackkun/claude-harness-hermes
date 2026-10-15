# compare-bot-integration-backends
<!-- hermes:auto-generated version:1 created:2026-10-15 -->

## 문제 상황
Bot 프로젝트의 응답 지연을 개선하기 위해 여러 연동 방식(cron 폴링, Claude SDK, Claude Channels, 공식 플러그인)을 순차적으로 조사하지만, 각 방식마다 동일한 성능 테스트 기준을 적용하지 않아 비교 신뢰도가 낮아짐.

## 규칙
- [ ] Bot 성능 개선 전에 현재 기준(cron 폴링 + 응답시간)을 측정 기록
- [ ] 새 연동 방식(SDK, Channels, 공식 플러그인)을 시도할 때마다 동일한 테스트 케이스로 응답 시간 재측정
- [ ] 구현 완료 후 즉시 벤치마크 결과(방식별 응답시간·메모리·폴링 간격)를 표로 정리
- [ ] 각 방식의 트레이드오프(속도 vs 비용 vs 복잡도)를 명시한 뒤 최종 선택

## 근거
- 감지 횟수: 3회 (Channels 조사 → 공식 플러그인 비교 → 재측정 사이클)
- 패턴 키: [REDACTED:NAME]_bot
