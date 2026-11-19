# 2026-11-19-review-coverage — 리뷰할 파일을 기계로 고정하고 빠짐·줄 번호를 검사한다

## 1. 동기 (Why)

- 2026-11-19 사용자가 알리바바 open-code-review(OCR) 소개 쇼츠를 건넸다(`NPHW6-SI9CY`). 영상과 README 는 자연어만으로 돌리는 리뷰의 약점 두 가지를 짚는다 — 큰 변경에서 파일 몇 개만 보고 끝냄(incomplete coverage), 지적한 줄 번호가 실제와 어긋남(position drift).
- 우리 `assets/agents/code-reviewer.md` 의 절차는 "`git diff --staged` 와 `git diff` 를 본다" 한 줄뿐이다. 볼 파일 목록을 고정하는 장치도, 몇 개 중 몇 개를 봤는지 세는 장치도, 줄 번호를 확인하는 장치도 없다. untracked 새 파일은 `git diff` 에 나오지 않아 절차상 빠진다.
- OCR 의 위임 모드 스킬(`open-code-review-delegate`)은 Go CLI `ocr` 이 있어야 돈다. 설치는 `npm install -g`(전역)이다. 사용자는 "도구는 깔지 않고 장점만 가져온다" 를 골랐다(2026-11-19 대화).

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 `review_scope.py scope` 가 작업 중 변경(staged·unstaged·untracked)·범위(`--from/--to`)·커밋(`--commit`) 세 방식에서 리뷰할 파일과 뺀 파일(이유 포함)을 낸다 — 검증: `tests/review-coverage-test.sh` 가 임시 git 저장소에서 세 방식 결과를 단언
- [x] G2 `rule` 이 파일마다 검사 기준을 붙이고 같은 기준끼리 묶는다. 프로젝트 `.claude/review-rules.json`(`{"rules":[{"path","rule","merge_system_rule"?}]}`) 이 내장 기준을 바꾸거나 더한다. 깨진 JSON·`path`/`rule` 없는 항목은 종료 2 와 원인 줄로 멈춘다 — 검증: 같은 시험에서 `.py`→python, `.svelte`→default, 덮어쓰기·합치기·깨진 파일 단언
- [x] G3 `check` 가 리뷰 장부(JSON)를 받아 빠진 파일·이유 없는 건너뜀·범위 밖 지적·파일 길이를 넘는 줄 번호를 실패(종료 1)로, 바뀐 줄 밖 지적을 경고로 낸다. 요약에 `total/reviewed/skipped/coverage_rate` 를 찍는다 — 검증: 같은 시험에서 각 경우 종료 코드·출력 단언
- [x] G4 `code-reviewer` 에이전트가 스크립트가 있으면 scope → rule → 파일별 리뷰 → check 순서를 따르고, 없으면 기존 절차로 돌며 그 사실을 보고한다 — 검증: 시험이 에이전트 본문의 스크립트 경로(설치 뒤 `.claude/skills/review-coverage/scripts/review_scope.py`)·폴백 문구를 센다. 훅은 에이전트 이름만 읽고 본문은 읽지 않는다(grep 확인, 2026-11-19)
- [x] G5 workflow 프리셋에 스킬이 등록돼 update-all 로 소우주에 깔린다 — 검증: `tests/preset-integrity-test.sh` PASS, 전파 뒤 소우주에 `.claude/skills/review-coverage/scripts/review_scope.py` 존재
- [x] G6 이 저장소의 실제 커밋에 돌려 결과가 맞는다 — 검증: `scope --commit 0e155a5` 의 리뷰할 파일이 4개(`git show --name-status 0e155a5` 와 같은 4개 경로)

## 2-bis. 착수 전 확인한 사실 (2026-11-19)

| 확인한 것 | 결과 |
| --------- | ---- |
| OCR 저장소 | alibaba/open-code-review @ 817ed02, Apache-2.0, 별 54,239 |
| OCR 위임 스킬 | `skills/open-code-review-delegate/SKILL.md` 218줄, blob 78bb26d1 — 7단계, 빠짐률 필수 |
| OCR 내장 규칙 | `internal/config/rules/rule_docs/*.md` 68개 · 484KB, 경로 대응표 `system_rules.json` 72줄 |
| OCR 제외 디렉터리 | `.idea/ .vscode/ .svn/ .git/ vendor/ node_modules/ target/ .happypack/ .cachefile/ _packages/ rpm/` (`internal/diff/git.go`) |
| 우리 code-reviewer | 58줄, tools Read·Grep·Glob·Bash (Write 없음 → 장부는 표준입력으로 넘긴다) |
| `.harness/` | `.gitignore` 42행에 있음 |
| 줄 번호 기준 | 범위·커밋 방식은 target 커밋의 파일, 작업 중 방식은 작업 트리 파일. untracked 는 전 줄이 바뀐 줄. 삭제·바이너리는 리뷰 대상이 아니라 장부에 없어도 된다. 이름 변경은 새 경로로 센다 |
| 0e155a5 | M 4개 (tool-calls-pane·hermes-roster-pane 의 band.tsx·constants.ts) |

