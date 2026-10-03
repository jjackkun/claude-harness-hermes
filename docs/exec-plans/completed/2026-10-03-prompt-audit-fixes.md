# 2026-10-03-prompt-audit-fixes — 소우주 감사가 찾은 공장 쪽 낡은·충돌 지시 1~6 고치기

근거: `docs/exec-plans/backlog/prompt-audit-terminal-shipping-findings.md` (terminal-shipping 09-29 prompt-audit).
7(매 턴 주입 줄이기)은 행동 가설이라 terminal-shipping 측정이 먼저, 8(`/impeccable` 대 프로젝트 스킬)은 사람 결정이 먼저 — 이번 범위 밖.

## 1. 동기 (Why)

설치된 규칙·훅·DS 블록이 서로, 또는 소우주 실물과 어긋난다. 모델은 어느 쪽이 지금 규칙인지 가릴 수 없다.
6번은 실제 결함이다 — 이 세션의 주입에도 `[헤르메스 규칙 — SKILL.md]` 이름표가 찍혔다(폴더 이름이 아니라).

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 (#6) — 스킬 머리말 `description: |`·`>`(블록 스칼라)를 펼쳐 한 줄로 주입하고, 이름이 `SKILL.md` 면 폴더 이름을 이름표로 쓴다. 검증: 블록 스칼라 픽스처 → 주입 글이 `|` 가 아니라 본문 · 이름표 = 폴더 이름. 고치기 전 코드로 빨강.
- [x] 목표 2 (#2) — python 규칙의 black·isort 를 ruff(`ruff format` · `ruff check --fix`)로. 검증: `grep -c 'black\|isort' assets/rules/python/*.md` = 0.
- [x] 목표 3 (#1) — 공장 규칙 파일의 `R6` 을 소우주 R 번호와 겹치지 않는 이름 `ui-skill-first` 로(§6). 검증: `git grep -n '\bR6\b' -- assets` 에서 규칙 번호로 쓰는 곳 0 (promote-rule 의 "예: R1~R6" 은 예시라 둔다).
- [x] 목표 4 (#3) — web coding-style 의 Vue 구조 규칙에 적용 범위(`.vue` 파일이 있는 프로젝트만, 게이트도 `.vue` 만 본다)를 적는다. 검증: 문구 존재 + `check-component-structure.mjs` 가 `.vue` 만 본다는 사실과 일치.
- [x] 목표 5 (#4) — 소우주 CLAUDE.md 에 들어가는 `docs/hermes-{cron,loop,sync}-guide.md` 링크를 공장 저장소 주소로. 검증: 설치 템플릿에 공장 주소 3곳 · 상대 링크 0.
- [x] 목표 6 (#5) — DS COUNTS 칸이 무엇을 세는지(harness 프리셋이 까는 스킬·에이전트, 공장 시험) 글에 적는다. 검증: `sync-doc-counts.sh` 대조 통과 · 렌더 문구에 기준 표기.

## 2-bis. 착수 전 확인한 사실 (2026-10-03)

| 확인한 것 | 결과 |
| --------- | ---- |
| #6 주입 이름 | `hermes_skill_render.inject_text(name, …)` — `name` 을 그대로 씀. 호출 2곳(`hermes-search.py:290,299`) |
| #6 머리말 파서 | `_DESC = ^description:\s*(.+)$` — `\|` 한 글자만 잡힌다 |
| #2 | `coding-style.md:36-37` black·isort, `hooks.md:14` black/ruff |
| #1 | `rules.md:33` `## R6.` · `roles/designer.md:32` "(R6)" · 시험 `hermes-role-templates-test.sh:149` 가 그 문구를 단언 |
| #3 | 게이트 `check-component-structure.mjs:51` 은 `ext === '.vue'` 만 검사 |
| #4 | `presets/workflow/hermes.conf:496,500,539,548,555` |
| #5 | `doc_counts.py` 의 스킬·에이전트 = `harness.conf` 의 SKILLS·AGENTS 배열, 시험 = 공장 `tests/` |

## 3. 비목표 (Out of Scope)

- #7 매 턴 주입 줄이기, #8 프론트 첫 스킬 결정.
- 소우주 전파(update-all) — 공장 커밋 뒤 따로.

## 4. 영향 영역

- 코드: `scripts/hermes_skill_render.py`, `assets/hooks/doc_counts.py`
- 문서·규칙: `assets/rules/python/{coding-style,hooks}.md`, 공장 `CLAUDE.md`(관리 블록 사본 3줄 · COUNTS), `README.md`·`presets/workflow/harness.conf`(COUNTS), `scripts/hooks/doc_counts.py`(배포 사본), `tests/hermes-role-templates-test.sh:149`(R6 문구 단언), `tests/run-all.sh`(등록), `assets/rules/harness/rules.md`, `assets/templates/agent/roles/designer.md`, `assets/rules/web/coding-style.md`, `presets/workflow/hermes.conf`
- **신규 파일 목록**:
  - `tests/hermes-skill-render-test.sh` — 스킬 주입 한 줄(블록 스칼라 펼침 · 폴더 이름표)만 시험한다
- 룰: 없음 · 데이터: 없음

## 5. 단계 (Steps)

### Step 1. #6 블록 스칼라·이름표 [Impl — 시험 먼저]
### Step 2. #2·#1·#3 규칙 문구 [단순]
### Step 3. #4 링크 · #5 수치 기준 [단순]
### Step 4. 묶음 시험 · 커밋 · 백로그 문서 갱신

## 6. 의사결정 로그

- 2026-10-03: #1 이름은 `H-ui-skill` 이 아니라 `ui-skill-first` — `H-01~H-11` 이 이미 헤르메스 결정 번호로 쓰인다(planner-lite 지적).
- 2026-10-03: #4 링크는 설치 복사가 아니라 공장 저장소 주소(`github.com/jjackkun/claude-harness-hermes`)로 — 가이드 셋은 공장 운영 문서라 소우주에 복사하면 낡은 사본이 생긴다. 바꾼 곳은 CLAUDE.md 관리 블록 템플릿 3줄(`hermes.conf:539,548,555`)과 공장 CLAUDE.md 의 같은 3줄. `:496`(주석)·`:500`(설치 로그)·`README.md:532`(공장 문서, 상대 링크가 맞다)는 둔다.
- 2026-10-03: #5 는 렌더 문구에 기준을 박는다("harness 프리셋이 까는 … · 공장 테스트 …") — 소우주 CLAUDE.md 에도 그대로 실려 설치마다 덮이는 것이 의도(수치의 출처가 공장이므로).
- 2026-10-03: #6 블록 스칼라는 라이브러리 없이 직접 편다 — `\|`·`>`·`\|-`·`>-`·`\|+` 모두 다음 들여쓴 줄을 공백으로 이어 한 줄로(주입은 한 줄이라 literal/folded 를 가르지 않는다). 이름표 대체는 `inject_text` 안에서 — 호출 2곳 모두 덮는다.

## 7. 발견·예외

- 공장 `rules.md` 의 R1~R5·R7 도 소우주 `core-beliefs.md` 번호와 잠재적으로 겹친다(이번에 실제 충돌로 보고된 것은 R6 뿐). 범위 밖 — 백로그 문서 #1 칸에 적어 둔다.
- 실측(terminal-shipping `docs-first` 스킬): 수정 전 `[헤르메스 규칙 — SKILL.md] |` → 수정 후 `[헤르메스 규칙 — docs-first] 기획·설계·기능·화면에 대해 …`.
- 시험: `hermes-skill-render-test` 6/6(수정 전 3 빨강) · skill-inject 18 · skill-extends 9 · keywords 20 · mesh-consume 14 · role-templates 61 · doc-counts-gate 19 · test_doc_counts 9.

## 8. 회고 (완료 시 작성)

- 잘된 것: #6 은 이 세션의 실제 주입 이름표가 고친 직후 폴더 이름으로 바뀐 것으로도 확인됐다.
- 잘못된 것: 계획서 첫 판에 사본 파일(`scripts/hooks/doc_counts.py`)·시험 등록·문구 단언 시험을 빠뜨렸다 — planner-lite 와 `test_doc_counts` 가 잡았다.
- 다음 룰 후보: 없음(사본 대조는 이미 `test_배포_사본이_원본과_같다` 가 강제한다).

## 후속 (2026-10-03)

- `7f42d01` — code-reviewer LOW 1·2: 블록 표지만 있는 값만 블록으로 읽고(`>3 steps` 는 일반 글), 블록 본문의 따옴표는 벗기지 않는다. `hermes-skill-render-test` 8/8.
