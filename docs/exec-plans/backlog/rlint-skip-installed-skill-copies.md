# R-lint 이 설치된 스킬 사본(.claude/skills/)까지 검사한다

> 작성일: 2026-10-20
> 목적: 소우주의 ESLint 가 공장이 깐 스킬 JS 를 검사해 전파 커밋을 막는 일을 없앤다.
> 근거: `docs/exec-plans/completed/2026-10-20-ui-prototype-skill.md` §7 (전파 중 발견)

## 개요

ui-prototype 전파(2026-10-20)에서 zeroday-frontend 의 커밋이 R-lint 에 막혔다.
`.claude/skills/ui-prototype/assets/template/scripts/*.js` 의 `NB`(브라우저 전역)와
`scripts/collect_scenes.js` 의 `require`·`process`(node)가 `no-undef` 11건.

- R-plan-missing·R-cx·R-dep 은 이미 `HARNESS_MANAGED_RE`(`.claude/{skills,rules,agents}/`)로 사본을 뺀다. R-lint 만 빠져 있다.
- 원본은 공장이 검사한다. 사본을 소우주 ESLint 설정으로 다시 검사할 이유가 없다 — 프로젝트마다 전역·환경 설정이 달라 공장이 다 맞출 수 없다.
- 다른 소우주 9곳은 ESLint 가 없거나 `.claude/` 를 이미 무시해 통과했다.

## 후보

1. pre-commit 의 `JS_TS` 집합에서 `HARNESS_MANAGED_RE` 를 뺀다 (R-fmt·R-plan 과 같은 판단).
2. 시험: 소우주 픽스처에 ESLint 위반 JS 를 `.claude/skills/x/` 에 두고 R-lint 가 건너뛰는지.
