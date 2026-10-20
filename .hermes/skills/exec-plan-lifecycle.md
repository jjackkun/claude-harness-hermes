# exec-plan-lifecycle
<!-- hermes:auto-generated version:1 created:2026-10-16 -->

## 문제 상황
계획서(`docs/exec-plans/active/YYYY-MM-DD-<slug>.md`) 작성 후 git 미등록 상태로 남음. planner-lite 리뷰 반영, 회고 작성, completed/ 이동의 각 단계를 놓칠 수 있음. 계획서 파일 경로와 명명이 일관되지 않을 때가 있음.

## 규칙
- [ ] 비자명한 작업 시작 전 `docs/exec-plans/active/YYYY-MM-DD-<slug>.md` 작성 (템플릿: `docs/exec-plans/template.md`)
- [ ] 작성 후 즉시 `git add docs/exec-plans/active/...` 로 staged 상태 유지
- [ ] 복잡한 계획이면 작성 직후 planner-lite 에이전트로 리뷰 요청
- [ ] 리뷰 지적사항을 계획서에 반영하고 커밋 전까지 임시 상태 유지
- [ ] 작업 완료 후 회고(§8) 작성 및 문제점·배운 점 정리
- [ ] `mv docs/exec-plans/active/... docs/exec-plans/completed/...` 로 파일 이동
- [ ] 최종 커밋 메시지에 "docs(exec-plan): ..." 로 명기

## 근거
- 감지 횟수: 6회
- 패턴 키: 계획서
