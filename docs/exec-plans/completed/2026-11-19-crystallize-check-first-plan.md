# 2026-11-19-crystallize-check-first — 결정화 전에 "기계 검사로 만들 수 있나" 를 먼저 묻는다

## 1. 동기 (Why)

- 헤르메스 결정화(`scripts/hermes-crystallize.py`)는 3회 반복된 실수를 **글(체크리스트)** 로만 굳힌다.
  모델에게 주는 출력 형식이 `## 문제 상황` + `## 규칙 - [ ]` 하나뿐이다(같은 파일 89~147줄).
  "이 실수를 훅·게이트·시험으로 막을 수 있는가" 를 묻는 칸이 프롬프트에도, `hermes-crystallize` 스킬 본문에도 없다.
- 그 결과 공장 `.hermes/skills/` 에 글 규칙이 쌓였다(본 checkout 166개, git 추적 155개).
  이 중에는 **이미 게이트가 막는 것을 글로 다시 적은** 것이 있다:
  - `split-when-file-exceeds-gate.md` — 400/500줄 분리. R-size 가 이미 커밋을 막는다.
- 반대로 기계 검사가 없는 실수는 글로만 남아 매 턴 주입되고, 지켜지는지 아무도 재지 않는다.
- 근거 영상: Lauren Tan "All Code Is Slop (Except Mine)" (AI Engineer Code Summit 2026-11-11) 해설.
  "에이전트를 교정할 때마다 결정적 검사로 옮긴다. 규칙 파일(산문)은 피라미드의 좁은 아래 칸이다."
  발표 팀의 결정적 검사는 7 → 167 로 늘었다(발표자 제시 값, 우리가 확인하지 않음).
  우리 공장에도 같은 방향의 장치(`harness-promote-rule` 스킬)가 있지만 **결정화와 이어져 있지 않다.**

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1. 새 결정화마다 모델이 판정 한 줄을 낸다: `ENFORCE: covered:<R-이름> | checkable:<hook|gate|test> | prose`.
  판정 줄은 스킬 본문에서 떼어 내고 장부에 적는다 —
  검증: 가짜 모델 출력 3종을 먹인 시험이 각각 기대한 분기로 간다. 쓰인 스킬 파일에 `ENFORCE:` 글자가 0회.
- [x] G2. `covered` 면 스킬 파일을 쓰지 않는다. `pattern_count.crystallized = -1`(기존 "다시 안 함" 값)로 두고,
  어느 게이트인지는 장부에 남긴다 —
  검증: `covered:R-size` 출력 뒤 skills 폴더 새 파일 0개 · `crystallized = -1` · 장부 1줄(`verdict=covered`, `gate=R-size`).
- [x] G3. `checkable` 이면 스킬은 지금처럼 쓰고, 장부에 `verdict=checkable`, `kind`, `skill_file` 을 남긴다.
  `list` 명령이 장부에서 후보를 모아 보인다 —
  검증: 후보 2건 장부 → `list` 출력 2줄. 스킬 파일을 진화(`hermes-evolve-skill.py`)로 다시 써도 `list` 결과가 같다.
- [x] G4. "이미 있는 게이트 목록" 은 설치된 pre-commit 첫머리 `#   차단 N — R-…` 줄에서 기계로 뽑는다(손 목록 금지).
  모델이 목록에 없는 이름으로 `covered` 를 내면 `prose` 로 강등한다 —
  검증: 실제 `assets/hooks/pre-commit.sh` 에서 R-size·R-secret·R-cx·R-privacy 를 찾고, R-out·R-cov 는 없다. `covered:R-없는이름` → 스킬 파일 1개 생성, 장부 `verdict=prose`, `note=unknown-gate`.
- [x] G5. 판정 줄이 없거나 형식이 틀리면 `prose` 로 처리한다(결정화가 멈추지 않는다) —
  검증: 판정 줄 없는 가짜 출력 → 스킬 파일 1개, 장부 `verdict=prose`, `note=missing`.
- [x] G6. 에이전트 개인 층(`--agent`)도 같은 분기를 탄다 —
  검증: 개인 층으로 `covered` 1건 → 개인 skills 폴더 새 파일 0개.

