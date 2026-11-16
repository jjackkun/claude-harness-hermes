# skill-iteration-record-sync
<!-- hermes:auto-generated version:1 created:2026-11-16 -->

## 문제 상황
스킬을 skill-creator로 정식 빌드하며 반복 평가할 때, 반복 메타데이터(record_iteration)와 결정 기록(decisions.record) 간에 기록 불일치 발생. 한 곳만 업데이트되거나 타이밍이 맞지 않아 나중에 기록을 재구성할 수 없음.

## 규칙
- [ ] 스킬 평가 마다 record_iteration 에 반복 번호·결과·발동율을 기록
- [ ] 같은 순간에 decisions.record 에 개선사항을 함께 기록
- [ ] 반복마다 두 기록이 정확히 쌍을 이루는지 확인
- [ ] 다음 반복 시작 전에 동기화 상태를 검증

## 근거
- 감지 횟수: 1회
- 패턴 키: iteration-n
- watch 스킬 skill-creator 평가 과정에서 기록 관리 공백 발생
