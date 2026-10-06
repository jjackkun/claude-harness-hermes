# 2026-10-06-mods-factory-install — 패널 모드 세 개를 공장 설치 대상으로

## 1. 동기 (Why)

2026-10-06 에 패널 모드 세 개(`file-explorer`, `hermes-roster-pane`, `tool-calls-pane`)를 만들었다.
세 모드는 `~/.claude/skills/` 에 손으로 넣은 것이라 **이 컴퓨터에만 있다.** 저장소에는 설계 기록
(`docs/design-docs/claude-code-mods.md`)만 있고 코드가 없다.

- 다른 컴퓨터에서 공장을 설치하거나 업데이트해도 모드가 따라오지 않는다.
- 이 컴퓨터의 `~/.claude/` 가 사라지면 코드(시험 포함 약 2,700줄)를 복구할 곳이 없다.

사용자 요청(2026-10-06): "다른 컴퓨터에 설치하거나 업데이트하면 바로 사용할 수 있도록."

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1. 세 모드의 코드가 저장소에 있다 — 검증: `assets/skills/{file-explorer,hermes-roster-pane,tool-calls-pane}/.claude-plugin/plugin.json` 3개가 존재하고 `git ls-files` 에 나온다. → **확인**: 2026-10-06 `git ls-files` 에 세 매니페스트 3개
- [x] G2. 전역 선택 프리셋 하나로 세 모드가 깔린다 — 검증: `CLAUDE_CONFIG_DIR` 를 빈 임시 폴더로 두고 `public-claude.sh --skills-only --set-global "mods"` 를 돌리면 `skills/` 아래에 세 폴더가 생기고 `.factory-manifest.json` 에 기록되며, **기본 5종도 그대로 있다**(새 시험이 단언). → **확인**: 2026-10-06 `tests/mods-install-test.sh` [1] 7개 항목 통과
- [x] G3. 고르지 않은 사람에게는 깔리지 않는다 — 검증: 같은 시험에서 `--set-global ""` 로 돌리면 세 폴더가 없다. 켰다가 끄면 **세 폴더만** 지워지고, 기본 5종과 손으로 넣은 무관한 폴더는 남는다. 인자 없이 다시 돌려도(`update-all.sh:218` 이 하는 방식) 고른 것이 유지된다. → **확인**: 2026-10-06 같은 시험 [2]·[3]·[4] 10개 항목 통과
- [x] G4. 깔린 모드가 엔진 검사를 통과한다 — 검증: `claude` 가 있는 컴퓨터에서 새 시험이 `claude plugin validate` 를 세 폴더에 돌려 종료 코드 0 을 단언한다. `claude` 가 없으면 건너뛰고 건너뛴 사실을 출력한다(그 컴퓨터에서는 G4 가 검증되지 않는다는 뜻이다. 통과로 세지 않는다). → **확인**: 2026-10-06 같은 시험 [5] 3개 항목 통과(이 컴퓨터, Claude Code 2.1.291)
- [x] G5. 헤르메스가 없는 프로젝트에서는 명부 버튼이 띠에 뜨지 않는다 — 검증: `hermes-roster-pane` 의 모드 시험(명부 명령이 실패하면 띠에 자기 버튼을 그리지 않는다). 시험을 먼저 써서 실패하는 것을 본 뒤 구현한다. → **확인**: 2026-10-06 `hermes-roster-pane` 띠 시험 3건(먼저 실패 확인 후 구현), 모드 시험 8건 통과
- [x] G6. 이 컴퓨터의 손으로 넣은 사본이 설치기가 깐 것으로 바뀌고, 모드가 두 벌 로드되지 않는다 — 검증: `claude plugin list` 에 세 모드 이름이 **각각 정확히 한 번** 나오고 모두 `✔ loaded`(이름이 두 번 나오면 실패), `~/.claude/skills/` 에 `*.backup-*` 폴더가 0개. → **확인**: 2026-10-06 세 이름 각 1회 `✔ loaded`(경로 `~/.claude/skills/<이름>`), 백업 폴더 0개. 실제 화면 확인은 사용자 몫으로 남음
- [x] G7. 공장 시험 묶음이 통과한다 — 검증: `bash tests/run-all.sh` 종료 코드 0. → **확인**: 2026-10-06 실행 131 · 통과 131 · 실패 0 (289초)

