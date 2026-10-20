# hermes-loop-step-decision-logging
<!-- hermes:auto-generated version:1 created:2026-10-16 -->

## 문제 상황
Hermes 루프 실행 시 각 스텝(step 0~9)마다 `decisions.record()` 호출을 누락하거나, 파싱 실패 분기에서 결정 기록을 안 하는 경우가 반복됨. 보고서 생성 후 `loop_steps` 행과 `loop_decisions` 행을 대조했을 때 기록 누락을 사후에 발견하고 있음.

## 규칙
- [ ] 루프의 모든 스텝(step 0~9)에서 결정 후 `decisions.record([...])` 호출 (없으면 `decisions.record([])`)
- [ ] 파싱 실패·조건문 분기 포함 **모든 코드 경로**에서 결정 기록
- [ ] 루프 반복 종료 후 보고서의 `loop_steps` 행과 `loop_decisions` 행이 1:1 대응되는지 확인 (행 수 일치)
- [ ] 각 스텝 완료 시점에 "단계 — 근거 — 손해" 형식으로 기록

## 근거
- 감지 횟수: 3회 (Step 0~9 완료, Step 1 판정 추적, decisions 호출 누락)
- 패턴 키: step