## 2-bis. 착수 전 확인한 사실 (2026-11-19)

| 확인한 것 | 결과 |
| --------- | ---- |
| `.hermes/skills/*.md` 수 | 본 checkout 166개 · 이 worktree(git 추적) 155개 |
| 본 checkout `pattern_count` 상태별 | 대기(0) 672 · 결정화(1) 172 · 거부(-1) 250 |
| `core-beliefs.md` 의 `## R-` 제목 | 31개 |
| `scripts/hermes-crystallize.py` 길이 | 446줄 — 400 경고선 위. 새 로직을 이 파일에 넣지 않는다 |
| 결정화 모델 | `claude-haiku-4-5-20251001` (같은 파일 230줄) |
| 결정화 시험 | `tests/hermes-crystallize-naming-test.sh` · `tests/hermes-crystallize-reversed-test.sh` |
| `crystallized` 값을 읽는 곳 | `hermes-cleanup.py:123` (`-1` 만 삭제 보호) · `hermes-increment.py:62` (`1` 아니면 "거부됨") · `hermes_sync_learning.py:164` (`max()` 병합) · `hermes_save_session_storage.py:96,100` · `hermes_dashboard_data.py:129` (둘 다 `= 0` 만 봄) |
| 스킬 파일을 다시 쓰는 곳 | `hermes-evolve-skill.py:50-69` — 모델이 파일 전체를 다시 쓴다. 본문 안 표식은 보존이 보장되지 않는다 |
| 드림 경로 | `hermes-dream.py:348-354` 가 `hermes-crystallize.py` 를 subprocess 로 부른다 → 같은 분기를 탄다. 따로 고칠 것 없음 |
| 기존 "룰 후보" 수집기 | `scripts/hermes_rule_candidates.py` — 완료 계획서 §8 만 읽는다. 이번 장부와 합치지 않는다(§3) |

## 3. 비목표 (Out of Scope)

- **이미 있는 155~166개를 다시 판정하는 일(소급).** 모델 호출이 든다. 별도 단계로 떼고 사용자 승인 뒤에만 한다(§5 Step 5).
- 판정 결과로 훅·게이트를 **자동 생성**하는 일. 후보로 표시만 한다. 실제 승격은 지금처럼 `harness-promote-rule` 을 사람이 부른다.
- 대시보드에 "산문 대 검사" 비율을 그리는 일, `hermes_rule_candidates.py` 와 장부를 합치는 일 — 별도 백로그(Step 6).
- 주입 로직 변경. `covered` 는 파일이 안 생기므로 주입도 안 된다. 그 밖은 그대로.
- `hermes_sync_learning.py` 의 `max()` 병합이 `-1` 을 `0` 에 지게 하는 문제 — 기존 결함이다. §7 에 적고 이번에 고치지 않는다.
- 소우주 전파. 공장에서 끝낸 뒤 따로 정한다.

## 4. 영향 영역

- 코드 수정:
  - `scripts/hermes-crystallize.py` — 판정 지시를 **공용 상수 하나**로 두 프롬프트에 끼우고, `crystallize()` 에서 SKIP 판정 뒤·`scrub()` 앞에 판정 줄을 떼어 분기한다. `generate_skill_content` 의 반환 형식은 바꾸지 않는다(naming 시험 호환). 늘어나는 줄은 20줄 안쪽.
  - `.claude/skills/hermes-crystallize/SKILL.md` — 동작 순서에 판정 단계와 `list` 명령 추가. **스킬 수정이므로 skill-creator 를 먼저 부른다**(CLAUDE.md 「Skill Development」).
- **신규 파일 목록:**
  - `scripts/hermes_enforce_verdict.py` — 게이트 이름 목록 추출 · 모델 출력의 `ENFORCE:` 줄 해석과 강등. 판정 해석 한 가지만 맡는다.
  - `scripts/hermes_enforce_ledger.py` — 판정 장부(`.hermes/enforce-verdicts.jsonl`) 한 줄 쓰기 · 읽기 · `list` CLI. 장부 입출력 한 가지만 맡는다.
  - `tests/hermes-crystallize-enforce-test.sh` — G1~G6 시험. 모델은 부르지 않고 가짜 출력을 먹인다.
