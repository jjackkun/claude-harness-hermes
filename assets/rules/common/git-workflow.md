# Git Workflow

## Commit Message Format
```
<type>: <description>

<optional body>
```

Types: feat, fix, refactor, docs, test, chore, perf, ci

Note: Attribution disabled globally via ~/.claude/settings.json.

## Branch Strategy

- **소규모 작업:** 현재 브랜치에서 직접 작업한다.
- **대규모 작업** (여러 파일·모듈에 걸친 구조 변경, 장기 피처): `git checkout -b <branch>`로 새 브랜치를 만들어 작업한다.
- **직접 worktree 를 만들지 않는다 (포그라운드 세션):** `git worktree add` 등 worktree 생성을 사용하지 않는다.
  - **예외 — 백그라운드 세션:** 파일 충돌 방지를 위해 `EnterWorktree`를 안전장치로 사용한다.

## worktree 세션 마무리

데스크톱 앱은 세션마다 worktree 를 **만들어 준다**. 위의 "만들지 않는다" 와는 다른 경우다. 앱이 만든 worktree 에서 일을 끝내면:

- **`worktree-finish` 스킬로 끝낸다** — 커밋 → 로컬 main 위로 rebase → 메인 체크아웃에서 `merge --ff-only` → worktree·브랜치 지우기. 스킬이 멈추면 우회하지 말고 이유를 사용자에게 보인다.
- **PR 은 열지 않는다** — 혼자 쓰는 저장소가 기본이다. PR 로 운영하는 저장소는 그 저장소의 규칙을 따른다.
- **푸시는 지시가 있을 때만** 한다.
- **남의 worktree 는 건드리지 않는다** — 다른 세션의 커밋 안 된 변경을 옮기거나 지우지 않는다.

이유: worktree 에 남긴 커밋은 main 에서 보이지 않는다. 다른 세션이 같은 일을 다시 하고(2026-11-19 jj-agent-room 결재 중복), worktree 가 쌓인다. 끝냈는데 합치지 않으면 Stop 훅이 한 번 막고, 세션 시작에 안 합친 worktree 를 알린다.
근거: 공장 `docs/exec-plans/completed/2026-11-20-worktree-finish-plan.md`

## Pull Request Workflow

When creating PRs:
1. Analyze full commit history (not just latest commit)
2. Use `git diff [base-branch]...HEAD` to see all changes
3. Draft comprehensive PR summary
4. Include test plan with TODOs
5. Push with `-u` flag if new branch

> For the full development process (planning, TDD, code review) before git operations,
> see [development-workflow.md](./development-workflow.md).