## 2-bis. 착수 전 확인한 사실 (2026-10-06)

"직접"은 이 세션에서 명령으로 본 것, "조사"는 탐색 에이전트가 보고했고 표시한 줄을 직접 대조한 것이다.

| 확인한 것 | 결과 |
| --------- | ---- |
| 모드가 자동 로드되는 위치 | `~/.claude/skills/<이름>/` 과 프로젝트 `.claude/skills/<이름>/` (엔진 문서). 지금 세 모드가 전자에서 `✔ loaded` (직접) |
| 스킬 설치 방식 | `rm -rf "$dst"; cp -r "$src" "$dst"` 로 폴더를 통째로 복사. `SKILL.md` 를 요구하지 않는다 (`lib/installers.sh:85-98`, 직접) |
| 설치 목록 해시 | 폴더 안 모든 파일(숨김 포함)의 sha256 (`lib/factory_manifest.sh:17-25`, 조사) |
| 엔진이 설치된 모드 폴더에 파일을 써 넣는가 | 아니다. 세 폴더에 내가 쓴 파일만 있고 `types/` 생성물·`tsconfig.json` 이 없다 (직접, 2.1.291 에서 하루 사용 후) |
| 같은 이름의 손으로 넣은 폴더 | 지우지 않고 `<이름>.backup-<날짜시각>` 으로 **같은 `skills/` 폴더 안에** 옮긴 뒤 설치한다 (`lib/installers.sh:67-78`, 직접) |
| 전역 선택 설치 장치 | 코드는 있고 꺼져 있다. `presets/global/` 폴더가 없다 (직접). `public-claude.sh --set-global "<이름들>"` 이 `presets.global.lock` 을 쓰고, `""` 로 비운다 (`public-claude.sh:37-51, 98-119`, 조사) |
| 전역 기본 스킬 | `presets/_common.conf` 의 5종 (직접) |
| 전역 conf 를 읽는 순서 | `_common.conf` 를 먼저 읽고(`public-claude.sh:91`) lock 에 적힌 전역 conf 를 뒤에 읽는다(`:107-118`). 그래서 전역 conf 는 `SKILLS+=(…)` 로 써야 한다. `SKILLS=(…)` 로 쓰면 기본 5종이 목록에서 빠져 정리 단계가 지운다 (직접, 리뷰 지적) |
| 설치 대상 폴더 | `CLAUDE_CONFIG_DIR` 가 있으면 그것, 없으면 `~/.claude` 를 찾는다 (`lib/preset.sh:19-26`, 직접). 시험은 이 변수를 임시 폴더로 두어야 실제 `~/.claude` 를 건드리지 않는다 |
| 전역 설치의 유지 | `update-all.sh:218` 이 `public-claude.sh` 를 인자 없이 다시 돌리고, 그때 lock 을 읽어 고른 것을 유지한다 (직접. 이를 단언하는 시험은 아직 없다) |
| 목록에 없는 스킬의 정리 | 설치 목록에 기록된 것만 지운다. 손으로 넣은 폴더는 지우지 않는다 (`lib/installers.sh:27-45`, 직접) |
| 커밋 게이트 대상 | `.ts/.tsx/.js` 는 R-size(500줄)·R-fmt·R-lint 대상. 제외 정규식에 `vendor`·`assets` 가 없다 (`assets/hooks/pre-commit.sh:30, 46-47`, 직접) |
| 공장에서 R-fmt·R-lint | 건너뛴다. 게이트는 `pnpm exec prettier` 를 쓰는데 공장 저장소에 `package.json` 이 없어 어느 컴퓨터에서든 실패한다 (직접: `ls package.json` 없음, `pre-commit.sh:173`) |
| 모드 파일의 줄 수 | 훅 쪽 최대 95줄(`pane.tsx`), 시험 최대 200줄. `prism.js` 는 55,014바이트 한 줄 → R-size 통과 (직접) |
| R-cx·R-dep·R-test | `.py` 만 본다 (조사) |
| 공장 시험 | `bash tests/run-all.sh`, `tests/*.sh` 127개 (직접). 모든 `*.sh` 에 `bash -n` 을 돌리므로 `tools/build-prism.sh` 도 대상 (조사) |
| 스킬 개수 표기 검사 | `harness.conf` 의 `SKILLS` 길이와 시험 개수만 센다. 새 conf 에 넣으면 스킬 숫자는 그대로, 새 시험 파일은 시험 개수를 바꾼다 (조사) |
| Codex 쪽 | `project-codex.sh:133, 138` 이 같은 `SKILLS` 를 Codex 폴더에도 깐다 (직접). 전역 프리셋은 `public-claude.sh` 만 읽고, 그 파일에 codex 언급이 0건이라 무관 (직접) |
| 모드 시험 현황 | `file-explorer` 77건, `hermes-roster-pane` 6건, `tool-calls-pane` 6건 통과 (직접) |

