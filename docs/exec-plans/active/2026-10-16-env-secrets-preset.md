# 2026-10-16-env-secrets-preset — `.env` 를 암호화해 PC 사이로 옮기는 선택 프리셋

> 출처 구현: 하류 jj-agent-room `scripts/fork/secrets.sh` + `scripts/fork/lib/env-secrets-*.sh`
> (커밋 0246f74 · 2822580 · 31d83d3, 계획 `docs/exec-plans/active/2026-10-15-env-secrets-sync.md`)

---

## 0. 다음 세션 시작점 (2026-10-16 세션 끝 기준)

**진행: 7단계 중 5단계 완료** — Step 1 · 2 · 2b · 3 · 4 끝. 남은 것은 Step 5(검증·리뷰)와 Step 6(전파, 사람 승인 필요).
**아무것도 커밋하지 않았다.** 아래 파일이 전부 작업 트리에만 있다(커밋은 사용자가 정한다 — 매 턴 알림 "자동 커밋 금지").

| 단계 | 상태 | 증거 |
| --- | --- | --- |
| Step 1 시험 먼저 | 완료 | 하류 원본을 꽂으면 56 통과 / 5 실패 — 시험이 가른다 |
| Step 2 자산 옮기기 | 완료 | `env-secrets-test.sh` 57/4 → (2b 뒤) 61/0 |
| Step 2b 가입 안내 | 완료 | 61/0 + 가상 터미널 실측 |
| Step 3 프리셋·설치 | 완료 | `env-secrets-install-test.sh` G1·G4·G7 통과 |
| Step 4 커밋 게이트 | 완료 | 같은 시험 25/25 · `gate-declaration-coverage-test.sh` 36/36 · pre-commit 쓰는 기존 시험 12개 실패 0 · doc-counts 19/19 |
| Step 5 검증·리뷰 | **다음** | — |
| Step 6 전파·하류 이전 | 사람 승인 후 | — |

**다음 세션에서 할 일 (순서대로)**

1. `bash tests/env-secrets-test.sh` · `bash tests/env-secrets-install-test.sh` 를 다시 돌려 61/0 · 25/0 인지 본다(합쳐 약 16초). 다르면 거기서 멈추고 원인부터.
2. Step 5-① 전체 시험: `bash tests/run-all.sh > .harness/out/run-all.log 2>&1` 을 **배경으로** 돌리고 Monitor 로 실패 줄만 지켜본다(전체 묶음은 수 분 걸린다). G9 판정.
3. Step 5-② 보안 리뷰: `code-reviewer` 에 변경 파일(§0 목록)을 주고 "평문·열쇠가 출력·argv·로그로 새는지, 게이트가 커밋을 막거나 멈추는지, `.env.keys` 가 커밋될 길이 있는지" 를 묻는다. 지적은 코드로 반증 조건을 돌려 가린 뒤 반영.
4. 커밋 직전: `readme-sync-before-commit` 스킬로 README **설명** 반영 여부 판정(프리셋 목록·게이트 설명에 env-secrets/R-env-secrets 가 없다 — 수치 블록만 갱신됨). 그다음 `pre-commit-measure` 로 `실측:` 줄.
5. 커밋은 사용자에게 묶음을 보여 주고 받는다. Step 6 은 별도 승인.

**작업 트리에 있는 이번 작업 파일** (`git add` 는 이 목록만 — `-A` 금지)

- 신규: `assets/env-secrets/` (secrets.sh + lib 10) · `presets/tools/env-secrets.conf` · `tests/env-secrets-test.sh` · `tests/env-secrets-install-test.sh` · `tests/fixtures/env-secrets/` (5) · 이 계획서
- 수정: `assets/hooks/pre-commit.sh` · `project-claude.sh` · `lib/harness_installers.sh` · `tests/run-all.sh` · `docs/design-docs/core-beliefs.md` · `README.md` · `CLAUDE.md` · `presets/workflow/harness.conf`(수치 블록만)
- 이번 작업과 **무관**한 변경(세션 시작 전부터 있음, 섞지 말 것): `.claude/.factory-manifest.json` · `.hermes/factory.json` · `.hermes/skills/*.md`