- 룰: 새 R 룰 없음. 기존 `harness-promote-rule` 흐름의 입구를 만든다.
- 데이터:
  - DB 값은 새로 만들지 않는다. `covered` 는 기존 `-1` 을 쓴다(삭제 보호·재시도 방지·집계가 이미 맞게 동작).
  - 새 파일 `.hermes/enforce-verdicts.jsonl` — 한 줄 `{date, key, verdict, gate|kind, skill_file, note}`. 스킬 파일처럼 git 으로 추적한다. 커밋 게이트 R-privacy 가 다른 `.hermes/` 파일처럼 본다.
  - 되돌리기: 장부 줄을 지우고 `UPDATE pattern_count SET crystallized=0 WHERE pattern_key=?` 하면 다음 결정화에서 다시 판정된다.
- 외부 의존: 없음. 모델 호출 수는 늘지 않는다(같은 호출에 판정 한 줄이 붙는다).

## 5. 단계 (Steps)

### Step 1. 시험 먼저 (RED) [Impl]

- 입력: G1~G6
- 산출: `tests/hermes-crystallize-enforce-test.sh` — 임시 DB·임시 skills 폴더, `generate_skill_content` 를 가짜로 바꿔 끼운다(naming 시험의 방식을 따른다).
- 검증: 지금 코드에서 실행 → 실패. 실패 줄이 "판정 없음" 때문인지 확인.

### Step 2. 판정 해석·장부 모듈 [Plan→Impl→Review]

- 산출: `hermes_enforce_verdict.py` — `gate_names(path)` · `split_verdict(text, gates) -> (verdict, detail, note, body)`.
  `hermes_enforce_ledger.py` — `append(...)` · `read(...)` · `list` CLI.
- 검증: G4·G5 시험 통과. 두 파일 모두 R-iface(공개 심볼 8 미만)·R-cx 통과.

### Step 3. 결정화에 연결 [Impl]

- 산출: 공용 판정 지시 상수, `crystallize()` 분기(`covered` → `mark_rejected` + 장부 · `checkable` → 쓰기 + 장부 · `prose` → 쓰기 + 장부). `SKILL.md` 갱신(skill-creator 먼저).
  판정 지시에 구분 하나를 넣는다: "게이트가 이미 막는다" 는 `covered`, "게이트에 막힌 뒤 어떻게 하나" 는 `prose`(§7).
- 검증: G1~G3·G6 시험 통과 + 기존 결정화 시험 둘 통과.

### Step 4. 실제 모델 1회 [단순]

- 대기 패턴 하나로 `--crystallize` 를 돌린다(haiku 1회).
- 통과 기준: 모델 출력에 `ENFORCE:` 줄이 있고 `split_verdict` 가 `note=missing` 없이 해석한다. 판정 값(covered/checkable/prose)이 무엇인지는 기준이 아니다 — 기록만 한다.
- 실패하면(줄이 없으면) 지시 문구를 고쳐 한 번 더. 두 번 실패하면 멈추고 보고한다.

### Step 5. 소급 판정 — 47개 (2026-11-19 사용자 승인: "47개만 판정")

- 비용: haiku 최대 166회. 더 싼 판: 본문에 "강제 장치"·"게이트"·"hook"·"훅" 이 들어간 47개만(worktree 155개 중 실측) → 47회.
- 사용자 승인 없이는 돌리지 않는다. 결과로 파일을 지우지 않는다 — `covered` 판정 목록만 보이고, 지울지는 사람이 정한다.

### Step 6. 마무리 [단순]

- 바뀐 부분 시험만 돌리고, 전체 시험은 마지막에 한 번.
- 백로그에 둘을 남긴다: 대시보드 "산문 대 검사" 비율 · `hermes_sync_learning` 의 `-1` 병합 결함.
- 회고(§8) 쓰고 `completed/` 로 옮긴다.

## 6. 의사결정 로그