## 3. 비목표 (Out of Scope)

- 프로젝트마다 까는 방식(`presets/workflow/*.conf`). 프로젝트 `.claude/skills/` 에 사본이 생기면 각 소우주의
  커밋 게이트(R-size·R-lint)와 Codex 복사에 걸린다. 전역 한 곳에만 깐다.
- 커밋 게이트의 제외 정규식 변경. 전역 설치만 하면 소우주 저장소에 모드 파일이 들어가지 않고, 공장에서는
  R-fmt·R-lint 가 건너뛰어지며 R-size 는 통과한다. 게이트 스크립트를 고치면 소우주 11곳에 다시 전파해야 한다.
  공장에 `package.json` 이 생기거나 모드를 프로젝트에 깔기로 하면 그때 별도 계획으로.
- 전역 설치물을 걷어 내는 `uninstall.sh` 경로. 끄는 방법은 `--set-global ""` 로 충분하다.
- 모드의 새 기능(파일 이름 필터, git 스테이징, 폭의 세션 간 저장).
- 엔진 버전을 검사해 설치를 막는 장치. 프리셋 주석과 문서에 요구 버전만 적는다.

## 4. 영향 영역

- 코드(수정):
  - `tests/run-all.sh` — 새 시험 등록
  - `README.md`, `CLAUDE.md`, `presets/workflow/harness.conf` — 시험 개수 표기(R-doc 이 요구하는 만큼)
  - `docs/design-docs/claude-code-mods.md` — 위치와 설치 방법 갱신
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `presets/global/mods.conf` — 전역 선택 프리셋: 패널 모드 세 개를 `SKILLS` 에 올린다
  - `tests/mods-install-test.sh` — 전역 프리셋으로 세 모드가 깔리고 걷히는지, 엔진 검사를 통과하는지 단언
  - `assets/skills/tool-calls-pane/` (8개)
    - `.claude-plugin/plugin.json` — 모드 이름·버전·상태 계약 경로
    - `hooks/hooks.json` — 훅 모듈 경로
    - `hooks/register.tsx` — 명령 등록, 도구 호출 기록, 패널 그리기
    - `hooks/band.tsx` — 프롬프트 위 띠의 여는 버튼
    - `hooks/constants.ts` — 패널 이름·제목·전체 닫기 목록
    - `types/index.d.ts` — 상태 계약(도구 호출 목록)
    - `tests/pane.test.tsx`, `tests/band.test.tsx` — 패널과 띠 시험
  - `assets/skills/hermes-roster-pane/` (9개)
    - `.claude-plugin/plugin.json`, `hooks/hooks.json`, `types/index.d.ts` — 위와 같은 역할
    - `hooks/register.tsx` — 명령 등록, 명부 읽기, 패널 그리기
    - `hooks/band.tsx` — 띠의 여는 버튼
    - `hooks/roster.ts` — 명부 명령의 결과를 패널 줄로 바꾸고 폭을 계산
    - `hooks/constants.ts` — 패널 이름·명부 명령·전체 닫기 목록
    - `tests/pane.test.tsx`, `tests/band.test.tsx` — 패널과 띠 시험
  - `assets/skills/file-explorer/` (47개: 매니페스트 1, 훅 쪽 31, 상태 계약 1, 도구 1, 시험 13)
    - `.claude-plugin/plugin.json`, `hooks/hooks.json`, `types/index.d.ts` — 위와 같은 역할
    - `hooks/register.tsx` — 명령 등록, 패널 열기, 띠 버튼
    - `hooks/pane.tsx` — 패널 그리기와 머리줄 버튼 동작
    - `hooks/inputs.tsx` — 화면 모듈이 보낸 값과 휠 받기
    - `hooks/header.tsx` — 머리 세 줄(탭, 도구, 알림)
    - `hooks/parts.tsx` — 탭에 따른 몸통 배치
    - `hooks/gitview.tsx` — git 탭 몸통
    - `hooks/sidebar.tsx` — 왼쪽 칸과 보기 사이의 세로선을 놓는 조각
    - `hooks/editor.tsx`, `hooks/treeview.tsx`, `hooks/hbar.tsx`, `hooks/divider.tsx` — 화면 모듈(에디터, 트리, 가로 막대, 세로선)
    - `hooks/reducers.ts`, `hooks/scrolling.ts`, `hooks/gitstate.ts` — 상태 계산(일반, 휠·폭, git 탭)
    - `hooks/editing.ts` — 키 하나를 반영한 편집 버퍼
    - `hooks/layout.ts` — 각 영역의 치수 계산
    - `hooks/git.ts` — git 명령과 출력 해석, 줄 색
    - `hooks/highlight.ts`, `hooks/grammars.ts`, `hooks/languages.ts` — 문법 색(조각 변환, vue 문법, 파일 이름→문법)
    - `hooks/tokens.ts`, `hooks/cells.ts`, `hooks/view.ts`, `hooks/tree.ts` — 조각 자르기, 화면 칸, 보이는 창·막대, 트리 펼침
    - `hooks/paint.tsx` — 조각 색과 줄·막대 그리기
    - `hooks/messages.ts`, `hooks/constants.ts` — 화면 모듈이 보낸 값의 모양 확인, 상수
    - `hooks/vendor/prism.js`, `hooks/vendor/prism.d.ts`, `hooks/vendor/PRISM-LICENSE` — Prism.js 1.29.0 묶음, 그 선언, MIT 라이선스 전문(이 3개는 위 "훅 쪽 31"에 포함)
    - `tools/build-prism.sh` — Prism 묶음을 다시 만든다
    - `tests/*.test.tsx` 13개 — cells, color, edit, git, gittab, pane, prism, resize, scroll, stale, tokens, vue, wheel 시험
