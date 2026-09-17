# 2026-09-17-design-coverage-gaps — 설계에 확정됐으나 계획·코드에 없던 동작 채우기

> 작성일: 2026-09-17
> 목적: 설계 문서 9개의 기계 동작 문장 ≈85건을 코드와 전수 대조해 나온 누락 15건 + "계획 ✔인데 코드 0건" 1건을 심각도 순으로 채운다.
> 선행: 계획 `2026-09-17-summon-soul-injection`(같은 유형의 첫 발견) · 계획 4(agent-identity) · 계획 3(work-journal).
> 대조 기록: 서브에이전트 전수 대조(2026-09-17) — 핵심 0건 주장 4개는 본 세션이 grep 으로 재확인.

## 1. 동기 (Why)

- 설계 문서는 리뷰를 거쳐 "확정" 이 붙었지만, 계획서로 옮길 때 목표 목록이 보안·토큰 쪽으로 좁혀졌고, 옮겨지지 않은 문장을 잡는 장치가 없다. SOUL 주입도 이 경로로 빠졌고, 같은 대조에서 15건이 더 나왔다.
- 그중 하나는 **보안**이다: 이력 자유 글 칸(`intent`·`lesson`·`decision`)이 마스킹 없이 원문으로 저장된다(`work-journal.md:170,186` "기록 전 마스킹"). 오늘 올린 R-leak 과 정면 충돌.
- 하나는 **계획 체크가 거짓**이다: 계획 4 목표 11 의 `claimed: blocked + evidence.reason = rule:<이름>` 은 ✔ 인데 코드·테스트 0건.

## 2. 목표 (What — 검증 가능한 형태)

> 검증 명령: 각 목표에 적힌 테스트 · `bash tests/run-all.sh`(회귀).

- [x] 목표 1 — **자유 글 마스킹**: `hermes_journal.emit` 이 `intent`·`lesson`·`decision` 을 저장 **전** `hermes_redact.redact(text, project)` 로 치환한다(.env 값 대조 + 형태 규칙). 검증: `bash tests/hermes-journal-test.sh` — `.env` 의 값·GitHub PAT 꼴·전화번호를 담은 intent 를 emit → DB 행에 원문 0건, `[REDACTED:` ≥1.
- [x] 목표 2 — **`agent.created` 이벤트**: `hire` 가 명부·폴더 다음에 `agent.created`(actor=사람, evidence 없음, intent=`hire <이름> <분야/직급/조직>`)를 기록한다. `KINDS` 에 추가하고 DB CHECK 는 `KINDS` 에서 생성한다. 검증: `bash tests/hermes-roster-test.sh` — hire 뒤 `journal_events` 에 kind=`agent.created` 1행, actor 가 `human:` 접두.
- [x] 목표 3 — **기존 DB 마이그레이션**: 옛 CHECK(`agent.created` 없음)를 가진 `state.db` 에서 `ensure_schema` 가 한 트랜잭션으로 새 표에 복사→교체하고 인덱스·추가전용 트리거를 다시 만든다. 검증: `bash tests/hermes-journal-test.sh` — 옛 SQL 로 만든 DB 에 3행 넣고 ensure_schema → 행 3 보존·`agent.created` INSERT 성공·UPDATE/DELETE 여전히 거부·`journal_events_disabled_*` 없음.
- [x] 목표 4 — **규칙 위반 차단 기록**(계획 4 목표 11 의 거짓 체크 정정): `hermes_handoff.resolve(how="blocked", reason="rule:<이름>")` 가 `task.finished` + `claimed=blocked` + `evidence.reason=rule:<이름>` 을 남긴다. `reason` 이 `rule:` 꼴이 아니면 거부. 검증: `bash tests/hermes-handoff-test.sh` — 정상 1 · 꼴 아님 거부 1.
- [x] 목표 5 — **봉투 `kind`·`from`·`to`·`return_to`** (`handoff-contract.md:28-35`): `open_handoff` 가 `kind ∈ {지시, 협업, 요청}`(기본 `지시`)·`return_to`(기본 요청자)를 받아 `task.handoff` evidence/intent 에 남기고, `resolve(how="declined")` 는 `kind=지시` 봉투를 **거부**한다(지시는 거절 불가, 규칙 위반이면 목표 4 의 blocked). 검증: 테스트 — 지시 declined → HandoffError, 협업 declined → 기록.
- [x] 목표 6 — **`constraints` 보존**: 검증만 하고 버리던 `constraints` 를 `task.handoff` 의 `decision` 칸(자유 글, 목표 1 마스킹 적용)에 `constraints=<…>` 로 남긴다. 검증: 테스트 — open 뒤 행의 decision 에 constraints 문자열.
- [x] 목표 7 — **세션 안 `summons` 쓰기 차단**(`identity.md:206`): PreToolUse 훅이 Bash 명령줄에 `sqlite3 … state.db` + `summons` 에 대한 INSERT/UPDATE/DELETE 가 함께 있으면 차단한다. 러너 스크립트 실행은 허용(기존 허용 목록). 검증: `bash tests/hermes-summon-guard-test.sh` — 차단 2 · 통과(SELECT) 1.
- [x] 목표 8 — 나머지 9건은 **backlog 로** 옮긴다(`design-gaps-tier2.md`): 주입 순서·철회 재학습 표시·출처 불명 표시·만료 원인·2차 되묻기 승격·우선순위·매칭 근거·담당 없음 기억·무인 이월. 검증: 파일 존재, 9건 각 설계 파일:줄 포함.
- [x] 목표 9 — **재발 방지 후보**: 설계 "확정" 문장 ↔ 계획 목표 대조 게이트(`R-design-cover`)를 §8 룰 후보로만 제안한다(이 계획에서 구현하지 않음). 검증: §8 에 문장.

