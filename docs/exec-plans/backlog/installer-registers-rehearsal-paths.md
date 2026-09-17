# installer-registers-rehearsal-paths — 임시 경로 가드가 `$TMPDIR` 한 곳만 본다

## 배경

`2026-09-17-install-coexistence` 계획의 리허설 중 `.installed-projects` 에 `/tmp/tmp.*/…`
경로가 두 번(8건·2건) 등록됐다(백업 `.harness/out/installed-projects.{bak,before-cleanup}`).
그 상태로 `update-all.sh` 를 돌리면 이미 지워진 경로를 12개 소우주와 나란히 순회한다.

가드는 이미 있다 — `project-claude.sh:189-193`(커밋 `b7d174a`, 09-16): 프로젝트 경로가
`${TMPDIR:-/tmp}` 아래거나 `HERMES_NO_REGISTER=1` 이면 등록하지 않는다.
**구멍**: `TMPDIR` 이 다른 곳(예: 백그라운드 잡의 `$CLAUDE_JOB_DIR/tmp`)으로 잡힌 채
`mktemp` 를 그 전에 `/tmp` 로 만들어 둔 사본을 설치하면, 가드는 `$TMPDIR` 만 대조하므로
`/tmp/…` 가 빠져나간다. 2026-09-17 재현: `TMPDIR=<잡 디렉터리>` 에서 `/tmp/tmp.X` 를 가드
식에 넣으면 "등록됨".

## 무엇을 하려는 것인가

- 가드가 대조하는 임시 루트를 **`/tmp` 와 `$TMPDIR` 둘 다**(같으면 하나)로 넓힌다.
- `update-all.sh` 가 존재하지 않는 경로를 만나면 순회에서 빼고 한 줄 알린다(2차 방어 —
  등록이 어떤 경로로 새더라도 없는 경로를 돌지 않는다).
- `copy-install-test.sh:157` 의 기존 단언(`/tmp` 프로젝트 설치 → 실 레지스트리 불변)에
  `TMPDIR` 을 다른 곳으로 둔 케이스를 하나 더한다 — 지금 단언은 `TMPDIR` 미설정에서만 초록이다.

## 검증

- `TMPDIR=$(mktemp -d) bash project-claude.sh /tmp/<사본> hermes` 뒤 `.installed-projects`
  에 그 경로가 없고 "레지스트리 등록 생략" 로그 1줄.
- 레지스트리에 없는 경로를 한 줄 넣고 `update-all.sh` → 그 줄은 건너뛰고 알림 1줄, 종료 0.
