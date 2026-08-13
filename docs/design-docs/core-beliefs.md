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

## R-plan-stale — 계획서가 코드를 따라오는가 {#r-plan-stale}

`active/` 에 계획서가 있는데 작업 코드만 스테이징되면 경고(차단 아님).

R-plan 은 *스테이징된* 계획서만 검사한다 — "갱신하지 않는 행동" 을 잡으려는 장치가
"갱신했음" 을 전제하는 순환 의존이었다. 이 룰이 그 축을 뒤집는다.

**차단하지 않는 이유**: 계획서가 하나뿐일 때 차단하면 워킹트리 공유 시 상호 차단이
발생한다(2026-07-23 사고, `tests/harness-hooks-smoke.sh` 13(a) 가 회귀를 고정한다).
일부라도 스테이징돼 있으면 통과시킨다 — 어느 계획에 속한 커밋인지 훅은 알 수 없다.
하네스 생성물(`scripts/hooks/`)은 대상에서 제외한다: 재설치가 덮어쓰므로 포함하면
하네스 갱신 커밋이 자기 게이트에 걸린다.

**검증 상태**: Provisional. 오탐 데이터를 `docs/audits/` 에 쌓은 뒤 차단 승격을 검토한다.

## R-retro — 회고 없이 완료 처리 금지 {#r-retro}

`completed/` 로 **옮긴** 계획서의 §8 이 템플릿 그대로 비어 있으면 경고(차단 아님).

완료 처리의 실질이 파일 경로 이동뿐이어서 회고가 선택 사항이 되어 있었다.

`git diff --cached --diff-filter=RA` 로 이동(rename·신규)만 본다. `git mv` 는 `ACM` 필터에
잡히지 않으므로(2026-08-13 실측) `STAGED` 를 쓸 수 없고, `M`(수정)을 넣으면 옛 계획서의
오타 수정까지 걸려 하지도 않은 작업의 회고를 지어내게 된다.

**한계**: 기계는 "쓰지 않았음" 까지만 본다. 회고의 품질은 판정하지 않는다.
이미 `completed/` 에 쌓인 것은 주간 가드닝의 `[plan-noretro]` 가 수거한다.

**검증 상태**: Provisional.

## P9 — 비밀의 경계는 파일이 아니라 값이다 {#p9}

**원칙**: 자격증명·개인정보를 평문으로 커밋하지 않는다. git 히스토리는 되돌릴 수 없으므로
*들어가기 전에* 막는 것이 유일한 방어다.

**왜 파일 단위 규칙으로는 부족한가**: "`.env` 를 커밋하지 않는다"는 규칙이 완벽히 지켜지는
동안에도, 같은 값이 **채팅 텍스트**로 전달되는 순간 규칙의 사정권 밖으로 나갔다. 실제로
그렇게 새어 세션 기록 파일에 실려 커밋·푸시까지 갔다.

**따르는 규칙 셋**:
- **값 대조가 형태 추측에 우선한다.** `label=value` 딱지를 전제한 마스킹은 사람이 실제로
  주는 형태(`아이디 | 비번`)를 원리상 못 잡는다. `.env` 실재 값을 정답지로 대조한다.
- **면제 규칙은 탐지 단위와 같은 폭이어야 한다.** 줄 단위 탐지에 줄 단위 자리표시자 면제를
  붙이면, 한 줄이 긴 파일(jsonl)에서 `example` 한 번에 그 줄의 진짜 비밀이 통째로 면제된다.
- **패턴을 복제하면 역류 경로를 함께 정한다.** 복제본에서 구멍을 고치고 원본을 두면,
  원본을 쓰는 경로가 계속 뚫려 있다.

**기계 강제**: `pre-commit` R-secret 단계(`check-secrets.py`) + DB·export 경계
마스킹(`hermes_redact.py`). 회귀 고정: `tests/hermes-secret-masking-test.sh`.
소급 정리: `scripts/hermes-scrub-history.py`. 상세: `docs/superpowers/specs/2026-08-10-hermes-secret-masking-design.md`.