- 룰: R-plan(이 계획서), R-pipe(코드 리뷰 기록), R-doc(시험 개수 표기), R-declare(위 목록)
- 데이터: 없음
- 외부 의존:
  - Claude Code 2.1.290 이상. 엔진 문서에 "EARLY ACCESS"로 적혀 있어 버전이 오르면 깨질 수 있다.
  - Prism.js 1.29.0 (MIT). 묶음 파일을 저장소에 넣는다. 라이선스 전문을 함께 둔다.
  - `hermes-roster-pane` 은 프로젝트의 `scripts/hermes-agent.py` 를 실행한다(없으면 조용히 넘어간다).

## 5. 단계 (Steps)

### Step 1. 명부 버튼을 헤르메스가 있는 곳에서만 [Impl + 시험]

- 입력: `~/.claude/skills/hermes-roster-pane/`
- 산출: 세션 시작 때 읽은 명부가 실패(`isOk` 가 거짓)이면 띠에 자기 버튼을 그리지 않고 아래 것만 돌려준다.
- 순서: 시험을 먼저 쓴다 → 실패 확인(RED) → 구현 → 통과(GREEN).
- 검증: 명부 명령이 종료 코드 2 를 내면 띠에 `에이전트 명부` 버튼이 없다(G5). 기존 6건 통과.

### Step 2. 모드 폴더를 저장소로 [단순]

- 입력: `~/.claude/skills/` 의 세 폴더
- 산출: `assets/skills/` 아래 세 폴더(§4 목록). 엔진이 쓴 생성물은 없으므로 그대로 복사한다.
- 검증: 복사 전후 파일 목록과 sha256 이 같다. `claude plugin validate`·`claude plugin test` 를 `assets/skills/` 쪽에서 돌려 통과(77+7+6건).

### Step 3. 전역 선택 프리셋 [Plan/Impl/Review]