**알아 둘 것**

- 시험은 사용자 캐시 `~/.cache/env-secrets/dotenvx-2.32.3` 의 진짜 dotenvx 를 쓴다(없으면 npm 으로 받음 — 네트워크 필요).
- `ENV_SECRETS_ASSET_DIR=<폴더>` 를 주면 시험이 다른 구현을 대상으로 돈다(시험 자체 검증용).
- 리뷰 HIGH #1(커밋이 비밀번호를 기다리며 멈춤)은 **틀린 전제**였다 — §7 참고. 같은 지적이 다시 나오면 실측(git 2.43: 훅 stdin=/dev/null)으로 답한다.

## 1. 동기 (Why)

- `.env` 는 git 에 안 올라가서 새 PC 마다 손으로 옮기다 빠뜨린다. 2026-10-15 jj-agent-room 새 PC 에서 Google 로그인 키가 없어 로그인이 막혔다.
- jj-agent-room 에서 해결 방식을 만들고 실제로 확인했다(2026-10-16): 다른 PC 역할의 클론에서 `secrets:open` 한 번(Bitwarden 마스터 비밀번호만 입력)으로 원래 PC 와 **바이트 동일한** `.env`(12개 키, 2018바이트, 권한 600)가 생겼다.
- 이 문제는 `.env` 를 쓰는 모든 프로젝트에 같다. 그런데 지금은 jj-agent-room 에만 있다. 공통 기능은 공장이 깔아야 한다(사용자 2026-10-16). 다만 필요 없는 프로젝트도 있으므로 **선택**이어야 한다(사용자 2026-10-16).

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 — `presets.lock` 에 `env-secrets` 가 있는 프로젝트에만 `scripts/env-secrets/` 가 깔린다. 없는 프로젝트에는 아무것도 생기지 않는다. — 검증: 시험(두 임시 프로젝트에 설치, 파일 유무)  ✅ 2026-10-16 `env-secrets-install-test.sh`
- [x] G2 — 깔린 프로젝트에서 `bash scripts/env-secrets/secrets.sh import|sync|open` 이 jj-agent-room 과 같은 동작을 한다: 처음 암호화 + 열쇠 Bitwarden 자동 저장(화면에 안 보임) / `.env` 바뀌면 같은 열쇠로 재암호화 / 풀기(`.env` 없으면 바이트 그대로 복원, 있으면 값 갱신). — 검증: Step 1 에 열거한 공장 시험 단언 전부 통과(하류 시험 27개 시나리오에서 옮김, 옮기지 않는 것은 이유와 함께 §7 에 적음)  ✅ 2026-10-16 `env-secrets-test.sh` 61/0
- [x] G3 — `package.json`·`node_modules` 가 없는 프로젝트(파이썬 등)에서도 동작한다. dotenvx·dotenv 는 고정 판을 사용자 캐시에 받아 쓴다. 필요 조건은 `node`·`npm` 뿐. — 검증: package.json 없는 임시 프로젝트에서 import→open  ✅ 2026-10-16 시험 프로젝트 전부 package.json 없음 + clone 직후 캐시 받기 시험
- [x] G4 — `.env.keys` 가 그 프로젝트의 `.gitignore` 에 들어가고, 프리셋을 lock 에서 빼고 재설치해도 남는다(공통 무시 목록). — 검증: 설치 후·프리셋 뺀 재설치 후 `git check-ignore .env.keys`  ✅ 2026-10-16 `env-secrets-install-test.sh` (프리셋 뺀 재설치 포함)
- [x] G5 — 커밋 게이트에 `R-env-secrets` 단계: `scripts/env-secrets/secrets.sh` 가 있으면 `sync --stage` 를 돌려 바뀐 `.env` 를 그 커밋에 넣는다. 없으면 `skipped`. **절대 커밋을 막지 않고, 입력을 기다리며 멈추지도 않는다**(금고 잠김·열쇠 없음도 경고만. git 이 훅 stdin 을 `/dev/null` 로 주고 게이트가 stderr 도 받는다). — 검증: 시험(실제 git 커밋에 `.env.secrets` 포함 / 스크립트 없으면 skipped / 가짜 bw 가 locked 일 때 프롬프트 없이 끝남) + gate-declaration-coverage 통과  ✅ 2026-10-16 `env-secrets-install-test.sh` 25/25 · gate-declaration 36/36
- [ ] G6 — jj-agent-room 이 포크 전용 복사본 대신 프리셋을 쓴다(`scripts/fork/secrets.sh`·`lib/env-secrets-*` 제거, `.harnessrc` 의 임시 sync 줄 제거, `init:setting`·npm 스크립트는 새 경로를 부름). 기존 `.env.secrets`·Bitwarden 항목은 그대로 열린다. — 검증: 전파 후 jj-agent-room 에서 `open` → 같음 12, 시험 통과
- [x] G8 — Bitwarden 계정이 없는 사람도 막히지 않는다. 금고를 처음 열 때(로그인 안 된 상태) 이메일을 묻기 전에 "계정이 없으면 https://vault.bitwarden.com 에서 무료 가입(마스터 비밀번호는 본인이 정하고, 잊으면 Bitwarden 도 되찾아 주지 못함) 후 다시 실행" 안내를 보인다. 로그인 실패 때도 같은 안내로 끝낸다(지금은 "Bitwarden 열기 실패" 한 줄뿐). — 검증: 시험(가짜 bw 가 unauthenticated → 출력에 가입 주소와 다시 실행 명령) + 가상 터미널 실측  ✅ 2026-10-16 `env-secrets-test.sh` + 가상 터미널 실측
- [x] G7 — 하류 수정이 공장 개정에 덮이지 않는다(`install_factory_file` 의 공존 규칙). — 검증: `tests/env-secrets-install-test.sh` 에서 실제 프리셋으로 설치 → 하류 수정 → 재설치 후 수정 보존  ✅ 2026-10-16 `env-secrets-install-test.sh` 재설치 단언
- [ ] G9 — `tests/run-all.sh` 전체 통과, 고아 시험 0. — 검증: run-all 결과