- 2026-11-19: 판정은 **같은 모델 호출** 안에서 한 줄로 받는다 — 근거: 결정화는 Stop 훅에서 돈다. 호출을 늘리면 세션 끝 비용과 시간이 그대로 는다.
- 2026-11-19: `checkable` 도 스킬은 쓴다 — 근거: 검사가 실제로 생기기 전까지 글이 유일한 방어다.
- 2026-11-19: `covered` 는 파일을 안 쓴다 — 근거: 게이트가 이미 막는 것을 매 턴 글로 주입하면 주입 자리만 차지한다. 장부와 되돌리기 절차(§4)로 틀린 판정을 되살린다.
- 2026-11-19: 게이트 목록은 `core-beliefs.md` 제목에서 뽑고, 목록 밖 이름은 `prose` 로 강등한다 — 근거: 모델이 지어낸 게이트 이름으로 스킬이 영구히 사라지는 것을 막는다.
- 2026-11-19: 새 값 `-2` 대신 기존 `-1` + 장부 — 근거(검토 지적): `-2` 는 `hermes-cleanup.py:123` 에서 삭제 보호를 못 받고, `hermes-increment.py:62` 에서 "거부됨" 으로 찍히고, 동기화 `max()` 에서도 다르게 섞인다. 세 곳을 고치는 것보다 이미 맞게 다루는 `-1` 을 쓰고 이유를 장부에 두는 편이 작다.
- 2026-11-19 (구현 중): 게이트 목록을 `## R-` 제목에서 → 두 문서에 나온 `R-…` 이름 전부로 넓혔다 — 근거: 시험 [f] 가 실제 `core-beliefs.md` 에서 R-secret 을 못 찾았다. 제목은 31개인데 R-secret 은 다른 절 본문(668줄)에만, R-privacy 는 `CLAUDE.md` 에만 있다. 제목만 보면 진짜 게이트의 `covered` 판정이 `unknown-gate` 로 강등된다.
- 2026-11-19 (리뷰 뒤): 게이트 목록을 다시 바꿨다 — 두 문서의 `R-…` 전부 → pre-commit 첫머리 "차단" 줄 — 근거(code-reviewer MEDIUM): 문서 이름을 다 모으면 측정 훅(R-out)·경고 게이트(R-cov)까지 들어간다. 모델이 그 이름으로 `covered` 를 내면 막지도 않는 게이트 때문에 스킬이 영영 안 생긴다. "차단" 줄은 공장·소우주 pre-commit 에 같은 형식으로 있다(공장 · drh-cloth-shop · jj-agent-room 확인).
- 2026-11-19 (리뷰 뒤): 장부 쓰기 실패는 남기고 넘어간다. `covered` 는 장부를 먼저 쓰고 `-1` 을 단다 — 근거(MEDIUM): 장부 예외가 루프를 끊어 남은 키가 처리되지 않았다. 순서가 반대면 이유 없는 `-1` 만 남는다.
- 2026-11-19 (리뷰 뒤): 판정 줄은 마지막(없으면 첫) 비어 있지 않은 줄만 본다. 닫는 펜스를 벗긴다. 게이트 이름은 대소문자·백틱을 무시한다 — 근거(MEDIUM·LOW): 본문 중간 예시 줄이 지워지거나, 펜스 뒤 판정에서 "```" 가 스킬에 남았다.
- 2026-11-19 (구현 중): 실모델 확인을 계획의 1회 대신 2회 했다(`repeated-mistake` · `css-property-missing`) — 근거: 판정 값이 하나로 몰리는지 보려고. haiku 2회.
- 2026-11-19: 표식을 스킬 파일 안이 아니라 장부 파일에 둔다 — 근거(검토 지적): `hermes-evolve-skill.py` 가 모델로 파일 전체를 다시 쓰므로 본문 안 표식은 조용히 사라질 수 있다.

## 7. 발견·예외

