# background-session-edits-need-sync
<!-- hermes:auto-generated version:1 created:2026-11-25 -->

## 문제 상황
백그라운드 세션의 worktree에서 파일을 편집한 후, dev server나 Storybook에 변경이 반영되지 않는다.
메인 checkout이 여전히 이전 버전의 파일을 갖고 있기 때문이다.

## 규칙
- [ ] worktree에서 Edit/Write 완료 후 커밋
- [ ] 커밋 직후 `cp -r <worktree-path>/* <main-checkout-path>/` 실행
- [ ] dev server 띄우거나 Storybook/테스트 실행 전에 복사 완료 확인
- [ ] 여러 파일 변경 시 한 번의 `cp` 명령으로 모두 반영

## 근거
- 패턴 키: worktree-not-synced
- 발견: worktree-finish 계획 구현 중
