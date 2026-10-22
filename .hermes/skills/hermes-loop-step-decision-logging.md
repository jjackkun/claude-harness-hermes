# hermes-loop-step-decision-logging
<!-- hermes:auto-generated version:2 created:2026-10-16 -->

## 문제 상황
Hermes 루프 반복 중 Step 0에서 계획서 재확인을 생략하거나, Step 1~5에서 `decisions.record()` 호출을 누락하는 경우가 반복됨. 보고서 생성 후 `loop_steps`과 `loop_decisions` 행 수 불일치로 누락을 발견하고 있음.

## 규칙
- [ ] Step 0: `docs/exec-plans/active/` 계획서를 읽고 목표·§2·§4를 재확인하고 진행
- [ ] Step 1~5: 각 반복 완료 후 `decisions.record([...])` 호출 (없으면 `decisions.record([])`)
- [ ] 조건문 분기·예외 처리 포함 모든 코드 경로에서 결정 기록
- [ ] "결정 — 근거 — 손해" 형식으로 기록
- [ ] 루프 종료 후 보고서의 `loop_steps` 행과 `loop_decisions` 행이 1:1 대응 확인

## 근거
- 감지 횟수: 4회 (Step 0 미확인, Step 1~5 decisions 호출 누락, 분기 경로 누락, 행 수 불일치)
- 패턴 키: step, decisions, exec-plans, 계획서 재확인
