# 설치 영수증 — 설치기가 쓴 파일을 기록하고, 미커밋이면 다음 세션에서 알린다

> 작성일: 2026-09-16
> 목적: 전파 뒤 커밋할 경로를 사람·에이전트의 기억으로 정하지 않게 한다. 설치기가 이번에 쓴 파일 목록을 남기고, 그 중 커밋되지 않은 것이 있으면 세션 시작 때 경고한다.

## 1. 동기 (Why)

2026-09-16 복사 설치 전파(계획 `2026-09-15-copy-install.md` Step 7)에서 9곳을 커밋할 때 add 경로를
손으로 정했다(`.claude .hermes/factory.json .gitignore scripts/hooks CLAUDE.md`). hermes 프리셋이
`scripts/hermes-*.py` 사본 7개도 복사한다는 사실(`presets/workflow/hermes.conf:73`)을 놓쳐
5곳(novel-ab·novel-bc·ai-create·jjackkun_bot·upbit-ai-trading)이 그 7개를 뺀 채 푸시됐다.
커밋 뒤 "남은 변경 N건" 숫자만 보고 내용을 열지 않은 것이 두 번째 원인이다.

설치기가 프로젝트 안에 파일을 쓰는 지점은 `lib/harness_installers.sh` 에만 20곳이 넘어 지점마다
기록을 넣는 방식은 수정 범위가 크고 새 지점이 생길 때 또 빠진다. 설치 시작 표식 이후 바뀐 파일을
끝에서 한 번에 모으는 편이 지점 수와 무관하다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 설치가 끝나면 `.claude/.last-install.txt` 에 이번 설치가 쓴 파일이 저장소 상대경로로
  한 줄씩 남는다. 검증: 테스트 샌드박스 설치 후 파일에 `.claude/skills/<x>/SKILL.md`·`scripts/hooks/*`·
  `CLAUDE.md` 가 있고, 설치가 건드리지 않은 `src/keep.txt` 는 없다.
- [x] 목표 2 — `cp -p`(mtime 보존) 로 복사된 파일도 잡힌다. 검증: ctime 기준(`find -cnewer`)이며
  테스트에서 `cp -p` 한 파일이 목록에 있다.
- [x] 목표 3 — 영수증 자체는 커밋되지 않는다. 검증: 관리 `.gitignore` 블록에 `.claude/.last-install.txt`.
- [x] 목표 4 — 세션 시작 훅이 영수증의 파일 중 git 이 무시하지 않으면서 미커밋인 것이 있으면
  `[install-uncommitted WARN] 설치물 N건이 커밋되지 않았습니다` 를 stderr 로 낸다. 전부 커밋돼 있거나
  영수증이 없으면 조용하다. 검증: 테스트에서 커밋 전 경고·커밋 후 무경고.
- [x] 목표 5 — 이전 절차 문서의 커밋 명령이 영수증을 읽는다. 검증: `migration/copy-install-all-universes.md` §3.

## 3. 비목표 (Out of Scope)

- 설치기 쓰기 지점마다 기록 호출을 넣는 것.
- 자동 커밋. 영수증은 목록일 뿐, 커밋은 사람이 한다.
- `.pyc` 등 프로젝트가 잘못 추적 중인 파일 정리.

## 4. 영향 영역

- 코드: `project-claude.sh`(영수증 시작·끝 호출), `lib/common.sh`(source), `lib/harness_installers.sh`
  (`.gitignore` 관리 항목 1줄), `presets/workflow/harness.conf`(훅 복사 목록·SESSION_START 등록),
  `lib/uninstall_helpers.sh`(영수증 제거), `tests/run-all.sh`(등록)
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `lib/install_receipt.sh` — 설치 시작 표식을 만들고, 끝에서 표식 이후 바뀐 파일을 `.claude/.last-install.txt` 에 쓴다.
  - `assets/hooks/claude-sessionstart-install-uncommitted-warn.sh` — 영수증의 파일 중 무시되지 않은 미커밋 파일이 있으면 경고한다.
  - `tests/install-receipt-test.sh` — 목표 1·2·3·4 검증.
- 룰: P10(설치물은 저장소 밖을 가리키지 않는다) 과 무관. R-declare 대상 신규 파일 3개는 위에 선언.
- 데이터: 없음.
- 외부 의존: `find -cnewer`(GNU findutils, WSL 기본).

## 5. 단계 (Steps)

### Step 1. 영수증 모듈 + 설치기 연결 [단순]

