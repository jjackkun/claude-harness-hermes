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
- **Git worktree 금지 (포그라운드 세션):** `git worktree add` 등 worktree 생성을 사용하지 않는다.
  - **예외 — 백그라운드 세션:** 파일 충돌 방지를 위해 `EnterWorktree`를 안전장치로 사용한다.

## Pull Request Workflow

When creating PRs:
1. Analyze full commit history (not just latest commit)
2. Use `git diff [base-branch]...HEAD` to see all changes
3. Draft comprehensive PR summary
4. Include test plan with TODOs
5. Push with `-u` flag if new branch

> For the full development process (planning, TDD, code review) before git operations,
> see [development-workflow.md](./development-workflow.md).
