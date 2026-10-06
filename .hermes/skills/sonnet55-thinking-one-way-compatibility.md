# Sonnet55 Thinking One-Way Compatibility

<!-- hermes:auto-generated version:1 created:2026-10-01 -->

## 문제 상황
Sonnet 5.5는 Sonnet 5의 extended thinking 블록을 읽을 수 있지만, 역으로 5.5에서 5로 다운그레이드하면 thinking 콘텐츠가 손실됨. 
설정 변경이나 모델 전환 시 이 비호환성으로 인해 예상치 못한 동작 저하와 컨텍스트 손실 발생.

## 규칙
- [ ] 5.5에서 작업 중 장시간 사고(thinking)가 누적된 상태에서 모델 다운그레이드 피하기
- [ ] ~/.claude/settings.json의 `model: sonnet` 별칭이 5.5를 가리키는지 먼저 확인
- [ ] Thinking 활성화 상태에서 effort 설정 변경(high→medium) 후 호환성 재검사
- [ ] 이전 모델로 전환 필요 시 현재 세션의 thinking 내용 먼저 문서화

## 근거
- 감지 횟수: 1회
- 패턴 키: sonnet-55-reads-thinking-backwards-not-supported
- 공식 출처: claude.dev 'Building with Claude Sonnet 5.5'