- 입력: `public-claude.sh` 의 전역 선택 장치(꺼져 있음)
- 산출: `presets/global/mods.conf`. **`SKILLS+=(…)` 로 쓴다**(`=` 로 쓰면 기본 5종이 지워진다). 주석에 요구 엔진 버전, 켜고 끄는 명령, 띠에 버튼이 생긴다는 점을 적는다.
- 시험(`tests/mods-install-test.sh`)의 격리: `CLAUDE_CONFIG_DIR` 를 `mktemp -d` 폴더로 둔다. 시험 앞뒤로 실제 `~/.claude/skills` 의 목록이 같은지 단언한다.
- 검증:
  - 켜면 세 폴더와 기본 5종이 있고 설치 목록에 기록된다(G2).
  - 임시 폴더에 무관한 폴더를 하나 손으로 넣어 둔다 → 비우면 세 폴더만 사라지고 기본 5종과 그 폴더는 남는다(G3).
  - 켠 뒤 인자 없이 다시 돌려도 세 폴더가 남는다(G3, `update-all.sh` 가 도는 방식).
  - `claude` 가 있으면 `claude plugin validate` 세 번(G4).
- `setup.sh` 의 전역 선택 단계(`setup.sh:166-213`, fzf): `presets/global/` 이 생기면 처음으로 켜지는 코드다. 코드를 읽어 두 경우를 확인한다(결과는 §7). 사람이 고르는 화면이라 자동 시험은 두지 않는다.

### Step 4. 시험 등록과 문서 숫자 [단순]

- 입력: `tests/run-all.sh`, R-doc 이 세는 시험 개수
- 산출: 새 시험을 `REGISTERED_TESTS`(`tests/run-all.sh:226`)에 추가(없으면 고아 검사가 실패한다). 시험 개수 표기는 `assets/hooks/doc_counts.py` 를 먼저 돌려 요구하는 자리를 목록으로 받은 뒤 고친다.
- 검증: `bash tests/run-all.sh` 종료 코드 0(G7). 마지막에 한 번만 돌린다.

### Step 5. 이 컴퓨터를 설치기 판으로 전환 [사람 확인 필요]

- 입력: 손으로 넣은 `~/.claude/skills/` 의 세 폴더(Step 2 에서 저장소로 옮긴 것과 같은 내용)
- 산출: 설치기가 깐 세 폴더와 `.factory-manifest.json` 기록.
- 선행 조건: Step 1~4 가 커밋되어 있다(코드가 저장소에 있어야 이 컴퓨터의 사본이 마지막 사본이 아니다).
- 순서:
  1. 손으로 넣은 세 폴더가 저장소 판과 같은지 sha256 으로 확인한다.
  2. 세 폴더를 `skills/` **밖으로 옮긴다**(`mv`, 예: `~/.claude/mods-handplaced-2026-10-06/`). 지우지 않는다.
     옮기는 이유: 그냥 설치하면 설치기가 같은 `skills/` 안에 백업 폴더를 남기고, 그 백업이 모드로 한 번 더 로드될 수 있다.
  3. `public-claude.sh --skills-only --set-global "mods"` 를 돌린다.
  4. G6 을 확인하고, 실제 화면에서 세 패널이 열리는지 사용자가 확인한다.
- 실패 시: 설치기가 깐 세 폴더를 치우고 옮겨 둔 폴더를 `skills/` 로 되돌린다. `--set-global ""` 로 lock 을 비운다.
- 옮겨 둔 폴더의 삭제: 4번 확인이 끝난 뒤 **사용자 승인을 받아** 지운다. 그때까지 둔다.

### Step 6. 설계 문서 갱신과 마무리 [단순]

- 산출: `docs/design-docs/claude-code-mods.md` 의 위치·설치 방법·명부 버튼 조건. 회고(§8) 작성 후 `completed/` 로 이동.
- 검증: 문서에 적은 경로가 실제로 있다.

## 6. 의사결정 로그

