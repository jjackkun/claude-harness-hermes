# exec-plan-completion-process
<!-- hermes:auto-generated version:1 created:2026-11-25 -->

## 문제 상황
작업 완료 후 계획서를 `docs/exec-plans/completed/` 로 옮기는 절차가 반복됨. 매번 회고(§8) 작성 → 폴더 이동 → 커밋의 순서가 동일함.

## 규칙
- [ ] 계획서 작업 완료 후 회고(§8) 섹션 작성
- [ ] `docs/exec-plans/active/YYYY-MM-DD-<slug>.md` 를 `docs/exec-plans/completed/` 로 이동
- [ ] 파일명 형식 유지: `YYYY-MM-DD-<slug>.md`
- [ ] `git add` 후 커밋 (메시지: `docs(plan): <slug> completed`)
- [ ] 완료된 모든 계획서는 `completed/` 에 보관 (기록 보존)

## 근거
- 감지 횟수: 9회
- 패턴 키: completed
