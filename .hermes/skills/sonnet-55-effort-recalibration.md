# sonnet-55-effort-recalibration
<!-- hermes:auto-generated version:1 created:2026-10-01 -->

## 문제 상황
Sonnet 5.5가 기본 effort: medium이지만, ~/.claude/settings.json은 effort: high로 설정. 5에서 생성한 extended thinking 블록이 5.5로 전달되면 역호환성 문제 발생 가능. 모델 전환 시 사고량 재보정 미수행으로 인한 답변 품질 편차.

## 규칙
- [ ] Sonnet 5.5 사용 시 기본값 effort: medium으로 시작 (5의 high와 동등하지 않음)
- [ ] 두 모델을 같은 대화에서 번갈아 사용할 때 effort 수준을 명시
- [ ] 5의 thinking 블록을 5.5 컨텍스트에 포함할 때만 호환성 확인 필요
- [ ] 사고량 부족 증상(중단, 규칙 무시, 오류)이 나면 model 명시 후 재요청

## 근거
- 감지 횟수: 0회
- 패턴 키: sonnet-aliases-55-default-medium