- 2026-10-06: 세 모드를 모두 전역 선택 프리셋 하나(`mods`)로 묶는다 — 근거: 프로젝트마다 깔면 소우주 저장소에 `.tsx` 와 축소판 JS 가 들어가 그쪽 게이트에 걸리고(`pre-commit.sh:46-47`), Codex 폴더에도 복사된다(`project-codex.sh:133`). 처음 말한 안(명부 모드만 헤르메스 프리셋에)에서 바꿨다.
- 2026-10-06: 기본 설치가 아니라 선택 설치로 — 근거: 프롬프트 위에 버튼이 생기는 눈에 보이는 변화다. 엔진 기능이 초기 단계라 깨질 수 있다.
- 2026-10-06: 모드를 `assets/skills/` 에 둔다(새 자산 종류를 만들지 않는다) — 근거: 설치기는 폴더를 통째로 복사하고 `SKILL.md` 를 요구하지 않는다. 엔진이 읽는 위치도 `skills/` 다.
- 2026-10-06: 명부 버튼은 명부가 읽히는 프로젝트에서만 — 근거: 전역에 깔면 헤르메스가 없는 프로젝트에서도 로드된다. 눌러도 오류만 나는 버튼은 두지 않는다.
- 2026-10-06: 커밋 게이트는 건드리지 않는다 — 근거: 전역 설치만 하면 소우주에 파일이 안 들어가고, 공장에서는 R-size 통과·R-fmt·R-lint 건너뜀(§2-bis). 필요가 실제로 생기면 고친다.
- 2026-10-06: 엔진 버전이 낮은 컴퓨터를 위한 설치 로그 경고는 넣지 않는다 — 근거: 고른 사람만 받는 프리셋이고, 요구 버전은 프리셋 주석과 설계 문서에 적는다. 버전 문자열을 해석하는 코드를 설치기에 더할 만큼의 필요가 아직 없다.
- 2026-10-06: planner-lite 리뷰(차단 1, 경고 6, 참고 3)를 코드와 대조해 9건을 반영했다 — Step 5 를 삭제 대신 옮기기로, `SKILLS+=` 명시, 시험의 `CLAUDE_CONFIG_DIR` 격리, G2·G3·G6 의 단언 강화, G5 의 실패 먼저 확인, `setup.sh` 확인 항목, 시험 등록 자리. 반영하지 않은 1건은 §7 에 적는다.

- (완료 후 뒤집음, 2026-10-06) **선택 프리셋 → 전역 기본 설치.** 사용자가 "사람이 그걸 매번 해야 해?" 라고 물었다. 요청은 처음부터 "설치하거나 업데이트하면 바로 사용" 이었는데,
  선택 프리셋은 이미 쓰던 컴퓨터에서 명령을 한 번 쳐야 했다. `presets/global/mods.conf` 를 지우고 세 모드를 `presets/_common.conf` 에 넣었다.
  G2(선택 프리셋으로 깔린다)·G3(고르지 않으면 안 깔린다)는 이 결정으로 폐기됐다. 시험은 "고르지 않아도 깔린다" 로 다시 썼다(18개 항목).

## 7. 발견·예외

- (착수 전) 같은 이름의 손으로 넣은 폴더를 설치기가 `skills/` 안에 백업한다. 모드는 그 폴더에 있기만 하면 로드되므로
  백업이 두 번째 모드가 될 수 있다. 이번에는 Step 5 의 순서로 피한다. 설치기의 백업 위치 자체는 별도 후보.
- (착수 전) `setup.sh` 의 전역 선택 단계는 지금까지 한 번도 돌지 않은 코드다. Step 3 에서 처음 켜진다.
- (Step 3) `setup.sh:164-216` 의 전역 선택 단계는 **끄는 길이 없다.** 하나 이상 고르고 Enter 를 치면 고른 것으로 lock 을 덮어쓰지만,
  아무것도 고르지 않으면(Enter·ESC) "변경 없음"으로 건너뛰고 lock 을 그대로 둔다. 착수 전에는 "고르지 않으면 lock 이 빈다"고 가정했는데 틀렸다.
  끄려면 `public-claude.sh --skills-only --set-global ""` 를 직접 쳐야 한다(프리셋 주석에 적어 둠). 마법사에서 끌 수 있게 할지는 별도 후보.
  이 단계는 터미널에서 사람이 고르는 화면(fzf)이라 이 세션에서 실행하지 못했다. 코드만 읽었다.
- (Step 4) 시험 개수 표기는 `README.md`·`presets/workflow/harness.conf`(R-doc 검사 대상)와 `CLAUDE.md`(검사 대상은 아니지만 같은 블록)의 126 → 127.
  `tests/*.sh` 는 128개지만 R-doc 이 세는 값은 등록된 시험 수 127 이다.
