# multi-location-issue-coordinated-fix
<!-- hermes:auto-generated version:1 created:2026-10-26 -->

## 문제 상황
같은 유형의 버그나 리뷰 누락이 여러 파일에 분산되어 있을 때, 일부만 발견되고 나머지는 나중에 개별적으로 고쳐진다. 이번에는 R-pipe 리뷰 누락이 hermes_search_fallback, hermes-evolve-skill, hermes-summon, hermes-manager, hermes_loop_prompt, hermes_mesh_gate 6개 파일에 동일하게 있었으나, 처음엔 3개만 식별되고 나머지는 순차 발견됨.

## 규칙
- [ ] 결함/리뷰 누락 1개 발견 시 바로 grep으로 동일 패턴의 전체 범위 확인
- [ ] 영향받는 모든 파일을 한 목록에 정리
- [ ] 목록을 먼저 보고한 뒤, 모든 파일을 함께 수정 (단계별 수정 금지)
- [ ] 수정 후 재검색으로 빠진 곳 없음 확인

## 근거
- 감지 횟수: 1회 (R-pipe 리뷰 누락, 처음 3개 → 최종 6개 파일)
- 패턴 키: hermes-skill-crystallization-batch
