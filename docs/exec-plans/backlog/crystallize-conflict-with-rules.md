# crystallize-conflict-with-rules — 결정화가 이미 있는 스킬·규칙과 어긋나는 스킬을 만든다

> 작성일: 2026-11-20 · 출처: `docs/exec-plans/completed/2026-11-20-worktree-finish-plan.md` §7

## 무슨 일이 있었나

- jj-agent-room 에서 `worktree-not-synced`(107회)를 결정화했더니 스킬 2개가 생겼다(`sync-worktree-to-main-checkout.md` · `copy-worktree-edits-to-main.md`).
- 둘 다 "worktree 파일을 `cp -r` 로 메인 체크아웃에 복사" 하라고 적었다. 같은 날 만든 `worktree-finish`(rebase → ff)와 어긋나고, 메인의 다른 세션 변경을 덮을 수 있다.
- 커밋되지 않았지만 헤르메스는 `.hermes/skills` 를 세션에 주입하므로 그 컴퓨터에서는 이미 살아 있었다. 사용자 판정으로 지웠다(색인 줄 2개 백업 후 삭제).
- 같은 키에서 스킬이 2개 나온 것도 이상하다(키 하나 → 스킬 하나여야 한다).

## 해야 할 것(후보)

- 결정화 프롬프트에 그 프로젝트의 규칙(`~/.claude/rules`, `.claude/rules`)과 관련 스킬 이름·요약을 넣고, 어긋나면 만들지 않게 한다.
- 같은 키에서 이미 스킬이 나왔으면 두 번째를 만들지 않는다(`hooks.log` 28907·28909 — 같은 키로 DONE 두 번).
- 검증: 규칙과 어긋나는 증거를 준 가짜 패턴으로 결정화를 돌려 "만들지 않음" 이 나오는지(모델 호출 — 사용자 승인 뒤).