- `mask-sensitive-data-before-commit.md` 는 게이트(R-privacy)가 막은 뒤 **통과하는 법**을 적은 스킬이다. "이미 막힘" 과 "막힌 뒤 어떻게 하나" 는 다르다 — 후자는 `prose` 다. 판정 지시에 넣는다(Step 3).
- `hermes_sync_learning.py:164` 는 `max(crystallized, excluded.crystallized)` 로 합친다. 한 컴퓨터의 `-1`(거부)이 다른 컴퓨터의 `0`(대기)에 진다. 거부한 패턴이 다른 컴퓨터에서 다시 결정화될 수 있다. 이번 범위 밖 — 백로그로 보낸다(Step 6).
- 2026-11-19 planner-lite 검토: NEEDS_WORK, 지적 8건. HIGH 3건(`-2` 읽는 곳 · 동기화 · 진화가 표식 지움)은 코드에서 확인 뒤 위 결정으로 반영했다. MEDIUM 5건(드림 경로 · 시험 방식 · 지어낸 게이트 · 되돌리기 · 실모델 통과 기준)은 G4~G6·§4·Step 4 에 반영했다.

- 2026-11-19 code-reviewer: WARNING — MEDIUM 3 · LOW 3. MEDIUM 3 과 LOW 2(대소문자 · 본문 줄 삭제)를 고치고 시험 [f]·[i]·[j] 로 고정했다. LOW "db_path 가 폴더 없는 상대 경로" 는 `hermes_dir or "."` 로 막았다.
- Step 4 실측(2026-11-19, 임시 프로젝트, haiku 2회): 두 번 모두 `ENFORCE:` 줄이 나왔다. 해석도 `note` 없이 됐다. 판정은 둘 다 `checkable:hook` 이었다. 스킬 본문의 `ENFORCE` 는 0회였다.
  두 패턴(반복 실수 감지 · CSS flex 부모)이 정말 훅으로 잡히는지는 별개다 — 모델이 `checkable` 쪽으로 쏠리는지는 소급 판정(Step 5) 표본에서 본다.

- Step 5 실측(2026-11-19, haiku 47회, 일회용 스크립트 · 스킬 파일·DB·장부 무변경):
  - 결과: checkable 34 · covered 6 · prose 5 · 질문 무시 2.
  - **해석기가 너무 엄격했다.** 첫 해석에서 47 중 11(23%)이 형식 때문에 prose 로 떨어졌다 — 판정 뒤 같은 줄 설명 6 · 판정 뒤 설명 문단 3 · 질문 무시 2.
    판정 앞머리만 읽고, 끝·첫 줄에 없으면 본문의 마지막 판정 줄을 찾도록 고쳤다(시험 [i] 3건 추가). 받은 출력을 다시 해석하니 형식 손실 11 → 2.
  - 질문 무시 2건은 모델이 프롬프트 대신 "메시지가 비어 있습니다" · "활성 계획을 이어갈까요?" 로 답했다. `claude -p` 가 저장소 문맥(활성 계획)을 읽는 것으로 보인다 — 추정, 원인 미확인. 결정화도 같은 명령을 쓰지만 이 경우 prose 로 떨어질 뿐 데이터를 잃지 않는다.
  - **checkable 쏠림.** 34/47(72%). 대상이 "게이트·훅" 말이 든 파일이라 높게 나올 수 있다. 그래도 Step 4 의 2/2 와 합치면 모델이 checkable 을 쉽게 고른다. 후보 목록은 사람이 거른다는 전제가 필요하다.
  - covered 6 — 사람이 볼 목록(파일은 지우지 않음):
    - R-privacy: `auto-redact-email-in-docs` · `check-privacy-before-commit` · `redact-sensitive-data-before-commit` · `mask-sensitive-data-before-commit`
    - R-test: `full-test-suite-before-commit` · `test-gate-silent-skip-alerts`
    - 주의: `mask-sensitive-data-before-commit` 는 §7 에서 "막힌 뒤 통과하는 법" 이라 prose 라고 본 것이다. 모델은 지시를 받고도 covered 로 냈다. `test-gate-silent-skip-alerts` 도 R-test 자체의 빈틈을 다룬 것이라 covered 가 의심스럽다. covered 6 중 2는 판정이 틀렸을 수 있다.

