# defer-low-urgency-issues-to-backlog
<!-- hermes:auto-generated version:1 created:2026-10-06 -->

## 문제 상황
세션에서 결함·아이디어·미완료 설계를 여러 개 발견했을 때, 어느 것을 현재 처리하고 어느 것을 미뤄야 할지 판단하지 않고 방치하거나, backlog 항목으로 문서화할 때 재현 조건·영향도·의존성을 빠뜨려서 나중에 다시 분석해야 하는 상황이 반복됨.

## 규칙
- [ ] 발견한 각 이슈/아이디어마다: 현재 처리(active) vs 나중 처리(backlog) 판단하기
- [ ] 나중 처리로 판단한 항목은 `docs/exec-plans/backlog/<slug>.md`에 문서화
- [ ] backlog 항목마다: 제목·배경·재현 조건(있으면)·설계 가설·의존성 포함
- [ ] 우선순위는 미지정 상태로 두고, 향후 분류 시점 명시
- [ ] 현재 active 계획의 회고(§8)에 "backlog로 미룬 항목 N개"와 그 이유 한 줄씩 기록

## 근거
- 감지 횟수: 6회 (manifest-batch-write, hermes-chat, agent-model-routing-blindspot 등)
- 패턴 키: backlog-manager
