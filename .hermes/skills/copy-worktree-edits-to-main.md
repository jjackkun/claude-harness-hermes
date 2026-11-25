# copy-worktree-edits-to-main
<!-- hermes:auto-generated version:1 created:2026-11-25 -->

## 문제 상황
백그라운드 worktree에서 파일을 커밋한 후 메인 checkout에 복사하지 않아서 dev server나 Storybook에 변경사항이 반영되지 않는다.

## 규칙
- [ ] 백그라운드 worktree 커밋 후 `cp <worktree-path>/<파일> <main-checkout-path>/<파일>`로 메인 checkout에 동기화
- [ ] dev server/Storybook을 재로드해서 변경사항이 보이는지 확인
- [ ] worktree-finish로 세션을 마칠 때는 복사 불필요 (git merge가 자동 동기화)
- [ ] 메인 checkout 파일 시스템과 worktree 파일 시스템을 항상 같은 상태로 유지

## 근거
- 감지 횟수: 반복 패턴
- 패턴 키: worktree-not-synced
- 출처: CLAUDE.md 알려진 규칙 · worktree-finish 계획서