## 2-bis. 착수 전 확인한 사실 (2026-10-16)

| 확인한 것 | 결과 |
| --- | --- |
| 프리셋 범주 | `presets/{lang,framework,database,build,workflow,permissions,tools}/*.conf` (lib/preset.sh:214-226). `tools/` 에 prettier·terminal-paste-image 가 있음 → `presets/tools/env-secrets.conf` |
| 임의 경로 복사 선언 키 | **없음**. `install_factory_file <src> <dst> <kind> <name> <claude_dir> [mode]` 를 부르는 설치 함수가 필요(lib/factory_coexist.sh:148). 선례 `_hermes_setup`(presets/workflow/hermes.conf:133), 호출 자리는 project-claude.sh:166 에 `declare -f` 로 프리셋별 하드코딩(일반 훅 아님) |
| pre-commit 의 stdin | ~~git 은 훅 stdin 을 터미널에 둔다~~ **틀림(Step 4 실측)**: git 2.43 은 pre-commit 훅 stdin 을 `/dev/null` 로 준다(stderr 만 터미널). 그래서 `env-secrets-vault.sh:52` 가드(`! -t 0 \|\| ! -t 2`)가 프롬프트 전에 끝낸다. 하류 방식(`\|\| true` 만)도 pty 에서 멈추지 않았다 |
| 게이트 선언 시험 | `tests/gate-declaration-coverage-test.sh` 는 `# GATE: R-<이름> <block\|warn>` 선언 + `gate_add R-<이름> <같은 종류>` + `gate_add R-<이름> pass` 를 **모두** 요구. skipped 만으로는 실패 |
| 게이트 집계 | pre-commit.sh:7-8 헤더 목록(경고 10종)과 README/CLAUDE.md 수치 블록을 함께 고쳐야 함 |
| 하류 init 연동 | `lib/env-secrets.sh` 는 `init-setting.sh`·`init-ui.sh`(`ui_record`) 전용. `ENV_SECRETS_ROOT` 는 `env-secrets-config.sh:5` 에서 스크립트 위치(`lib/../../..`)로 계산 |
| 선택 | `.claude/presets.lock` 한 줄에 프리셋 하나(project-claude.sh:189). update-all.sh:88-160 이 lock 대로 재설치 |
| pre-commit 선택 단계 | 프리셋별 조립 장치 **없음**. 관례는 "파일 있으면 실행, 없으면 `gate_add <R> skipped`"(pre-commit.sh:384·470·502·762) |
| package.json | 공장은 안 건드림 → 명령은 `bash scripts/env-secrets/secrets.sh …` 가 기본. npm 스크립트는 프로젝트가 원하면 직접 단다 |
| .gitignore | `GITIGNORE_ENTRIES+=(…)` 키 있음(hermes.conf:453) |
| 시험 등록 | `tests/run-all.sh` 의 `REGISTERED_TESTS` (:226-361), 미등록이면 고아 검사 실패 |
| P9 암호문 면제 | 이미 공장 0397dcb(`CIPHERTEXT_RE`) — 추가 작업 없음 |
| 하류 구현 크기 | secrets.sh 127줄 · lib 9파일(각 17~87줄) · 시험 27개 |