- (Step 3) 설치 시험이 결함을 잡는지 일부러 깨뜨려 확인했다: `SKILLS+=` 를 `SKILLS=` 로 바꾸면 1건, 모드 하나를 목록에서 빼면 5건 실패. 되돌리면 21건 통과.
- (Step 5) 전환 결과: 손으로 넣은 세 폴더를 `~/.claude/mods-handplaced-2026-10-06/` 로 옮기고 `public-claude.sh --skills-only --set-global "mods"` 를 돌렸다.
  설치본 해시가 저장소 판과 일치(세 폴더), 링크가 아닌 복사본, 설치 목록에 3개 기록, lock 은 `mods`. 보관 폴더는 사용자 승인 전까지 둔다.
- (Step 5 중 발견) **공장 전체 시험이 실제 `~/.claude` 에 전역 설치를 돌린다.** `tests/update-all-roundtrip-test.sh:22` 는 `HOME` 을 가짜 폴더로 바꿔 격리하지만,
  `public-claude.sh:63` 은 홈을 `getent passwd` 에서 찾으므로 그 격리가 통하지 않는다. `update-all.sh:218` 이 `public-claude.sh` 를 인자 없이 부른다.
  실측: `tests/run-all.sh` 가 16:09:08 에 끝났고 실제 `~/.claude/.factory-manifest.json` 이 16:07:57 에 다시 쓰였다(에이전트 9·규칙 1·스킬 5, 공장 커밋 `0807975`).
  이번 변경이 만든 것이 아니라 원래 있던 동작이다. 손으로 넣은 모드는 설치 목록에 없어 지워지지 않았다(해시 일치).
  고치는 길: 그 시험이 `CLAUDE_CONFIG_DIR` 를 임시 폴더로 두게 한다(이 계획의 `mods-install-test.sh` 가 쓰는 방식). 별도 후보.
- (리뷰) "다른 컴퓨터에 prettier 가 있으면 `prism.js` 가 R-fmt 에 걸린다"는 지적은 반영하지 않았다. 게이트는 `pnpm exec prettier` 로 부르는데
  공장에 `package.json` 이 없어 어느 컴퓨터에서든 건너뛴다(§2-bis). 공장에 `package.json` 이 생기면 다시 본다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
  - 착수 전에 설치기 코드를 읽어 "같은 이름의 손으로 넣은 폴더는 `skills/` 안에 백업된다" 를 미리 알았다. 그래서 Step 5 를 "먼저 밖으로 옮긴다" 로 짰고, 모드가 두 벌 로드되는 일이 없었다(세 이름 각 1회 loaded, 백업 폴더 0개).
  - 설치 시험을 일부러 깨뜨려 봤다(`SKILLS=` 로 바꾸면 1건, 모드 하나를 빼면 5건 실패). 시험이 결함을 잡는다는 것을 확인하고 커밋했다.
  - 전환 전후를 해시로 대조했다(손으로 넣은 사본 = 저장소 판 = 설치본, 세 폴더 모두). 화면은 사용자가 확인했다(2026-10-06, 세 패널 모두 열림).
- 잘못된 것:
  - 계획서의 숫자를 두 번 틀렸다(`file-explorer` 파일 41 → 47개, 시험 12 → 13개). 세지 않고 기억으로 적었다.
  - `setup.sh` 에서 아무것도 안 고르면 lock 이 빈다고 가정했다. 실제로는 변경 없이 건너뛴다. 마법사로는 끌 수 없고 명령을 직접 쳐야 한다.
  - Step 4 에서 공장 전체 시험을 돌릴 때, 그 시험이 실제 `~/.claude` 에 전역 설치를 돌린다는 것을 몰랐다. Step 5 의 사전 점검에서 설치 목록의 수정 시각을 보고서야 알았다.
- 다음 룰 후보:
  - 시험이 대상 폴더를 격리한다고 주장하면, 시험 앞뒤로 실제 폴더의 수정 시각이나 목록을 비교하는 단언을 넣는다. `mods-install-test.sh` 는 넣었고 `update-all-roundtrip-test.sh` 는 없다 → `backlog/update-all-roundtrip-test-leaks-real-home.md`.
- 남은 것(이 계획 밖):
  - `~/.claude/mods-handplaced-2026-10-06/` 보관 폴더 삭제 — 사용자 승인 후.
  - 다른 컴퓨터에서의 설치 — 해 보지 못했다. 그 컴퓨터에서 `public-claude.sh --skills-only --set-global "mods"` 를 돌려 확인한다.
