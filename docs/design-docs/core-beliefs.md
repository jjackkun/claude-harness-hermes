# Core Beliefs — 하네스 룰 앵커

> 본 문서는 hook 메시지가 가리키는 anchor 목록이다. 메시지는 짧게, 근거는 여기에.
> Opus 4.7 (2026-04-16+) 의 글자대로 해석 특성에 맞춰 hook 출력은 단일 권장 + 링크 형태.

## R5 — 우회 금지 {#r5}

pre-commit / hook 이 막으면 hook 또는 코드를 고친다. `--no-verify`, `eslint-disable` 단독 우회 금지.

## R-agent — 도메인 에이전트 우선 {#r-agent}

frontend/DB/TS 작업은 `fullstack-developer`, `database-reviewer`, `typescript-reviewer` 사용.
`general-purpose` 는 범용 조사·문서·검색 전용.

## R-size — 1 파일 = 1 책임 (500은 안전망) {#r-size}

**원칙**: 한 파일은 한 책임만 진다. 파일명이 그 책임을 드러내야 한다.
배럴 (`index.ts` / `__init__.py`) 로 import 인체공학을 유지.

**안전망**: soft 400 (PostToolUse 경고), hard 500 (pre-commit 차단).
이 한도가 트리거되면 *원칙이 상류에서 실패했다는 뜻* — 501줄에서 기계적 분리가
아니라 "왜 여기까지 왔지?" 부터 묻는다. 500 초과 파일은 거의 항상 책임 2개 이상이
섞여 있고, 제대로 분리하면 500 한도는 자연히 지켜진다.

정말 한 책임인데 500 을 넘으면 (큰 스키마 직렬화, 완전 열거 상태 머신 등) waiver 근거를
파일 상단 주석 + `docs/audits/` 에 기록 후 `.harnessrc` 의 `MAX_LINES_HARD` 상향.

## R-fmt — 포맷팅 {#r-fmt}

prettier 위반은 `pnpm exec prettier --write` 로 자동 수정. `.prettierrc` 단독 변경 금지 (프로젝트 합의 필요).

## R-lint — ESLint {#r-lint}

ai-dev-setting 의 lint 룰 메시지에는 한국어 수정 지침이 박혀있음. 메시지 따라 수정. `eslint-disable` 단독 우회 금지.

## R-test — pytest {#r-test}

테스트 실패 = 회귀(코드를 고침) 또는 룰 강제(룰을 따름). 테스트 단독 비활성화 금지 (`docs/audits/` 근거 후).

## R-review — 리뷰 빚 {#r-review}

코드 수정 발생 시 `.claude/.review-dirty` 생성. 자연 단위(엔드포인트/컴포넌트/마이그레이션 한 단락) 종료 시
code-reviewer dispatch 후 `rm .claude/.review-dirty`. 안 지우면 commit 단계에서 차단.

**도메인 리뷰어 병렬 dispatch (조건부)**: 변경에 DB 스키마/마이그레이션이 포함되면 `code-reviewer` 와 `database-reviewer` 를
*병렬로 함께* dispatch 한다. code-reviewer 는 Task 도구가 없어 스스로 위임할 수 없으므로 오케스트레이터가 책임.
DB 변경이 없는 단위는 단독 dispatch 유지 — 무차별 병렬 호출 금지.
강제: `assets/hooks/claude-pretooluse-agent-guard.sh` 가 code-reviewer dispatch 의 prompt/description 에서
DB 키워드 감지 시 additionalContext 로 안내 주입.

## R-plan — 완료된 계획 이동 강제 {#r-plan}

`docs/exec-plans/active/*.md` 의 모든 체크박스가 `[x]` 이면 pre-commit 차단.
회고(§8) 작성 후 `git mv active/<plan>.md completed/` 로 마감. 상세: `docs/exec-plans-system.md`.

**backlog/**: 아직 일정이 없는 작업 후보. 날짜 없이 `<slug>.md` 로 보관. active/ 로 승격 시 날짜 prefix 추가.

## R-plan-missing — 코드 수정 시 계획 존재 {#r-plan-missing}

코드 파일 수정이 있는데 `active/` 에 계획이 없으면 경고(차단 아님).
단순 버그 수정은 무시. 다중 파일·설계 결정이면 `docs/exec-plans/active/YYYY-MM-DD-<slug>.md` 작성. 템플릿: `docs/exec-plans/template.md`.