## 3. 비목표 (Out of Scope)

- 1Password 등 다른 비밀번호 관리자 — Bitwarden 무료만(jj-agent-room 결정 유지)
- 프로젝트 `package.json` 에 npm 스크립트 자동 추가 — 공장은 package.json 을 안 쓴다
- `.env` 외 파일(`.env.production` 등) 암호화 — 필요해지면 다음 계획
- 팀 공유·권한 — 혼자 쓰는 여러 PC 가 대상

## 4. 영향 영역

- **신규 (공장):**
  - `presets/tools/env-secrets.conf` — 프리셋 선언(CLAUDE_MD_SECTIONS 사용법, 설치 함수 `_env_secrets_setup`)
  - `assets/env-secrets/lib/env-secrets-signup.sh` — Bitwarden 계정 없는 사람에게 가입 주소·다시 돌릴 명령 안내(G8)
  - `assets/env-secrets/secrets.sh` + `assets/env-secrets/lib/*.sh|mjs` — 하류 구현을 옮김. `ENV_SECRETS_ROOT` 는 하류처럼 스크립트 위치로 계산(`scripts/env-secrets/lib` 도 깊이 3 으로 같음). `init-setting` 연동 파일(`lib/env-secrets.sh`)은 옮기지 않음
  - `tests/env-secrets-test.sh` — import 시나리오 + 아래 두 사례 파일을 불러 G2·G3·G8 판정
  - `tests/fixtures/env-secrets/open-cases.sh` — open 시나리오(복원·갱신·열쇠 출처·bw 자동 설치·캐시 받기·G8 가입 안내)
  - `tests/fixtures/env-secrets/sync-cases.sh` — sync(같은 열쇠로 재암호화)·merge(암호문 값 거절) 시나리오
  - `tests/env-secrets-install-test.sh` — 선택 설치(G1)·.gitignore(G4)·커밋 게이트 R-env-secrets(G5, pty 에서 잠긴 금고 멈춤 없음 포함)
  - `tests/fixtures/env-secrets/helpers.sh` — 시험 공용: 임시 저장소·가짜 금고·`secrets.sh` 실행·첫 PC/다른 PC 만들기·단언
  - `tests/fixtures/env-secrets/fake-bw.js` — Bitwarden CLI 대역(하류 FAKE_BW 이식, 금고는 폴더 안 파일)
  - `tests/fixtures/env-secrets/env-check.mjs` — 단언용 .env 읽기(값은 출력하지 않고 키 이름·종료 코드로만 답함)
