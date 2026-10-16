# 2026-10-16-language-neutral-structure-gate — 폴더·배럴 구조 검사를 언어 무관 엔진 + 언어 설정표로 바꾼다

> 작성일: 2026-10-16
> 목적: R-struct(폴더·배럴 강제)가 Vue 에서만 동작하는 것을, 공장이 설치하는 모든 언어와 흔한 언어까지 넓힌다.
> 출처: drh-cloth-shop 세션(SvelteKit + FastAPI 착수 전 점검)에서 "배럴 패턴 강제가 적용돼 있나" 질문으로 발견.
> 리뷰: planner-lite 1회(2026-10-16, NEEDS_WORK — CRITICAL 2 · HIGH 4 · MEDIUM 5 · LOW 3) 반영본. 반영 내역은 §6 끝.

---

## 1. 동기 (Why)

- `assets/hooks/check-component-structure.mjs` 는 첫 커밋(2026-07-01, `6c2bff4`)부터 **`.vue` 만** 폴더·배럴(R-struct-1~3)을 검사한다.
  R-struct-4(`export *` 금지)도 `index.js/ts` 배럴만 본다.
- 2026-10-03 terminal-shipping 감사(`backlog/prompt-audit-terminal-shipping-findings.md` #3)가 "R-struct 가 Vue 전제라 SvelteKit 에 안 맞는다"고 지적했지만,
  처리(`8302719`)는 `assets/rules/web/coding-style.md` 에 **"적용 범위: `.vue` 파일만"** 문구를 넣은 것이었다. 검사는 넓히지 않았다.
- 공장 스스로 `core-beliefs.md` R-struct-4 에 "파이썬 `__init__.py` 는 아직 대상이 아니다"라고 적어 두었다.
- 결과: 공장 프리셋 중 **vue 하나만** 구조가 기계로 강제되고, svelte·react·python·java·flutter 프로젝트는 규칙 문서(`common/coding-style.md` 배럴 절, `structured-file-layout` 스킬)로만 안내된다.
  drh-cloth-shop(svelte+fastapi)·terminal-shipping(svelte) 모두 이 상태다.
- 규칙 문서는 이미 언어별 배럴을 말한다(`common/coding-style.md`: TS/JS `index`, Python `__init__.py`, Go 패키지, Rust `mod.rs`, Java 패키지). 강제 장치만 따라오지 않았다.

## 2. 목표 (What — 검증 가능한 형태)

- [ ] G1. 검사기가 **언어 무관 엔진 + 언어 설정표** 구조다 — 검증: Step 1 에서 확정한 설정표 스키마로 Tier B 언어를 추가할 때 엔진 diff 를 Step 4 커밋 범위에서 `git diff --stat <Step3 끝 커밋>..HEAD -- assets/hooks/*.mjs` 로 잰다. 0줄이 목표, 스키마 개정이 필요하면 개정 이유를 §6 에 남기고 개정 후 남은 Tier B 언어로 다시 0줄을 잰다
- [ ] G2. 설정표 항목마다 **규칙 수만큼** 위반 fixture 가 있고 각각 기대대로 판정된다 — 검증: `tests/structure-gate-test.sh` 가 (a) 언어×규칙 bad → 기대 판정(차단/경고), good → 통과, bad 를 고치면 통과로 바뀜, (b) "설정표의 (언어, 규칙) 쌍 수 == fixture 가 덮는 쌍 수" 를 단언
- [ ] G3. 기존 Vue 동작이 그대로다 — 검증: 기존 `tests/struct-barrel-test.sh` 전부 통과(시험 파일 수정 없이)
- [ ] G4. 설치된 소우주에서 기존 코드가 갑자기 막히지 않는다 — 검증: `.installed-projects` 의 프로젝트 전부에 보고 모드 실행 → 프로젝트별 위반 수를 §7 에 기록. drh-cloth-shop 에서 기준선 생성 → 새 위반 하나 심어 차단 → 지우면 통과. 기준선에 있는 파일을 `git mv` 해도 새 위반으로 잡히지 않음
- [ ] G5. 규칙 문서가 강제 범위와 일치한다 — 검증: `web/coding-style.md` 의 언어별 강제 범위표와 `structure-langs.json` 의 (언어, 규칙) 목록을 시험 스크립트가 비교해 일치
- [ ] G6. R-iface(공개 심볼 수)가 Tier A·B 언어에서 동작한다 — 검증: `bash tests/iface-guard-lang-test.sh` — 언어별 공개 심볼 8개 파일 쓰기 차단 / 7개 통과
- [ ] G7. 검사기 고장이 커밋을 막지 않는다 — 검증: 설치본에서 엔진 파일 하나를 지우거나 JSON 을 깨면 차단이 아니라 `R-struct skipped` 가 `gate-events.jsonl` 에 남는다

## 2-bis. 착수 전 확인한 사실 (2026-10-16)

| 확인한 것 | 결과 |
| --------- | ---- |
| 검사기 | `assets/hooks/check-component-structure.mjs` 127줄. 대상 확장자 `.vue .js .jsx .ts .tsx` (`.svelte`·`.py` 없음) |
| pre-commit 호출 | `assets/hooks/pre-commit.sh:540~564`. `VUE_AND_CODE=$(filter_files '\.(vue\|js\|jsx\|ts\|tsx)$')` 만 넘기고, `xargs node … \|\| {` — **종료 코드가 0 이 아니면 무엇이든 "구조 위반 차단"** (고장과 위반을 구분 못 함) |
| 켜는 스위치 | `presets/framework/vue.conf` 의 `HARNESS_COMPONENT_STRUCTURE=1` 하나뿐 (`lib/harness_installers.sh:462` 에서 ESLint 짝 설치에 사용) |
| 설치 방식 | `lib/harness_installers.sh` `install_harness_pre_commit`(70~) 이 파일을 하나씩 `.git/hooks/` 로 평평하게 복사 (하위 폴더 없음) |
| `.harnessrc` | 저장소 루트의 선택 파일, `pre-commit.sh:21` 에서 bash `source`. drh-cloth-shop 에는 없음 |
| 설치 프로젝트 목록 | 공장 루트 `.installed-projects` (머신 로컬 레지스트리, `lib/registry.sh`) 11줄 |
| R-size 대상 확장자 | `pre-commit.sh:46` `py js jsx ts tsx svelte vue` — java·dart·go 등 없음 |
| R-iface 지원 | `claude-pretooluse-iface-guard.sh` `.py`, `.js/.jsx/.ts/.tsx`, `.vue/.svelte` 만 |
| ESLint 짝 | `assets/lint-configs/eslint/component-structure.config.js` (Vue 규칙) |
| 기존 시험 | `tests/struct-barrel-test.sh` (R-struct-4) |
| 공장 언어 프리셋 | `presets/lang/`: node, python, java, flutter / `presets/framework/`: react, svelte, vue, fastapi, springboot |
| 이 PC 런타임 | node 22.23.3, python 3.12.3. go·cargo·javac·dart 등 없음 → 검사는 소스 텍스트만 읽는다 |

## 3. 비목표 (Out of Scope)

- "이 파일의 책임이 정말 하나인가"의 의미 판정 — 기계로 불가. 스킬·리뷰 에이전트 몫으로 남긴다.
- 언어별 컴파일러·AST 도구 사용 — 이 PC·설치 대상에 없을 수 있다. 정규식 + 경량 토큰화로 한정.
- 코어/확장 같은 **프로젝트 고유 경계** 검사 — 프로젝트 `core-beliefs.md` 몫(예: drh-cloth-shop P-core).
- ESLint 규칙의 언어 확장 — pre-commit 검사기가 단일 출처. ESLint 짝은 JS 계열만 유지.

## 4. 영향 영역

- 코드: `assets/hooks/`, `assets/hooks/pre-commit.sh`, `lib/harness_installers.sh`, `presets/**/*.conf`, `assets/hooks/claude-pretooluse-iface-guard.sh`, `assets/rules/web/coding-style.md`, `assets/rules/common/coding-style.md`, `docs/design-docs/core-beliefs.md`(R-struct 절)
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `assets/hooks/check-structure.mjs` — 스테이지된 파일을 받아 설정·규칙 모듈을 불러 돌리고, 결과를 종료 코드(0 통과 · 1 차단 위반 · 3 경고만 · 2 내부 오류)로 돌려주는 진입점만 한다
  - `assets/hooks/structure-langs.json` — 언어별 확장자·배럴 파일 이름·import 패턴·전량 재노출 패턴·기본 예외만 담는다
  - `assets/hooks/structure-config.mjs` — 설정표 읽기, 켤 언어 고르기, 예외 경로(기본·`.harnessrc`·공장 영수증) 판정만 한다
  - `assets/hooks/structure-resolve.mjs` — import 문자열을 저장소 기준 경로로 풀고 같은 기능인지 가르기만 한다
  - `assets/hooks/structure-output.mjs` — 판정 결과를 글과 종료 코드로 바꾸기만 한다
  - `assets/hooks/structure-rules-common.mjs` — 언어 무관 규칙(폴더당 파일 수·금지 이름·타입별 폴더·깊이)만 판정한다
  - `assets/hooks/structure-rule-barrel.mjs` — 기능 폴더에 설정표의 배럴 파일이 있는지만 판정한다
  - `assets/hooks/structure-rule-deep-import.mjs` — 다른 기능의 배럴을 건너뛴 import 만 판정한다
  - `assets/hooks/structure-rule-reexport.mjs` — 배럴의 전량 재노출만 판정한다
  - `assets/hooks/structure-baseline.mjs` — `.structbaseline` 읽기·쓰기와 "새 위반만 남기기"만 한다
  - `tests/structure-gate-test.sh` — 언어×규칙 사례 시험의 셸 진입점만 한다
  - `tests/structure-gate-run.mjs` — 사례를 임시 폴더에 펼쳐 판정과 커버리지를 단언만 한다
  - `tests/iface-guard-lang-test.sh` — 언어별 공개 심볼 수 판정(차단 8 / 통과 7)만 단언한다
  - `tests/structure-install-test.sh` — 임시 저장소 설치·부분 설치·신구 혼합 조합의 동작만 단언한다
  - `tests/fixtures/structure/cases.json` — 언어·규칙별 위반(bad)·수정(good) 사례만 담는다
- 바뀌는 파일: `check-component-structure.mjs` 는 Vue 규칙(R-struct-1~3)을 엔진의 `vue` 설정으로 옮긴 뒤 **삭제하지 않고** `check-structure.mjs` 를 부르는 얇은 호환 래퍼로 둔다(설치된 소우주의 옛 pre-commit 이 이 이름을 부르므로)
- 설치기: 구조 검사기 파일 목록을 `lib/harness_installers.sh` 안 **한 배열**로 관리해 하나씩 복사한다(목록이 흩어지면 부분 설치가 생긴다)
- 스위치 (옛 → 새):

| 옛 | 새 | 기본값 | 관계 |
|---|---|---|---|
| `HARNESS_COMPONENT_STRUCTURE=1` (vue.conf) | 그대로 유지 — ESLint 짝 설치 전용 | 꺼짐 | 의미 바뀌지 않음 |
| (없음) | `HARNESS_STRUCT_LANGS="vue svelte js python …"` — 프리셋 conf 가 자기 언어를 덧붙임 | Tier A 프리셋 언어만 | 엔진이 검사할 언어 목록 |
| (없음) | `.harnessrc` 의 `STRUCT_LANGS_EXTRA="go rust"` — Tier B 를 프로젝트가 켬 | 비어 있음 | 위 목록에 더함 |
| (없음) | `.harnessrc` 의 `STRUCT_EXEMPT="src/lib/components/ui/"` — 프로젝트 예외 경로 | 설정표 기본 예외만 | 설정표 예외에 더함 |

- 룰: R-struct-1~4 (공장 `core-beliefs.md`), R-size, R-iface
- 데이터: 없음
- 외부 의존: 없음 (node 표준 라이브러리만)

## 4-bis. 언어 범위

"가능한 언어 전부"(사용자 요청)를 두 묶음으로 나눈다. 나누는 기준은 **공장이 그 언어 프리셋을 설치하는가**(자동으로 켤지 여부)다. 둘 다 이번 계획에서 만든다.

**판정 수준:** 배럴 존재·전량 재노출은 **차단**. 깊은 경로 import 는 같은 기능 안의 정당한 import 와 정규식으로 가르기 어려워 **경고로 시작**하고, Step 5 실측에서 거짓양성이 [__]% 이하인 언어만 차단으로 올린다(기준값은 Step 5 분포를 보고 사람 승인으로 정한다).

### Tier A — 공장 프리셋이 설치하는 언어 (프리셋에서 자동으로 켠다)

| 언어 | 배럴(공개 출입구) — 차단 | 깊은 경로 import — 경고로 시작 | 전량 재노출 — 차단 |
|---|---|---|---|
| JS / TS (node·react) | `index.js` `index.ts` (`.jsx/.tsx` 포함) | 다른 기능 폴더의 `index` 가 아닌 파일 경로 | `export *` |
| Svelte | `컴포넌트/index.svelte` (전역 CLAUDE.md §6) | `.svelte` 파일 직접 경로 (`index.svelte` 제외) | 배럴 `index.js` 에서 `export *` |
| Vue | `Foo/Foo.vue` + `index.js` (기존 R-struct-1~3 그대로 — 기존 차단 유지) | `.vue` 직접 경로 (기존 차단 유지) | `export *` |
| Python (python·fastapi) | 기능 폴더 `__init__.py` | 다른 기능 패키지의 하위 모듈 직접 import (`from a.b.c import`) | `from x import *` |
| Java (java·springboot) | 기능 패키지 루트 | 다른 기능의 `internal`/`impl` 하위 패키지 import (관례 기반) | `import a.b.*` (다른 기능 대상) |
| Dart (flutter) | `lib/<기능>/<기능>.dart` 라이브러리 파일 | 다른 기능의 `src/` 직접 import (Dart 관례상 `src/` 는 비공개) | `show` 없는 `export` |

### Tier B — 프리셋은 없지만 설정표 항목 + fixture 로 지원 (`.harnessrc` `STRUCT_LANGS_EXTRA` 로 켠다)

| 언어 | 배럴 | 깊은 경로 import (경고) | 전량 재노출 |
|---|---|---|---|
| Go | 패키지 자체 — 파일 불필요 | `internal/` 은 컴파일러가 막음 → 언어 무관 규칙만 | 없음 |
| Rust | `mod.rs` / `lib.rs` 의 `pub use` | `use crate::<기능>::<하위>::` | `pub use x::*` |
| Kotlin | 기능 패키지 루트 | Java 와 같음 | `import a.b.*` |
| C# | 기능 네임스페이스 | `.Internal` 네임스페이스 직접 사용 | 없음 |
| PHP | PSR-4 네임스페이스 | `\Internal\` 직접 사용 | 없음 |
| Swift | 모듈 | 언어 무관 규칙만 (모듈 경계는 빌드가 막음) | `@_exported import` |
| Ruby | `lib/<기능>.rb` | 다른 기능의 하위 파일 직접 `require` | 없음 |

- 언어 무관 규칙(§5 Step 2)은 Tier A·B 전부에 적용된다.
- 여기 없는 언어는 설정표에 항목을 추가하면 같은 엔진으로 붙는다(G1).

## 5. 단계 (Steps)

단계 태그: `[Plan/Impl/Review]` 는 계획 → 구현 → 검토 샌드위치를 거치는 비자명한 단계, `[단순]` 은 바로 구현·검증하는 단계 (`docs/exec-plans/template.md` §5 머리말).

### Step 0. 실측 먼저 — 대상 목록과 분포 [단순]

- 입력: 공장 루트 `.installed-projects`
- 산출: 프로젝트별 언어·폴더 깊이 분포·폴더당 파일 수 분포 표(§7)
- 검증: 11개 줄 전부 처리(경로가 없는 줄은 "없음"으로 표에 남김). 이 표로 Step 2 의 깊이 임계 [__] 를 정한다

### Step 1. 엔진 규약 확정 + Vue 이식 [Plan/Impl/Review]

- 산출:
  - 설정표 스키마 — 필드 목록(확장자, 배럴 이름, import 정규식과 캡처 그룹 규약 `(?<target>…)`, 재노출 정규식, 기본 예외)을 이 계획 §6 에 적고 `structure-langs.json` `vue` 항목으로 구현
  - 종료 코드 규약 0/1/2/3 (§4), 위반 메시지 형식 `[R-struct-N] 경로 → 수정 지침` (기존 형식 유지, 새 규칙 번호: 5 배럴 존재 · 6 깊은 import · 7 언어 무관)
  - 텔레메트리: 게이트 이름은 `R-struct` 하나, `gate-events.jsonl` 상세 칸에 `lang=… rule=…`
  - 경로 처리: 입력 경로를 `/` 로 정규화, 심볼릭 링크는 따라가지 않음
  - `check-structure.mjs`, `structure-rule-*.mjs`(vue 분), 호환 래퍼
- 검증: `tests/struct-barrel-test.sh` 무수정 통과(G3). 커밋당 호출 1회에서 실행 시간 측정값을 §7 에 기록

### Step 2. 언어 무관 규칙 [Plan/Impl/Review]

- 입력: `structured-file-layout` 스킬의 기준, Step 0 분포
- 산출: `structure-rules-common.mjs` — 전부 **경고**
  - 폴더당 파일 수: 스킬 문구 "같은 폴더 내 파일이 5개를 넘으면 하위 폴더를 검토"
  - 금지 이름: `utils` `helpers` `common` `misc` (스킬 "흔한 실수" 표)
  - 타입별 최상위 폴더(`services/` `routers/` `schemas/` 만 있는 구조)
  - 폴더 깊이: Step 0 분포로 정한 값
- 검증: fixture 로 규칙마다 발화·미발화

### Step 3. Tier A 언어 [Plan/Impl/Review]

- 산출: 설정표 js/ts·svelte·python·java·dart 항목 + 언어×규칙 fixture
- 검증: G2 (a)(b)

### Step 4. Tier B 언어 [단순]

- 산출: 설정표 go·rust·kotlin·csharp·php·swift·ruby 항목 + fixture
- 검증: G2, G1(엔진 diff 측정)

### Step 5. 기준선과 설치 소우주 실측 [Plan/Impl/Review]

- 산출: `structure-baseline.mjs`, `.structbaseline`
  - 위반 키: `규칙|경로|대상` (대상 = 깊은 import 면 import 문자열, 배럴이면 폴더, 재노출이면 배럴 줄 내용). 같은 파일의 새 위반은 대상이 달라 새 키가 된다
  - 이름 바꾸기: `git diff --cached -M --name-status` 의 `R` 줄로 옛 경로 키를 새 경로로 옮긴다
  - 라쳇: 키는 줄어들기만 한다. 키를 늘리는 갱신은 `--update-baseline` 명령으로만, 사람이 실행 (`.cxbaseline` 과 같은 원칙)
- 검증: G4. 깊은 import 거짓양성률(보고 모드 위반 중 사람이 정당하다고 본 비율)을 언어별로 §7 에 기록 → 차단 승격 여부를 사람이 결정

### Step 6. 연결: pre-commit·설치기·프리셋 [Plan/Impl/Review]

- 산출:
  - `pre-commit.sh` R-struct 절: 필터를 `HARNESS_STRUCT_LANGS` 의 확장자 합으로 넓히고 `check-structure.mjs` 호출. 종료 코드 1 → 차단, 3 → 경고, 2 → `skipped` + 이유
  - R-size 대상 확장자(`pre-commit.sh:46`)에 Tier A·B 확장자 추가
  - 설치기 한 배열로 새 파일 복사, 프리셋 conf 에 `HARNESS_STRUCT_LANGS` 덧붙임
- 검증 (`tests/structure-install-test.sh`):
  - 임시 저장소 설치 → `.git/hooks/` 에 목록 전부 존재 + svelte·python 위반 커밋 차단
  - 부분 설치(엔진 파일 하나 삭제, JSON 깨기) → 차단 아님, `skipped` 기록 (G7)
  - **옛 pre-commit + 새 파일**: 옛 필터로 `.vue/.js/.ts` 만 넘어가도 Vue 판정이 지금과 같음, 새 언어는 미검사임을 확인(전파 전 구간의 알려진 한계로 §7 에 기록)
  - **새 pre-commit + 옛 파일**(`check-structure.mjs` 없음): `skipped` 기록, 차단 아님

### Step 7. R-iface 언어 확장 [Plan/Impl/Review]

- 산출: `claude-pretooluse-iface-guard.sh` 공개 심볼 판정에 java·kotlin·csharp·php(`public`), go(대문자 시작), rust(`pub`), dart(밑줄 없음), swift(`public`/`open`) 추가. ruby 는 공개 판정 규칙이 없어 제외(§7 기록)
- 검증: G6

### Step 8. 문서 정합 [단순]

- 산출: `web/coding-style.md` "`.vue` 파일만" 문구를 언어별 강제 범위표로 교체, `common/coding-style.md` 배럴 절에 강제 장치 링크, 공장 `core-beliefs.md` R-struct 절 갱신(R-struct-5~7 추가, 파이썬 "아직 대상 아님" 문구 제거)
- 검증: G5 — 시험 스크립트가 범위표와 설정표 (언어, 규칙) 목록을 비교

### Step 9. 전파 [단순 — 사람 승인 후]

- update-all 로 설치 소우주에 전파. 실행 전 사용자 승인.

## 5-bis. 롤백

| 상황 | 되돌리는 법 |
|---|---|
| 한 프로젝트에서 잘못 막음 | 그 프로젝트 `.harnessrc` 에 `HARNESS_STRUCT_LANGS=` (빈 값) — R-struct 엔진 검사 끔. 사유를 그 프로젝트 `docs/audits/` 에 기록 |
| 특정 파일만 잘못 막음 | `--update-baseline` 으로 기준선에 넣음(사람 실행). 기준선이 우회 통로가 되지 않게 추가 사유를 커밋 메시지에 |
| 전파 후 여러 프로젝트에서 문제 | 공장에서 이 계획 커밋을 되돌리고 update-all 재전파. 호환 래퍼가 남아 있어 옛 pre-commit 도 그대로 동작 |

## 6. 의사결정 로그

형식: `날짜: 결정 — 이유 — 틀렸을 때 손해`

- 2026-10-16: 언어 범위를 Tier A(공장 프리셋 6개 언어) + Tier B(흔한 7개 언어)로 — 사용자 요청 "가능한 언어 전부", 프리셋 유무로 자동 켜기 여부가 갈림 — 범위가 커서 완료가 늦어진다
- 2026-10-16: 검사는 소스 텍스트만 읽는다(컴파일러·AST 도구 금지) — 이 PC 에 go·cargo·javac·dart 없음(§2-bis) — 정규식이 놓치는 문법(여러 줄 import 등)은 미검사로 남는다
- 2026-10-16: `check-component-structure.mjs` 를 지우지 않고 호환 래퍼로 남긴다 — 설치된 소우주의 옛 pre-commit 이 이 이름을 부른다 — 파일이 하나 더 남는다
- 2026-10-16: 배럴 존재·전량 재노출은 차단, 깊은 import·언어 무관 규칙은 경고로 시작 — 앞의 둘은 예/아니오 판정, 깊은 import 는 같은 기능 안의 정당한 import 와 정규식으로 가르기 어렵다(planner-lite HIGH 5) — 경고는 무시될 수 있어 깊은 import 우회가 실측 전까지 남는다
- 2026-10-16: Tier B 를 이번 계획에 남긴다(리뷰는 분리 권고) — 사용자가 "가능한 언어 전부"를 명시. 대신 Tier B 는 경고 위주 + 프로젝트가 켜야 동작하게 해 위험을 낮춤 — Tier B 때문에 Tier A 전파가 늦어질 수 있다. 늦어지면 Step 4 를 별도 계획으로 떼어 낸다
- 2026-10-16: R-iface 확장을 목표 G6 으로 정식 포함(리뷰는 분리 또는 G6 권고) — 같은 언어 범위·같은 설정 지식을 쓴다 — 다른 훅까지 건드려 변경 범위가 넓어진다
- 2026-10-16: 엔진 내부 오류(종료 코드 2)는 차단이 아니라 skipped — 지금 구조는 고장과 위반을 구분 못 해 고장 시 모든 커밋이 막힌다(planner-lite CRITICAL 2) — 고장이 조용히 미검사로 넘어갈 수 있어, skipped 를 `gate-events.jsonl` 과 커밋 출력에 반드시 남긴다
- 2026-10-16: planner-lite 리뷰 반영 — CRITICAL 1(필터·신구 혼합) → Step 6 / CRITICAL 2(고장 구분) → 종료 코드 규약·G7 / HIGH 3(기준선 키) → Step 5 / HIGH 4(순서) → Step 0 신설 / HIGH 5(범위·거짓양성) → 판정 수준 / HIGH 6(G1 측정) → 스키마 Step 1 확정·커밋 범위 명시 / MEDIUM 7~11 → G6·스위치 표·G2 커버리지 단언·결정 3칸·롤백 절 / LOW 12~14 → 태그 링크·rule-lang 3분할·G5 스크립트 비교 / 누락 4건(메시지·텔레메트리·성능·경로) → Step 1

- 2026-10-16: 언어를 켜는 스위치를 "프리셋 conf 가 덧붙임" 에서 **Tier A 는 확장자로 자동, Tier B 는 `.harnessrc` `STRUCT_LANGS_EXTRA`** 로 바꾼다 — 프리셋 conf 변수는 설치 시점에만 읽히고 pre-commit 은 `.harnessrc` 만 `source` 한다(`pre-commit.sh:21`). 런타임에 넘길 통로를 새로 만드는 것보다, 그 확장자 파일이 저장소에 있다는 것 자체가 그 언어를 쓴다는 뜻이다 — vue 프로젝트의 보조 파이썬 스크립트도 파이썬 검사를 받는다(배럴 차단은 기능 폴더·패키지 하위에서만 걸리고, 기존 위반은 기준선이 덮는다)
- 2026-10-16: 공장이 깐 파일(`.claude/.factory-manifest.json` 의 항목, `.claude/` · `scripts/hooks/` · `scripts/codex-hooks/`)은 구조 검사에서 뺀다 — Step 0 실측에서 소우주마다 `scripts/` 에 영수증 파일 131개가 한 폴더에 있었다. 이를 넣으면 모든 소우주가 같은 경고를 받고, 원본은 공장 저장소가 검사한다 — 영수증이 없는 옛 설치본에서는 `scripts/` 영수증 파일이 경고로 보인다
- 2026-10-16: 폴더 깊이 경고 임계 = 8 (경로의 `/` 수 > 8) — Step 0 에서 11개 프로젝트의 p90 최대가 7, 최댓값 9(zeroday-frontend 1곳). p90 위로 한 칸 — 깊은 폴더 몇 곳은 경고를 받지 않는다(경고라 손해가 작다)
- 2026-10-16: 언어 무관 규칙은 경고라도 기준선에 넣는다 — 폴더당 파일 5개 초과가 프로젝트마다 흔해(terminal-shipping 51/150 폴더) 기준선 없이 켜면 커밋마다 같은 경고가 나와 무시가 학습된다 — 기준선 파일 줄 수가 늘어난다
- 2026-10-16: Java·Kotlin 의 `import a.b.*` 는 대상과 무관하게 전부 R-struct-4(차단) — 계획 표는 "다른 기능 대상" 이었지만 텍스트만으로 "다른 기능" 을 가를 수 없다. java 프리셋이 지정한 google-java-format 의 Google Java Style 이 와일드카드 import 를 전면 금지하고, ktlint 표준 규칙 `no-wildcard-imports` 도 같다(`java.util.*` 등 허용 목록은 설정표 `allow`) — 와일드카드를 쓰던 프로젝트는 기준선 등록 전까지 막힌다
- 2026-10-16: Svelte 배럴 규칙은 "컴포넌트 폴더를 만들었으면 `index.svelte` 가 있어야 한다" 로 한정한다(낱개 `.svelte` 파일은 허용) — 전역 CLAUDE.md §6 이 폴더 구조를 "3개 이상 기능 또는 100줄 이상" 일 때만 요구한다. Vue 처럼 낱개 파일을 막으면 그 규칙과 어긋난다 — 큰 컴포넌트를 낱개 파일로 두는 경우는 못 잡는다(R-size 가 줄 수로 일부 잡음)

- 2026-10-16: fixture 를 `<언어>/<규칙>/{bad,good}/` 실제 소스 파일 대신 `cases.json` 한 장으로 — 위반 예시를 실제 `.py`·`.js` 로 두면 이 저장소 자신의 게이트(ruff F403 → R-lint, 설치된 R-struct-4, prettier R-fmt)가 그 예시 커밋을 막는다. 시험이 임시 폴더에 펼쳐 돌린다 — 사례를 편집기에서 소스로 열어 볼 수 없다
- 2026-10-16: G1 은 커밋을 나눠 잰다 — ① 엔진 + Tier A 설정·사례 ② Tier B 설정·사례만. 단, 스키마는 Tier B 를 알고 설계했다: Tier B 만 쓰는 필드 3개(`featureRoots` 언어별 덮어쓰기 — ruby, `reexport.allow` — kotlin, module 계열 owner 마지막 마디 비교 — php·csharp)가 ①에 이미 들어 있다. 그래서 0줄은 "스키마 확정 뒤 Tier B 추가에 엔진 수정이 없었다" 는 뜻이지 "Tier B 를 모르고 만든 엔진" 이라는 뜻이 아니다 — 여기 없는 언어를 붙일 때 엔진 수정이 필요할 수 있다

### 설정표 스키마 (Step 1 확정)

`assets/hooks/structure-langs.json` = `{ "version": 1, "featureRoots": [...], "defaultExempt": [...], "langs": { "<언어>": 항목 } }`

| 필드 | 뜻 |
|---|---|
| `tier` | `"A"` 자동(확장자로 켬) · `"B"` `.harnessrc` `STRUCT_LANGS_EXTRA` 로 켬 |
| `featureRoots` | (선택) 이 언어만 쓰는 기능 루트 폴더 이름. 없으면 최상위 `featureRoots` |
| `exts` | 이 언어로 볼 확장자 목록 |
| `exempt` | 이 언어 추가 예외 정규식(경로에 대해) |
| `barrel` | `{ "id", "strategy", "names", "componentPath"?, "hint" }` — `strategy`: `feature-root`(featureRoots 바로 아래 폴더) · `package-child`(부모가 배럴을 가진 폴더) · `component-dir`(componentPath 아래 컴포넌트 폴더) · `sfc-folder`(Vue R-struct-1/2) · `none`. `names` 는 폴더 기준 상대 경로, `{dir}` 은 폴더 이름 |
| `imports` | import 문 정규식 목록, 캡처 그룹 `(?<target>…)` 이 대상 |
| `resolve` | `{ "kind": "path" \| "module", "sep"?, "aliases"? }` — `path` 는 상대 경로를 파일 기준으로 풀고, `module` 은 `sep`(예 `.` `::` `\\`)을 `/` 로 바꾼다. `aliases` 는 `{ "정규식": "치환" }` |
| `deepImport` | `{ "id", "level", "private": [정규식], "skipInBarrel"?, "hint" }` — 풀린 대상이 `private` 중 하나에 맞으면 위반. 정규식의 `(?<owner>…)` 가 가져가는 파일 경로에 들어 있으면 같은 기능이라 통과 |
| `reexport` | `{ "id", "level", "patterns": [정규식], "allow"?, "barrelOnly", "barrelNames"?, "hint" }` |

- 판정 수준 `level`: `block` · `warn`. 규칙 번호: 1~3 Vue(기존) · 4 전량 재노출 · 5 배럴 존재 · 6 깊은 import · 7 언어 무관.
- 정규식은 전부 `m`(줄 단위) 플래그로 돈다. 줄 머리 고정(`^[ \t]*`)으로 문자열·주석 안의 오탐을 줄인다(기존 R-struct-4 원칙).
- 같은 파일이 두 언어에 걸리면(예: `.js` 가 `vue` 와 `js`) 위반 키(`규칙|경로|대상`)로 중복을 지운다.

## 7. 발견·예외

### Step 0 분포 (2026-10-16, `git ls-files` 기준, 공장 영수증 파일 제외)

깊이 = 경로의 `/` 수, 폴더당 = 그 폴더의 소스 파일 수. 값은 p50/p90/최댓값.

| 프로젝트 | 언어(파일 수) | 깊이 | 폴더당 | 5개 초과 폴더 / 전체 |
|---|---|---|---|---|
| zeroday-frontend | js 1396 · vue 431 · python 10 | 4/7/9 | 2/5/326 | 38/495 |
| novel-ab | (영수증 외 소스 없음) | - | - | 0/0 |
| novel-bc | python 1 | 1/1/1 | 1/1/1 | 0/1 |
| rim-kanban | python 76 · svelte 43 · js 28 | 4/5/8 | 2/7/17 | 7/46 |
| jjackkun_bot | python 18 | 0/1/1 | 10/10/10 | 2/2 |
| upbit-ai-trading | python 237 · svelte 142 · js 58 | 4/5/5 | 2/13/57 | 21/74 |
| terminal-shipping | python 726 · svelte 226 · js 203 | 4/6/7 | 2/15/186 | 51/150 |
| kis-trading | python 262 · svelte 251 · js 129 | 4/5/7 | 3/12/54 | 32/118 |
| claude-harness-hermes | python 182 · js 59 | 1/4/5 | 2/15/138 | 6/24 |
| jj-agent-room | js 642 · go 8 · swift 7 · python 4 · java 3 | 3/3/8 | 4/46/154 | 19/46 |
| drh-cloth-shop | js 2 | 3/3/3 | 2/2/2 | 0/1 |

- 11줄 전부 경로 있음. 영수증 제외 전에는 소우주 9곳이 `scripts/` 한 폴더에 파일 131개로 잡혔다 → 위 결정(공장 파일 제외)의 근거.
- 이 PC 의 소우주에 dart·rust·kotlin·csharp·php·ruby 소스는 0개다 → Tier B 와 dart 는 fixture 로만 검증된다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
