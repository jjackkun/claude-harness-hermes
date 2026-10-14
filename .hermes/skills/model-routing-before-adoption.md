# model-routing-before-adoption
<!-- hermes:auto-generated version:1 created:2026-10-09 -->

## 문제 상황
에이전트 15종의 effort 값이 근거 없고, 모델 선택(haiku/sonnet/opus) 기준이 불명확하며, 
기존 설정과 새 채택 간 모순이 반복된다. 실행 모드(foreground/background)별 정책이 없어 
"contradictory model guidance" 지적이 계속 발생한다.

## 규칙
- [ ] 새 에이전트/스킬 채택 전: 실행 모드(foreground/background/scheduled) + 예상 토큰 규모 확인
- [ ] effort 값 설정 시: 비용-성능 근거 명시 기록 (예: "Haiku 4.5: <1초, 배경 작업용 / Sonnet: 메인 개발용")
- [ ] foreground ↔ background 모델 분리 정책 문서화 (settings.json 주석 또는 CLAUDE.md §모델선택)
- [ ] 설정 변경(--model, --effort) 시: 기존 에이전트·스킬과 충돌 여부 확인
- [ ] scripts/ 헬퍼에 --model 인수 명시 필수 (agent-model-routing-blindspot 문서와 동기화)

## 근거
- 감지 횟수: 5회 이상
- 패턴 키: mode-idea-adoption-policy
- 관련 backlog: agent-model-routing-blindspot, agent-eval-regression, tool-output-budget