- **수정 (공장):**
  - `project-claude.sh` — `_env_secrets_setup` 호출 자리
  - `assets/hooks/pre-commit.sh` — `R-env-secrets` 단계(경고 분류, FAIL 안 올림): `# GATE: R-env-secrets warn` 선언, `gate_add R-env-secrets warn|pass|skipped`, 헤더 :7-8 경고 목록에 추가
  - `tests/run-all.sh` — 새 시험 등록
  - `lib/harness_installers.sh` — 공통 `.gitignore` 목록에 `.env.keys`(프리셋을 빼도 열쇠가 무시되게)
  - `README.md`·`CLAUDE.md`·`presets/workflow/harness.conf` 수치(sync-doc-counts — 완료), README 프리셋 목록·게이트 설명(**미완** — 커밋 전 readme-sync)
  - `docs/design-docs/core-beliefs.md` — `#r-env-secrets` 절(경고 근거 링크)
- **하류 (jj-agent-room, 전파 뒤):** `scripts/fork/secrets.sh`·`scripts/fork/lib/env-secrets-{config,key,open,progress,tools,unlock,vault}.sh`·`env-file.mjs`·`env-vault-item.mjs` 제거, `scripts/fork/lib/env-secrets.sh`(init 단계, 하류에 남김)는 `scripts/env-secrets/lib/*` 를 source 하게, `package.json` 스크립트 경로 교체, `.harnessrc` 임시 줄 제거, `tests/fork-env-secrets.test.ts` 는 새 경로로
- 외부 의존: `@dotenvx/dotenvx@2.32.3`·`dotenv@17.4.2`(캐시), `@bitwarden/cli@2026.9.1`(전역) — 모두 고정 판

## 5. 단계 (Steps)

### Step 1. 공장 시험 먼저 [TDD] — ✅ 완료
- 입력: 하류 `tests/fork-env-secrets.test.ts` 27개 시나리오
- 산출: `tests/env-secrets-test.sh` — 옮긴 시나리오 목록(단언 이름)을 파일 머리에 열거 + G1(선택 설치)·G3(package.json 없음)·G4(.gitignore)·G5(게이트·locked 일 때 안 멈춤)·G8(가입 안내) 단언. `run-all.sh` 등록
- 검증: 실행해 전부 RED(자산 없음)

### Step 2. 자산 옮기기 [Impl] — ✅ 완료
- 입력: 하류 `secrets.sh` + lib 8파일(`env-secrets.sh` 제외)
- 산출: `assets/env-secrets/`. `ENV_SECRETS_ROOT` 계산은 그대로, 하류 전용 문구(`npm run secrets:*`) → `bash scripts/env-secrets/secrets.sh …`
- 검증: G2·G3 단언 GREEN

### Step 2b. 가입 안내 (G8) [Impl] — ✅ 완료
- 산출: `vault_unlock_interactive` 가 unauthenticated 일 때 이메일을 묻기 전에 가입 안내, 로그인 실패(unlock.sh:31 자리)도 같은 안내 + 다시 실행 명령으로 끝냄
- 검증: G8 단언 GREEN + 가상 터미널 실측

### Step 3. 프리셋·설치 함수 [Impl] — ✅ 완료
- 산출: `presets/tools/env-secrets.conf` + `_env_secrets_setup`(install_factory_file, 755) + project-claude.sh:166 옆에 같은 `declare -f` 방식 호출
- 검증: G1·G4·G7 단언 GREEN

