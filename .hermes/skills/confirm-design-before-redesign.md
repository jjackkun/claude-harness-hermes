# confirm-design-before-redesign
<!-- hermes:auto-generated version:1 created:2026-09-28 -->

## 문제 상황
설계 결정이 이미 `docs/design-docs/` 나 `docs/exec-plans/completed/` 에 기록되어 있는데, 그것을 모르고 같은 주제를 다시 설계하거나 대안을 제시함. 09-19 에 cumora 의 자동 소환·기억 적립 방식이 결정되고 구현까지 완료됐는데, 09-28 에 같은 내용을 백로그에 새로 항목(목표 5)으로 다시 올려 재논의가 됨.

## 규칙
- [ ] 비자명한 작업 시작 전 `docs/design-docs/` 와 `docs/exec-plans/active/` 를 먼저 읽는다
- [ ] 같은 주제의 기존 완료 결정이 있으면 `completed/` 를 확인하고 그 근거를 숙지한다
- [ ] 이미 구현된 방식이 있으면 그것을 바탕으로 이어받는다. 재설계·우회 금지
- [ ] 기존 결정에 이의가 있으면 새 설계가 아닌 `docs/audits/` 에 검토 기록을 남긴다

## 근거
- 감지 횟수: 1회 (cumora 자동 소환·기억 적립 재논의, 09-28)
- 패턴 키: cumora-memory-adoption