## 3. 비목표 (Out of Scope)

- `ocr` CLI 설치·호출. 전역 설치이고, 사용자가 "장점만" 을 골랐다.
- 묶음마다 하위 에이전트를 따로 띄우는 병렬 리뷰. 모델 호출 수가 늘어난다(decision-ledger 5번) — 필요해지면 별도 계획.
- OCR 의 위치 재조정(relocation)·지적 재검토(reflection) 모듈. 모델을 부르는 단계다. 우리는 줄 번호를 기계로 확인만 한다.
- 규칙 문서 번역. 영어 원문 그대로 둔다(내용을 바꾸면 상류 추적이 어려워진다).
- Codex 쪽(`lib/codex_md_gen.sh` 의 code-reviewer → `codex review` 치환).

## 4. 영향 영역

- **신규 파일 목록**:
  - `assets/skills/review-coverage/SKILL.md` — 리뷰 범위 고정 → 기준 → 파일별 리뷰 → 장부 검사 절차
  - `assets/skills/review-coverage/NOTICE.md` — OCR(Apache-2.0) 출처·바꾼 점
  - `assets/skills/review-coverage/scripts/review_scope.py` — CLI 진입점(scope·rule·check 나눠 보내기)
  - `assets/skills/review-coverage/scripts/scope_git.py` — git 에서 바뀐 파일·바뀐 줄·뺄 파일을 모은다
  - `assets/skills/review-coverage/scripts/scope_rules.py` — 경로 패턴으로 검사 기준을 고르고 묶는다
  - `assets/skills/review-coverage/scripts/scope_check.py` — 리뷰 장부의 빠짐·줄 번호를 검사한다
  - `assets/skills/review-coverage/scripts/scope_glob.py` — `**`·`{a,b}` 경로 패턴 맞추기(제외·규칙이 함께 쓴다)
  - `assets/skills/review-coverage/references/rules/*.md` — OCR 내장 규칙 중 우리 스택에 맞는 것(원문)
  - `assets/skills/review-coverage/references/rules/path_rule_map.json` — 경로 패턴 → 규칙 문서 대응표
  - `tests/review-coverage-test.sh` — 임시 git 저장소로 G1~G4 정적 시험(모델 0·네트워크 0)
- 수정: `assets/agents/code-reviewer.md` (절차) · `presets/workflow/harness.conf` (등록) · `tests/run-all.sh` · `assets/upstream.json` (장부) · `README.md`
- 외부 의존: 없음(python3 표준 라이브러리 + git)

## 5. 단계 (Steps)

1. 스크립트 3개 + 진입점 작성, 규칙 문서 복사
2. 정적 시험 작성·통과
3. SKILL.md·NOTICE·에이전트 절차 수정
4. 이 저장소 실제 커밋으로 실측(G6)
5. 프리셋·장부·README 등록 → 커밋 → main ff → update-all 전파

## 6. 의사결정 로그

- 2026-11-19: `ocr` 대신 python 표준 라이브러리 스크립트로 같은 일을 한다 — 근거: 전역 설치 금지 규칙, 사용자 선택.
- 2026-11-19: 규칙 문서는 68개 중 우리 프로젝트 언어(python·ts/js·java·kotlin·go·rust·swift)와 설정 파일(json·yaml·package.json·pom.xml·build.gradle·properties·GitHub workflow)에 해당하는 것만 가져온다 — 근거: 484KB 를 10여 곳에 복사하면 대부분 쓰이지 않는다. 대응표에 없는 확장자는 default 로 간다.
- 2026-11-19: 잠금 파일(`*-lock.json`·`*.lock`·`pnpm-lock.yaml`)과 압축본(`*.min.js`·`*.min.css`)도 뺀다 — 근거: 사람이 쓰지 않는 생성물이다. OCR 은 빼지 않지만 우리 리뷰에서 읽을 이유가 없다.
- 2026-11-19: 장부는 파일이 아니라 표준입력(`check -`)으로도 받는다 — 근거: code-reviewer 에 Write 도구가 없다.

## 7. 발견·예외