### Step 4. 커밋 게이트 단계 [Impl] — ✅ 완료
- 산출: `R-env-secrets`(경고), 블록은 `# GATE: R-env-secrets warn` ~ `# /R-env-secrets`: 스크립트 있으면 `bash scripts/env-secrets/secrets.sh sync --stage` 의 출력을 `$(… 2>&1)` 로 받는다 — git 이 준 stdin(`/dev/null`)과 받은 stderr 때문에 vault.sh:52 가드가 프롬프트 없이 "잠김 — 터미널에서 다시 실행" 으로 끝난다. 출력이 있거나(재암호화·열쇠 없음) 종료 코드가 0 이 아니면 warn(출력을 WARNINGS 에), 출력 없이 0 이면 pass, 스크립트 없으면 skipped. 어떤 경우도 FAIL 안 올림
- 검증: G5 단언 GREEN + `tests/gate-declaration-coverage-test.sh` 통과

### Step 5. 검증·리뷰 — ⏭ 다음 세션
- 시험 GREEN, `tests/run-all.sh` 전체(G9), 보안 관점 code-reviewer(평문·열쇠 노출, 게이트가 커밋을 막거나 멈추지 않는지)

### Step 6. 전파·하류 이전 [사람 승인 후]
- 공장 커밋 → jj-agent-room `presets.lock` 에 `env-secrets` 추가 → `project-claude.sh` 로 그 프로젝트만 설치 → 하류 정리(§4) → `open` 실측 → 커밋
- 다른 프로젝트는 사용자가 고를 때 lock 에 추가

## 6. 의사결정 로그

- 2026-10-16: 선택 프리셋으로 둔다 (사용자) — 근거: `.env` 를 안 쓰거나 필요 없는 프로젝트가 있다
- 2026-10-16: 범주는 `tools/` — 근거: 언어·프레임워크와 무관한 도구 묶음이 이미 여기 있다(prettier)
- 2026-10-16: 명령 진입점은 `bash scripts/env-secrets/secrets.sh` — 근거: 공장은 package.json 을 안 쓰고, 파이썬 프로젝트에도 깔린다
- 2026-10-16: Bitwarden 계정 없는 사용자에게 가입 안내를 띄운다 (사용자) — 근거: 필요한 사전 준비는 dotenvx(무료, 가입 없음·자동 설치)와 Bitwarden 계정(사람당 한 번)뿐인데, 계정이 없으면 지금은 "열기 실패" 로만 끝나 무엇을 해야 할지 알 수 없다
- 2026-10-16: 게이트 단계는 비차단 — 근거: 금고 잠김 때문에 일상 커밋이 멈추면 안 된다(하류에서 같은 결정, 시험 있음)
- 2026-10-16(Step 4 에서 뒤집음): 게이트에 `</dev/null` 을 **붙이지 않는다** — 근거: git 2.43 실측으로 훅 stdin 이 이미 `/dev/null` 이고, 게이트가 출력을 `$(… 2>&1)` 로 받아 stderr 도 터미널이 아니다. 붙이면 쓸모없는 줄이다. 리뷰 HIGH #1 은 재지 않은 전제였다. 멈춤 없음은 pty 회귀 시험으로 지킨다. 타임아웃도 두지 않는다
- 2026-10-16: 게이트 분류는 "경고" — 근거: gate-declaration-coverage 가 block|warn 선언과 pass 기록을 요구한다. 재암호화가 일어났을 때 warn 으로 사람에게 보인다
- 2026-10-16: `ENV_SECRETS_ROOT` 는 스크립트 위치로 계산(git rev-parse 아님) — 근거: 하류에서 검증된 방식이고 설치 경로 깊이가 같다. git 이 아닌 곳에서도 동작
- 2026-10-16: init 연동 파일(`lib/env-secrets.sh`)은 공장에 넣지 않고 하류에 남긴다 — 근거: `init-setting.sh`·`init-ui.sh` 전용이고 공장에 그 장치가 없다

## 6-bis. 위험·되돌리기