- 2026-11-19 covered 처리(사용자 지시 "4개만 지우기" — ⚠️ 2개 제외한 4개):
  - 지움(git rm, 되살리기: `git checkout <이 커밋>^ -- <경로>`): `check-privacy-before-commit` · `redact-sensitive-data-before-commit` · `full-test-suite-before-commit`. 셋 다 주입 0회.
  - **남김: `auto-redact-email-in-docs`** — 지우기 직전 본 checkout DB 를 읽기 전용으로 보니 주입 6 · 도움 5 였다. 내용도 "게이트에 걸리기 전에 예시 도메인을 써라" 는 예방법이라 §7 기준으로는 prose 에 가깝다. 2026-11-19 사용자 결정: 남겨 둔다.
  - 남은 일: 본 checkout `.hermes/state.db` 의 `skill_index` 행 id 82 · 168 · 170 이 지운 파일을 가리킨다. 색인 도구에는 없는 파일의 행을 지우는 경로가 없다. main 에 합친 뒤 `state='tombstoned'` 로 바꿀지(검색이 tombstoned 를 거른다, `hermes-search.py:389`), 지울지 정한다 — DB 를 바꾸는 일이라 승인 뒤에.

## 8. 회고 (완료 시 작성)

- 잘된 것:
  - 시험을 먼저 써서(RED 24/27 실패) 계획의 가정 하나를 바로 깼다 — `core-beliefs.md` 제목만으로는 R-secret 을 못 찾았다.
  - 두 번의 리뷰가 모두 코드로 확인되는 결함을 냈다. 계획 단계(planner-lite): 새 값 `-2` 가 정리·집계·동기화 세 곳에서 다르게 다뤄진다. 구현 단계(code-reviewer): 문서 속 R- 이름 전부를 게이트로 보면 측정 훅으로도 covered 가 된다. 둘 다 시험으로 고정했다.
  - 소급 47회가 모의 시험이 못 잡은 결함을 잡았다. 실제 haiku 는 판정 뒤에 설명을 붙이거나 굵게 썼고, 해석기가 23% 를 버리고 있었다.
  - 지우기 직전 사용 기록을 보고 1개(`auto-redact-email-in-docs`, 도움 5/6)를 살렸다.
- 잘못된 것:
  - 게이트 목록의 출처를 세 번 바꿨다(제목 → 문서 전체 → pre-commit "차단" 줄). 계획 단계에서 "covered 의 근거는 무엇이 실제로 막는가" 를 먼저 물었으면 처음부터 pre-commit 을 봤다.
  - 가짜 모델 출력은 깔끔한 형식만 냈다. 실제 출력 표본(Step 4)을 2건이 아니라 10건쯤 봤으면 해석기 결함을 소급 전에 잡았다.
  - 소급 출력을 끝 200자만 저장해 재해석 때 3건이 잘렸다.
  - 전체 시험을 리뷰 반영 전 코드로 돌렸다. 반영 뒤에는 관련 시험만 다시 돌렸다.
- 다음 룰 후보:
  - 모델 출력을 해석하는 코드는 실제 출력 표본 10건 이상으로 시험을 만든다 — 모의 출력만으로는 꾸밈(굵게·뒤 설명)을 못 잡는다. 사례 1건.
  - checkable 쏠림(72%) — 후보 목록을 사람이 거르는 단계가 없으면 후보가 쌓이기만 한다. `enforce-ratio-dashboard` 백로그에서 다룬다.

## 9. 전파 (2026-11-19)

- 공장 푸시 dd13664..1ce8872. update-all 4곳 성공 4 · 실패 0.
- drh-cloth-shop: 영수증 경로 8개 커밋·푸시(2184c60).
- apt-curtain: 영수증 경로 8개 커밋(9f8f3ac, 브랜치 `design/result-screen-trial`). 원격 저장소가 없어 푸시하지 못했다.
- jj-agent-room: 설치만 했다. 커밋하지 않았다(전파 커밋 금지 목록).
- 공장 DB: `skill_index` id 82 · 168 · 170 을 tombstoned 로 바꿨다(지운 스킬 3개). 바꾸기 전 DB 를 백업했다.