## 3. 비목표 (Out of Scope)

- 목표 8 의 9건 구현. 원격 암호화(계획 3 몫). `hermes-search.py` 정렬 변경.

## 4. 영향 영역

- 수정: `scripts/hermes_journal.py`(마스킹), `scripts/hermes_journal_schema.py`(KINDS·CHECK 생성·마이그레이션), `scripts/hermes-agent.py`(agent.created), `scripts/hermes_handoff.py`(blocked·kind·return_to·constraints), `assets/hooks/claude-pretooluse-summon-guard.sh`(DB 쓰기 차단), `tests/hermes-journal-test.sh`, `tests/hermes-roster-test.sh`, `tests/hermes-handoff-test.sh`, `tests/hermes-summon-guard-test.sh`, `assets/skills/hermes-agent/SKILL.md`(blocked·kind 안내).
- 신규: `scripts/hermes_journal_migrate.py`(마이그레이션 단일 책임), `scripts/hermes_handoff_kind.py`(봉투 kind 를 조직 관계에서 판정하는 것만 — 지시·협업·요청·미상), `docs/exec-plans/backlog/design-gaps-tier2.md`.
- 전파: 스크립트·훅·스킬은 `assets`/`scripts` 자산 → `update-all` 필요.

## 5. 단계 (Steps)

### Step 1. 마스킹 + agent.created + 마이그레이션 [Impl] — 목표 1·2·3
### Step 2. 봉투 계약 보강 [Impl] — 목표 4·5·6
### Step 3. summons 쓰기 가드 [Impl] — 목표 7
### Step 4. backlog·회고·전파 [단순] — 목표 8·9, `completed/` 이동

각 Step: 테스트 먼저 빨강 → 구현 → 초록, 전체 스위트 0 실패, 사용자 지시로 커밋.

## 6. 의사결정 로그

- 2026-09-17: **DB CHECK 는 KINDS 튜플에서 생성한다.** 근거: 같은 목록이 두 곳(튜플·SQL 문자열)에 있어 갈라졌다 — 설계는 `agent.created` 를 요구하는데 둘 다 없었다. 손해: 기존 DB 는 옛 CHECK 를 갖고 있어 마이그레이션 없이는 새 kind INSERT 가 실패한다 → 목표 3.
- 2026-09-17: **마이그레이션은 복사→교체를 한 트랜잭션으로.** 근거: SQLite 는 CHECK 를 ALTER 로 못 바꾼다; RENAME 방식은 중간에 죽으면 `journal_events` 가 없어져 `schema_disabled` 판정(rollback 사본 이름 규칙)과 어긋난다. 트랜잭션이면 중간 실패 시 원상. 손해: 큰 이력은 복사 시간이 든다 — 1회성.
- 2026-09-17: **마스킹은 스키마 모듈이 아니라 `emit` 에서.** 근거: 정답지(.env) 위치는 프로젝트 경로가 있어야 하고 그것은 `emit` 만 안다. 스키마는 형식 검사 한 책임.
- 2026-09-17: **`kind=지시` 는 declined 거부, 규칙 위반은 blocked.** 근거: `handoff-contract.md:15-22` RV-07 — "지시는 거절 불가" 는 규칙 위 아님.

## 7. 발견·예외