- `npm i -g @bitwarden/cli` 실패(권한·네트워크) → 하류처럼 "bw 없음 — 자동 설치 실패, npm i -g …" 안내로 끝남. 커밋 게이트는 영향 없음
- dotenvx·dotenv 캐시 받기 실패(네트워크) → import/open 이 실패 메시지로 끝남. `.env`·`.env.secrets` 는 건드리지 않음(하류 시험 있음)
- `presets.lock` 에서 `env-secrets` 를 빼면 → **실측(Step 3)**: 설치물·manifest 항목은 남고 게이트도 계속 돈다(sync 만 하므로 해 없음). `.env.keys` 무시는 공통 목록으로 옮겨 남게 했다. 설치물 지우기는 uninstall 의 일
- 되돌리기: 공장 커밋 revert. 하류는 Step 6 전이면 영향 없음, Step 6 뒤면 하류 커밋 revert 로 `scripts/fork/` 복원(`.env.secrets`·Bitwarden 항목은 형식이 같아 그대로 열림)

## 7. 발견·예외

- 2026-10-16 Step 1 완료(RED). 하류 27개 중 22개를 옮김. 옮기지 않은 5개와 이유는 `tests/env-secrets-test.sh` 머리 주석:
  저장소 자기 점검 1(공장엔 `.env.secrets` 없음) · init 단계 전용 2(그 파일은 하류에 남음) · `.gitignore`·`.harnessrc` 2(→ `env-secrets-install-test.sh` 의 G4·G5).
  init 단계로 돌던 복원 시험은 같은 일을 하는 `open` 으로 돈다.
- 시험이 가르는지 실측: 자산 자리에 하류 원본을 꽂아(`ENV_SECRETS_ASSET_DIR`) 돌리면 **56 통과 / 5 실패**.
  실패 5개 = 문구 1(`npm run secrets:import` → `bash scripts/env-secrets/secrets.sh import`) + G8 가입 안내 4. Step 2·2b 의 할 일과 정확히 같다.
- 시험은 사용자 캐시(`~/.cache/env-secrets/dotenvx-<판>`)의 고정 판 dotenvx 를 쓰고, 없으면 도구와 같은 명령으로 받는다(조용한 skip 없음).
- 게이트 블록 끝 표지는 `# /R-env-secrets` — 시험이 이 사이만 잘라 돈다(Step 4 에서 그대로 만든다).
- 2026-10-16 Step 2 완료. 하류 10파일(secrets.sh + lib 9, `lib/env-secrets.sh` 제외)을 `assets/env-secrets/` 로 복사.
  바꾼 것은 하류 전용 문구 8곳뿐 — 다시 돌릴 명령을 `env-secrets-config.sh` 의 `ENV_SECRETS_CMD`(`bash scripts/env-secrets/secrets.sh`) 한 곳에 두고
  메시지 3곳이 그것을 쓴다(`npm run secrets:import`·`npm run init:setting` 대체), 나머지는 주석·계획 경로·금고 항목 메모.
  `env-secrets-test.sh` **57 통과 / 4 실패** — 남은 4개는 전부 G8(Step 2b).
- 2026-10-16 Step 2b 완료. 가입 안내를 새 파일 `lib/env-secrets-signup.sh`(`vault_signup_hint`)로 두고 세 자리에서 부른다:
  대화형 로그인에서 이메일 묻기 전 · 로그인 3회 실패 뒤(로그인 안 된 상태만 — 잠금 해제 실패는 이미 계정이 있다) · 터미널이 아니라 로그인 못 할 때.
  다시 돌릴 명령은 하위 명령을 따른다(import → import, 그 밖 → open). `secrets.sh` 가 명령을 고르기 직전에 `ENV_SECRETS_SUBCOMMAND` 를 정한다.
  `env-secrets-test.sh` **61 통과 / 0 실패**(9초). 가상 터미널(`script`) 실측: 이메일 앞 안내 3줄 · 3회 실패 뒤 같은 안내 · 입력 비밀번호 화면에 없음.