- 입력: `project-claude.sh` 의 Apply 블록 시작(`mkdir -p "$CLAUDE_DIR"`)과 레지스트리 등록 직전.
- 산출: `lib/install_receipt.sh`, 호출 2곳, `.gitignore` 항목, 로그 한 줄 "이번 설치가 쓴 파일 N건 → .claude/.last-install.txt".
- 검증: 목표 1·2·3.

### Step 2. 세션 시작 훅 [단순]

- 산출: `assets/hooks/claude-sessionstart-install-uncommitted-warn.sh`, harness.conf 등록.
- 검증: 목표 4.

### Step 3. 테스트·문서·공장 자기 재설치 [단순]

- 산출: `tests/install-receipt-test.sh`, run-all 등록, migration 문서 §3, 공장 자기 재설치로 훅 사본 동기화.
- 검증: `bash tests/install-receipt-test.sh`, `bash tests/run-all.sh`.

## 6. 의사결정 로그

- 쓰기 지점 계측 대신 표식 이후 변경 스캔 — 지점이 20곳 이상이고 앞으로 늘어난다 — 손해: 설치 중 다른
  프로세스가 쓴 파일이 섞일 수 있다(설치는 수 초, 실무상 드묾).
- ctime(`-cnewer`) 기준 — `harness_installers.sh:699·704` 의 `cp -p` 가 mtime 을 보존해 mtime 기준이면
  빠진다 — 손해: 권한 변경만 된 파일도 잡힌다(설치기는 권한을 바꾸지 않으므로 실제로는 같음).
- 영수증 위치 `.claude/.last-install.txt` — `.hermes/` 는 hermes 프리셋 없는 프로젝트(rim-kanban)에 없다
  — 손해: `.claude/*` 를 무시하는 프로젝트(kis-trading)에서도 무시되지만 영수증은 원래 커밋 대상이 아니다.
- 스캔 제외 디렉터리 `.git node_modules .venv venv __pycache__` — 설치기가 쓰지 않는 큰 디렉터리 — 손해:
  이 이름의 디렉터리에 설치기가 쓰게 되면 영수증에서 빠진다.

## 7. 발견·예외

1. **같은 틱 ctime 은 "이후"가 아니다.** `receipt_begin` 직후(같은 커널 틱)에 쓰인 파일은 표식과
   ctime 이 나노초까지 같아 `find -cnewer` 에 잡히지 않았다. 첫 테스트에서 `cp -p` 단언이 실패해
   드러났다. `receipt_begin` 이 탐침 파일로 "표식보다 새로운 시각"이 될 때까지 기다리게 고쳤다
   (같은 틱 재현 10회 전부 포착).
2. **b7d174a(임시 경로 등록 생략)가 기존 테스트 2개를 조용히 깨뜨려 놨다.** `update-all-roundtrip`
   은 레지스트리가 비어 아무 프로젝트도 돌지 않았는데 단언 11개가 "갱신 안 됨"으로만 보였고,
   `uninstall-roundtrip` 은 등록 단언에서 실패했다. 두 테스트에 `TMPDIR` 을 하위 폴더로 옮겨
   `$PROJ` 가 임시 경로로 판정되지 않게 했다. **전파 커밋 때 run-all 을 돌리지 않은 대가다.**
3. `copy-install-test` 7-b 의 "실 저장소 작업 트리에 새 파일 없음" 은 작업 중 미추적 파일이 있으면
   깨지는 단언이었다. 설치 전후 비교로 바꿨다.

## 8. 회고 (완료 시 작성)

- **원인은 기억에 의존한 커밋 경로.** 사고(hermes 스크립트 7개 누락)는 설치기가 무엇을 썼는지
  기계가 말해주지 않아 사람·에이전트가 외워야 했던 데서 나왔다. 영수증은 그 외움을 없앤다.
- **계측 지점을 늘리지 않은 선택이 맞았다.** 쓰기 지점은 `harness_installers.sh` 에만 20곳이 넘고
  앞으로도 는다. 표식 이후 변경 스캔은 지점 수와 무관해서 새 프리셋이 무엇을 복사하든 자동으로 잡힌다.
- **남은 약점**: 설치 도중 다른 프로세스가 같은 저장소에 파일을 쓰면 영수증에 섞인다. 설치는 수 초라
  실무상 드물고, 섞여도 결과는 "커밋 후보가 하나 더 보임" 이라 손해가 작다.