- 2026-09-17 Step 2: 기존 handoff 테스트가 사람→에이전트 봉투(=지시)를 `declined` 로 닫고 있었다 — 설계상 불가라 테스트의 보내는 쪽을 명부 밖 에이전트(요청·미상)로 바꿈. `resolve()` 복잡도 17 → 헬퍼 3개로 분리(R-cx 11). `hermes_handoff_kind.py` 는 쓰기 전 R-declare 가 §4 미선언을 잡아 선언 뒤 생성.
- 2026-09-17 리뷰(code-reviewer, HIGH 0·MEDIUM 1·LOW 3): MEDIUM — 가드가 `summ""ons` 결합에 뚫림(리뷰어 재현) → 따옴표·백슬래시 제거 뒤 검사 + 테스트 2건; 변수 조립·인코딩은 한계로 주석에 명시(2차 방어는 소환 러너 가드·시작 훅 검증). LOW — `_kind_of` 는 이번 커밋 전 봉투(`kind=` 없음)를 `요청`(거절 가능)으로 본다: 안전 방향, 소급 채움은 하지 않음. LOW — `open_handoff(by=)` 는 신뢰된 호출자만: docstring 경고. LOW — 마스킹 팽창으로 500자 초과 시 원인 표시: 미반영(UX).
- 2026-09-17 세션 안 실측: 제 Bash 명령 문자열에 "소환 명령" 글자가 주석으로 들어가자 기존 소환 가드가 그것을 막았다 — 가드는 명령 본문만 보는 게 아니라 문자열 전체를 본다. 편집은 Edit 도구로 나눠서 함.
- 2026-09-17 전파 직후: 새 가드가 제 커밋 명령을 막았다 — 메시지에 표 이름과 `update-all` 이 함께 있어서. 쓰기 동사가 표 이름에 붙은 SQL 꼴일 때만 잡도록 좁힘(산문 통과·`main.` 접두 차단 테스트 추가, 46/46).
- 2026-09-17 Step 3: summons 쓰기 가드는 테스트·훅을 함께 썼으므로 빈 훅으로 바꿔 차단 단언 3건이 빨개지는 것을 대조 확인.
- 2026-09-17 Step 1: 새 모듈 `hermes_journal_migrate.py` 를 `hermes.conf` 복사 목록에 안 넣어 roster 테스트(실제 설치기로 깖) 4건·journal 2건이 빨개졌다 — 목록·`.deprc` tier 0 등록으로 초록. 실물 terminal-shipping `state.db` 사본: 19행 보존·0.04초·트리거/인덱스 복원·integrity ok.

## 8. 회고 (완료 시 작성)

- 잘된 것:
  - **전수 대조를 먼저 했다.** SOUL 한 건을 고치고 멈추지 않고 설계 9개 문서를 코드와 대조해 15+1건을 한 번에 봤다. 보안 1건(자유 글 원문 저장)과 거짓 체크 1건(계획 4 목표 11)은 대조 없이는 드러나지 않았을 것이다.
  - **DB 제약을 코드 목록에서 생성하게 바꿨다.** `kind` 가 튜플·SQL 두 곳에 있어 갈라졌던 것을 한 곳으로. 마이그레이션은 실물 소우주 DB 사본에서 19행·0.04초·integrity ok 로 증명.
  - **설치기 테스트가 복사 목록 누락을 두 번 잡았다.** 새 모듈을 `hermes.conf` 에 안 넣으면 roster 테스트(실제 설치기로 깖)가 바로 빨개진다 — 실물 경로를 타는 테스트의 가치.
- 잘못된 것:
  - 계획 4 목표 11 이 ✔ 인 채 코드 0건이었다 — 목표 문장에 "검증: 테스트 2케이스" 라 적고 만료 2케이스만 만든 채 `rule:` 부분을 빠뜨렸다. 한 목표에 두 동작을 묶으면 절반만 검증하고 체크할 수 있다. 앞으로 목표 1개 = 동작 1개.
  - 설계 "확정" 문장이 계획으로 옮겨졌는지 보는 장치가 없다. 오늘 16건이 전부 그 경로다.
- 다음 룰 후보: **`R-design-cover`** — `docs/hermes-universe/design/**` 의 "(확정)"·"✅ 리뷰 확정" 문장은 어느 계획서 §2 목표에든 인용(파일:줄)돼야 한다; 인용 없는 확정 문장이 있으면 pre-commit 경고. 강제 장치: `scripts/hooks/design_cover.py`(확정 문장 추출 → `docs/exec-plans/**` grep) + 테스트. `harness-promote-rule` 로 별도 승격.