- 2026-10-16 Step 3 완료. `presets/tools/env-secrets.conf`(`_env_secrets_setup` — `install_factory_file` 로 진입점 755·lib 644) + `project-claude.sh` 에 `_hermes_setup` 옆 같은 `declare -f` 호출.
  `env-secrets-install-test.sh` **19 통과 / 6 실패** — 실패 6개는 전부 G5(Step 4). 프리셋 무결성 시험 통과, `.gitignore` 블록을 만지는 기존 시험 4개 통과.
- 계획과 다르게 한 것 ①: node·npm 을 `REQUIRED_BINS` 로 선언하지 않았다 — 그 목록은 `lib/tool_installers.sh` 의 핀 표(sha256 고정 배포 파일)에 있는 도구만 받는다.
  확인은 도구가 실행 때 한다(`env-secrets-tools.sh`: npm 없으면 "Node.js 설치 필요").
- 계획과 다르게 한 것 ②: `.env.keys` 무시 줄을 프리셋(`GITIGNORE_ENTRIES`)이 아니라 공통 목록에 뒀다. **실측**: 프리셋을 lock 에서 빼고 재설치하면
  `scripts/env-secrets/`·manifest 11항목은 남는데 `.gitignore` 의 `.env.keys` 만 사라졌다 → 열쇠가 `git add .` 한 번에 커밋될 수 있었다.
  모든 소우주 `.gitignore` 블록에 한 줄이 는다(없는 파일 무시 — 해 없음). 전파 때 함께 간다.
- 계획과 다르게 한 것 ③: G7 은 `install-coexist-test.sh` 대신 실제 프리셋 설치로 잰다 — 공존 함수는 경로와 무관하고, 재고 싶은 것은 "이 프리셋 경로로 깔린 파일" 이다.
- 프리셋을 lock 에서 빼도 `scripts/env-secrets/`·게이트는 남는다(지우지 않음). 남은 게이트는 sync(재암호화)만 하므로 해는 없다. 지우기는 uninstall 의 일 — 이 계획 밖.
- 2026-10-16 Step 4 완료. `assets/hooks/pre-commit.sh` 에 R-env-secrets 블록(`# GATE: R-env-secrets warn` ~ `# /R-env-secrets`, R-config 뒤),
  머리말 경고 목록 10 → 11, `core-beliefs.md#r-env-secrets` 절 추가. `env-secrets-install-test.sh` **25/25**, `gate-declaration-coverage-test.sh` **36/36**.
- **리뷰 HIGH #1 전제가 틀렸다(실측)**: pty 에서 `git commit` 을 돌리고 훅이 `[ -t 0 ]` 를 찍게 하니 `stdin=not-tty(/dev/null)`, `stderr=tty`(git 2.43.0).
  하류 방식 대조군(`secrets.sh sync --stage || true`)도 잠긴 금고에서 0초 만에 "bw 잠김 — 터미널에서 다시 실행" 으로 끝났다.
  그래서 계획의 `</dev/null` 은 넣지 않았고, pty 시험은 "가르는 시험" 이 아니라 **회귀 시험**이다(그 성질이 깨지면 빨개진다). 지난 턴에 이 전제를 재지 않고 받아들인 것이 잘못.
- 문서 수치(README·CLAUDE.md·harness.conf): `doc-counts-gate-test.sh` 가 낡음을 잡아 `bash scripts/sync-doc-counts.sh` 로 갱신 — 21→22종(경고 9→10), 시험 135→137. 다시 19/19.
  pre-commit.sh 를 쓰는 기존 시험 12개 전부 실패 0.
  경고가 11 이 아니라 10 인 것은 `# GATE: R-precheck warn   # …` 줄 끝 주석 때문에 `doc_counts.py:126` 정규식에 안 걸려서다 — 이번 변경과 무관한 기존 상태.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