- 2026-11-19 code-reviewer 가 **이 스킬의 새 절차로** 이 변경을 리뷰했다(첫 실전). 판정 BLOCK — HIGH 3 · MEDIUM 3 · LOW 3. 9건 모두 고치고 회귀 시험 7개를 더했다(39 → 46).
  - HIGH: 하위 폴더에서 부르면 untracked 가 빠지고 경로가 틀어짐 → `rev-parse --show-toplevel` 로 고정 · 중첩 저장소(`.claude/worktrees/`)에서 `IsADirectoryError` 로 전체 중단 → "일반 파일이 아님" 으로 뺌 · `--exclude '*.{py,md}'` 가 쉼표에서 잘려 `re.error` 추적 → 중괄호 밖 쉼표만 나눔, 짝 없는 중괄호는 글자로
  - MEDIUM: 장부 형식 오류가 추적(종료 1)으로 새어 "장부 불완전" 과 구분 안 됨 → 오류 줄로 · 파일 길이를 모르면 조용히 통과 → 경고 · `coverage_rate` 가 건너뜀까지 셈(리뷰어 자신이 5/16 건너뛰고 1.0 을 받음) → 읽은 비율로 바꾸고 건너뛴 파일 이름을 요약에 남김
  - LOW: numstat 이름 변경 파싱(`{sub => }/f`) → `-z` 형식 · 이름 변경 파일의 바뀐 줄을 새 경로로만 계산 → 옛 경로도 넘김 · `gen/out/` 처럼 끝이 `/` 인 패턴 → 그 폴더 아래 전부 · git 출력 복호화 → utf-8 replace
- 리뷰 결과가 보여 준 것: 장부 검사는 "다 봤다" 를 강제하지만 "제대로 봤다" 는 강제하지 못한다. 이유 칸이 비지 않으면 통과한다. 그래서 비율과 건너뛴 이름을 보고에 남기는 쪽을 골랐다.
- R-cx(복잡도 한도 11) 3건(`_run` 15 · `check_ledger` 14 · `_compile` 13)을 커밋 전에 잡아 나눴다.
- G6 실측: `scope --commit 0e155a5` → 리뷰할 파일 4개, `git show --name-status 0e155a5` 의 M 4개와 같은 경로.

- 되돌리기: 공장에서 이 작업 커밋을 revert 하고 update-all 을 다시 돌린다. 설치기가 프리셋에서 빠진 스킬 폴더를 회수하는지는 확인하지 않았다 — 남으면 소우주의 `.claude/skills/review-coverage/` 만 지우면 된다(다른 파일이 그 폴더를 부르지 않는다. code-reviewer 는 폴더가 없으면 폴백한다).
- 전파: 사용자가 2026-11-19 "적용해서 전파하면" 으로 지시했다. 대상은 `.installed-projects` 레지스트리(제외 목록은 메모리 기준)이고, 커밋 금지 목록(jj-agent-room · Nbbang-Run · 제로데이)은 설치만 한다.
- 완료 판정: `tests/review-coverage-test.sh` 와 `tests/preset-integrity-test.sh` PASS, G6 실측값 기록, 전파 영수증 경로 기록.

- 전파 2026-11-19: update-all 성공 4 / 실패 0 (jj-agent-room · drh-cloth-shop · claude-harness-hermes · apt-curtain). 4곳 모두 `.claude/skills/review-coverage/scripts/review_scope.py` 존재, code-reviewer 에 새 절차. drh-cloth-shop 에서 `scope --commit HEAD` 31개, apt-curtain 에서 `rule --no-text` 실행 확인.
  - 커밋: drh-cloth-shop 1982ad2 · apt-curtain e04f750 (브랜치 design/result-screen-trial) · 공장 자기 설치 3c2424d. jj-agent-room 은 커밋 금지 목록이라 설치만.
  - 푸시: 공장 푸시가 자동 모드 검사에 막혔다. 소우주 푸시도 하지 않았다 — 사용자가 직접 한다.

## 8. 회고

- 잘된 것: 새 절차로 이 변경 자체를 리뷰시킨 것이 가장 값졌다. 정적 시험 39개가 다 통과한 뒤에도 실사용 조건(하위 폴더 실행, 저장소 안 worktree 폴더, 중괄호 패턴)에서 HIGH 3건이 나왔다.
- 잘못된 것: 첫 판 `coverage_rate` 가 건너뜀을 덮었다 — 리뷰어 자신이 5/16 을 건너뛰고 1.0 을 받았다. 숫자가 무엇을 세는지 먼저 정하지 않았다.
- 다음 룰 후보: 없음. 다만 "장부 이유 칸" 의 질(‘안 읽음’ 같은 이유)은 기계로 못 막는다 — 반복되면 code-reviewer 지시를 고친다.
