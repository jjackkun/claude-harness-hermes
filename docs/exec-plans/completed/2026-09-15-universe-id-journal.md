# 2026-09-15-universe-id-journal — 소우주 키(universe_id)와 작업 이력(journal_events)

> 헤르메스 우주 구현 계획 **2/5**. 설계 원천: `design/world/universe-isolation.md`(D-05 · D-06), `design/agent/work-journal.md`(J-03~J-07, RV-09 · RV-10), `design/agent/identity.md`(A-03~A-05, RV-05).
> 선행: 계획 1(복사 설치) — `factory.json` 과 같은 자리(`_hermes_setup`)에서 `universe.id` 를 만든다.
> 다음 계획: `2026-09-15-sync-transport-encryption.md` — 이 계획의 이벤트를 원격으로 옮긴다.

## 1. 동기 (Why)

- 프로젝트 id 가 **폴더 이름(basename)** 이다: `scripts/hermes-crystallize.py:393`, `scripts/hermes-save-session.py:57`, `scripts/hermes-summarize.py:248`. 같은 이름의 폴더가 두 곳에 있으면 키가 겹치고, 폴더 이름을 바꾸면 과거 기록과 끊긴다.
- `skill_index` 에 소우주 칸이 없고 파일 절대경로가 사실상 키다(`.hermes/state.db`).
- 작업 기록이 없다. 있는 것은 루프 안에서만 쌓이는 `loop_steps` · `loop_decisions`(이 저장소 0행)와 게이트 관측 `.harness/gate-events.jsonl` 뿐. "누가 무엇을 했고 성공했는가" 를 세션이 끝난 뒤 알 수 없다.
- 결정 원장(`2026-09-15-decision-ledger.md`, 진행 중)은 루프 전용 저장 구조라 대화형 세션의 결정이 남지 않는다(G-9).
- V-4 확인(2026-09-15): `SubagentStop` 훅에 `agent_id` · `agent_type` 이 오고 모든 훅에 `session_id` 가 온다 → 대화형 세션에서도 기계가 행위자와 직무 템플릿을 찍을 수 있다.
- V-8 확인: 훅 입력에 토큰 사용량은 없다 → `usage` 칸은 헤드리스 러너 경로에서만.

## 2. 목표 (What — 검증 가능한 형태)

> 설계 결정 인용(2026-09-18 소급, R-design-cover): A-04 · J-04 · J-08 · J-09 · D-04(저장소 하나 = 소우주 하나 — 전제, 인용 2026-09-18) — 이 계획의 목표가 구현한 원장 결정(docs/audits/2026-09-18-decision-id-mapping.md).

- [x] 목표 1 — 설치 시 `<소우주>/.hermes/universe.id`(UUID v4 한 줄)가 생기고 git 추적된다. 재설치해도 바뀌지 않는다. 검증: `tests/hermes-universe-test.sh` — 두 번 설치 후 값 동일, `.gitignore` 마커에 `!.hermes/universe.id`.
- [x] 목표 2 — 세 스크립트의 `project_id` 가 `universe.id` 값을 읽는다(없으면 basename 으로 폴백하고 `[hermes] universe.id 없음` 경고). 검증: 테스트에서 폴더 이름을 바꿔도 `session_summary.project_id` 가 같은 값.
- [x] 목표 3 — `journal_events` 테이블이 INSERT 만 허용한다. 검증: 테스트에서 `UPDATE` · `DELETE` 가 트리거로 실패(`sqlite3.IntegrityError`).
- [x] 목표 4 — 이벤트 기록기가 **허용목록 스키마**로만 받는다. 검증: 모르는 칸(`raw_text`) 을 넣으면 거부, `evidence.command` 에 인자가 붙으면(`curl -H …`) 명령 이름만 남김, `intent` 에 줄바꿈이면 거부.
- [x] 목표 5 — 결과 3층이 기록된다: `claimed` 는 에이전트, `verified` 는 기계(`none` 은 `done_when` 형식이 기계 검증 불가일 때만, RV-09), `accepted` 는 사람. 검증: 테스트에서 에이전트 입력으로 `verified` 를 넘기면 무시되고 기계 값이 남는다.
- [x] 목표 6 — Stop 훅이 세션 종료 시 `task.started` 만 있고 `task.finished` 없는 작업에 `system:claude-stop-journal-gap` 누락 이벤트를 붙인다. 검증: 테스트에서 모의 훅 입력으로 확인.
- [x] 목표 7 — 행위자가 기계로 찍힌다: 대화형 = `agent:<main id>` + `requested_by: human:<git user.name>`, 헤드리스 루프 = `requested_by` 루프 시작자, cron = `system:hermes-cron`, 하위 에이전트 = `evidence.template = <agent_type>`(V-4). 검증: 테스트 4경로.
- [x] 목표 8 — `loop_decisions` 의 결정이 `journal_events` 의 `decision` 이벤트로도 남는다(G-9 — J-05 는 "흡수" 가 아니라 **병기 후 단계적 흡수**). 검증: `tests/hermes-loop-test.sh` 결정 절 + journal 조회. 기존 `loop_decisions` 는 그대로 둔다(`hermes_loop_report.py` 가 읽음).
- [x] 목표 9 — 스레드 보기: `hermes-journal.py thread <task_id>` 가 시간순 이벤트를, `graph` 가 `parent_task_id` · `caused_by` 간선을 낸다. 검증: 테스트 픽스처 5건.
- [x] 목표 10 — 결정화 스킬 `rotate-ephemeral-work-logs` 가 작업 이력을 로테이션 대상에서 제외한다(G-10). 검증: 스킬 본문에 제외 문장 + `hermes-cleanup.py` 가 `journal_events` 를 건드리지 않음(테스트).
- [x] 목표 11 — 구버전 스키마 호환(planner-lite 지적): `journal_events` · `loops.started_by` 가 없는 기존 `state.db`(zeroday 포함)에서 Stop · SubagentStop 훅이 죽지 않고 한 줄 알린 뒤 exit 0, 첫 실행 때 지연 생성(`_ensure_injection_source_column` 패턴, `scripts/hermes-search.py:53`). 검증: 현재 스키마 DB 사본으로 훅 2개 실행 → exit 0 + 테이블·칸 생성.
- [x] 목표 12 — 롤백 경로(planner-lite 지적): 트리거가 기존 쓰기 경로를 막았을 때 `hermes-journal.py rollback --confirm` 이 트리거 2개와 테이블을 지우지 않고 **이름만 바꿔**(`journal_events_disabled_<ts>`) 훅이 조용히 건너뛰게 한다. 검증: 테스트 — rollback 뒤 훅 exit 0, 이벤트 보존.
- [x] 목표 13 — heartbeat(RV-10, 2026-09-16 사용자 위임 확정): 진행 중 작업은 `step` 이벤트를 N분마다 남기고, `task.started` 뒤 heartbeat 가 간격을 넘겨 끊기면 **Stop 훅을 기다리지 않고** 누락 이벤트(`system:claude-stop-journal-gap` 과 같은 형식, `evidence.reason = heartbeat-timeout`)를 붙인다. N 은 `.hermes/journal.json` 에서 설정 가능하고 **기본값은 구현 시 실측 후** 정한다(근거 없는 고정값 금지 — 이 저장소의 루프 `loop_steps` 간격 분포를 재서 적는다). 검증: `tests/hermes-journal-test.sh` — heartbeat 간격 초과 픽스처(`task.started` 뒤 마지막 `step` 시각이 N 을 넘김) → `gap-check` 가 누락 이벤트 1건, 간격 안이면 0건.

## 3. 비목표 (Out of Scope)

- 원격 보존(`refs/hermes/sync`)과 자유 글 칸 암호화 — 계획 3. 이번에는 로컬 `state.db` 만.
- 명부 전체·입사·소환 러너·소환 토큰 — 계획 4. 이번에는 설치 시 `main` 한 명만 `.hermes/agents.json` 에 만든다(행위자를 찍으려면 id 가 필요).
- 기억 이벤트 `memory_events` — 계획 4.
- `tombstone` 비상 삭제 실제 절차(G-5) — 계획 3(참조 재작성이 필요).
- `global.db` `harness_rules` 쓰기 중단(L-05) — 계획 5.
- 에이전트 성적 계산(G-12) — 보기 하나(`claimed=success & verified=fail` 목록)만 이번에.

## 4. 영향 영역

- 코드(수정): `scripts/hermes_loop.py`(`loops.started_by` 칸 추가), `scripts/hermes-init.py`(테이블·트리거 생성 호출), `scripts/hermes-crystallize.py:393` · `scripts/hermes-save-session.py:57` · `scripts/hermes-summarize.py:248`(universe_id 읽기), `scripts/hermes_loop_decisions.py`(결정 저장 시 journal 에도 기록), `scripts/hermes-loop-run.sh` · `scripts/hermes-cron-run.sh`(`HERMES_REQUESTED_BY` 환경변수 주입, `claude -p --output-format json` 의 usage 를 `evidence.usage` 로), `assets/hooks/claude-stop-retrospective.sh`(세션 종료 시 누락 감지 호출), `presets/workflow/hermes.conf`(`_hermes_setup` 에서 universe.id · agents.json 생성, 복사 목록에 새 모듈 추가, `.gitignore` 예외), `scripts/hermes-cleanup.py`(journal 제외 확인), `.hermes/skills/rotate-ephemeral-work-logs.md`(제외 문장).
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `scripts/hermes_universe.py` — `universe.id` 읽기·생성·폴백 판정 한 가지만 담당한다(모든 스크립트가 이 함수로 소우주 키를 얻는다).
  - `scripts/hermes_journal_schema.py` — `journal_events` 테이블·INSERT 전용 트리거·허용목록 스키마 정의와 검증기(칸 이름, 값 집합, `evidence` 정제 규칙).
  - `scripts/hermes_journal.py` — 이벤트 한 건을 검증해 INSERT 하고, 행위자(`actor` · `requested_by`)를 환경·훅 입력에서 결정한다.
  - `scripts/hermes_journal_views.py` — 스레드·그래프·"주장 vs 검증 불일치" 보기를 이벤트에서 계산한다(파생, 쓰기 없음).
  - `scripts/hermes-journal.py` — CLI(`emit` · `thread` · `graph` · `gap-check` · `mismatch`) — 훅·러너·사람이 부르는 진입점.
  - `scripts/hermes_uuid7.py` — UUIDv7 생성(Python 3.10 표준에는 없음. 3.12 `uuid.uuid7` 도 없음 — RFC 9562 대로 시간 48비트 + 난수).
  - `assets/hooks/claude-stop-journal-gap.sh` — Stop 훅에서 미완료 `task.started` 를 찾아 누락 이벤트를 남긴다.
  - `assets/hooks/claude-subagentstop-journal.sh` — `SubagentStop` 입력의 `agent_type` · `session_id` 로 하위 에이전트 `task.finished` 를 기록한다(V-4).
  - `tests/hermes-universe-test.sh` — universe.id 생성·불변·폴백과 세 스크립트의 키 전환을 검증한다.
  - `tests/hermes-journal-test.sh` — 스키마 허용목록·트리거·결과 3층·행위자 4경로·누락 감지·보기를 검증한다.
- 게이트 대비: 각 신규 파이썬 모듈은 공개 심볼 7개 이하(내부는 `_` 접두), 400줄 이하. `hermes_journal_schema.py` 가 넘치면 `evidence` 정제만 `hermes_journal_evidence.py` 로 뗀다.
- 자체 리뷰 반영(2026-09-15): 헤드리스 루프의 지시자를 알 수 있는 칸이 없다 — `loops` 테이블(`id · title · goal_md_path · mode · branch · status · max_iterations …`)에 `started_by` 가 없다. `hermes_loop.py` 의 루프 생성 시 `started_by`(`human:<git user.name>` 또는 `system:hermes-cron`) 칸을 추가(`ALTER TABLE … ADD COLUMN`)하고 러너가 이 값을 `HERMES_REQUESTED_BY` 로 넘긴다. 목표 7 의 검증에 포함.
- 룰: 새 R 룰 후보 "작업 이력은 원문을 담지 않는다(허용목록)" — J-06. 강제 장치는 `hermes_journal_schema.py` 검증기 + 테스트.
- 데이터: 새 테이블 `journal_events`(`CREATE TABLE IF NOT EXISTS` — 기존 DB 무손실), 트리거 2개. `session_summary.project_id` 는 칸 이름 그대로 두고 값만 universe_id 로(이름 변경은 마이그레이션 비용 대비 이득 없음). 기존 행은 basename 값 그대로(L-02 — 옛 자산은 옮기지 않는다).
- 외부 의존: 없음. sqlite3 표준 모듈.

### journal_events 스키마(안, G-6 닫기)

```sql
CREATE TABLE IF NOT EXISTS journal_events (
  event_id        TEXT PRIMARY KEY,          -- UUIDv7
  ts              TEXT NOT NULL,             -- ISO-8601 UTC
  kind            TEXT NOT NULL CHECK (kind IN ('task.assigned','task.started','step','decision',
                                                'task.handoff','task.finished','correction','tombstone',
                                                'handoff.declined','handoff.question','handoff.expired','handoff.external')),
  universe_id     TEXT NOT NULL,
  task_id         TEXT NOT NULL,
  parent_task_id  TEXT,
  caused_by       TEXT,                      -- JSON 배열(event_id)
  actor           TEXT NOT NULL,             -- human:|agent:|system:
  requested_by    TEXT,
  session_id      TEXT,                      -- 참조만
  claimed         TEXT CHECK (claimed IN ('success','failure','partial','blocked','abandoned') OR claimed IS NULL),
  verified        TEXT CHECK (verified IN ('pass','fail','none') OR verified IS NULL),
  accepted        TEXT,
  evidence        TEXT,                      -- JSON: exit_code, commit, files[], command(이름만), bytes, template, usage, reason
  intent          TEXT, lesson TEXT, decision TEXT   -- 한 줄. 계획 3에서 원격 사본만 암호화
);
CREATE TRIGGER IF NOT EXISTS journal_no_update BEFORE UPDATE ON journal_events BEGIN SELECT RAISE(ABORT,'journal_events is append-only'); END;
CREATE TRIGGER IF NOT EXISTS journal_no_delete BEFORE DELETE ON journal_events BEGIN SELECT RAISE(ABORT,'journal_events is append-only'); END;
```

- `tombstone` 뒤 물리 삭제(G-5)는 사람이 트리거를 잠시 내리고 하는 별도 스크립트(계획 3)로만.

## 5. 단계 (Steps)

### Step 1. universe.id + main 명부 [Impl]

- 산출: `hermes_universe.py`, `_hermes_setup` 수정(없을 때만 생성, `.gitignore` 예외 `!.hermes/universe.id` · `!.hermes/agents.json`), `agents.json` 에 `main` 한 명(`{"agents":[{"agent_id":"<uuid7>","name":"main","status":"active","created_by":"system:installer"}]}`).
- 검증: 목표 1.

### Step 2. project_id → universe_id [Impl]

- 산출: 세 스크립트 수정. 폴백 경고.
- 검증: 목표 2. 기존 `tests/hermes-pipeline-test.sh` 통과.

### Step 3. 스키마·기록기·보기 [Plan/Impl/Review]

- 산출: `hermes_journal_schema.py`, `hermes_journal.py`, `hermes_journal_views.py`, `hermes-journal.py`, `hermes_uuid7.py`. `hermes-init.py` 가 스키마를 만든다.
- 검증: 목표 3·4·5·9. R-iface(새 파일 공개 심볼 8 미만)에 맞춰 모듈을 나눴다 — CLI 가 진입점, 나머지는 각 1~4 함수.
- Review 승격 사유: 공유 경계(모든 훅·러너가 쓰는 스키마) + 보안(허용목록).

### Step 4. 행위자 배선 [Impl]

- 산출: 러너 두 스크립트에 `HERMES_REQUESTED_BY` 주입, `hermes_journal.py` 의 행위자 결정(환경변수 → 훅 입력 `agent_type` → 기본 `main`), `claude-subagentstop-journal.sh`, `hermes.conf` 훅 등록. 사람 id 는 `git config user.name`(G-13 은 계획 4).
- 검증: 목표 7.

### Step 5. 누락 감지 + 결정 흡수 + 로테이션 제외 [Impl]

- 산출: `claude-stop-journal-gap.sh`, `hermes-journal.py gap-check` 의 heartbeat 간격 판정(목표 13, N 은 `.hermes/journal.json`), `hermes_loop_decisions.py` 에서 `decision` 이벤트 병기, `rotate-ephemeral-work-logs.md` 제외 문장, `hermes-cleanup.py` 확인.
- 검증: 목표 6·8·10·13.

### Step 6. 테스트·복사 목록·문서 [Impl]

- 산출: 테스트 2개, `run-all.sh` 등록, `hermes.conf` 복사 목록 6개 모듈 추가, `doc_counts` 동기화, `docs/hermes-universe/design/agent/work-journal.md` §4 스키마 확정 표시.
- 검증: `bash tests/run-all.sh` 0 실패.

## 6. 의사결정 로그

- 2026-09-15: `session_summary.project_id` 칸 이름을 유지하고 값만 바꾼다 — 근거: 읽는 코드 7곳 변경 비용 대비 이득 없음. 틀렸을 때 손해: 이름이 뜻과 어긋남(주석으로 표기).
- 2026-09-15: UUIDv7 은 자체 구현(`hermes_uuid7.py`) — 근거: 이 환경 Python 3.10(WSL 시스템)·3.12(pyenv) 어느 쪽에도 `uuid.uuid7` 이 없다. 틀렸을 때 손해: 표준이 들어오면 교체(함수 하나).
- 2026-09-15: 대화형 세션의 기본 행위자는 설치 시 만든 `main` 의 id — 근거: A-05. 명부 전체는 계획 4 지만 id 없이는 이력을 찍을 수 없다. 틀렸을 때 손해: 계획 4 에서 명부 형식이 바뀌면 `agents.json` 마이그레이션(한 항목).
- 2026-09-15: `usage` 칸은 러너 경로만 — 근거: V-8. 틀렸을 때 손해: 대화형 비용은 실측 불가로 남음(백로그 `platform-cost-performance-levers` 에 표기).
- 2026-09-16: 설계 문서 갱신으로 계획서와 설계가 일치 — 근거: 대조 77건.
- 2026-09-16: heartbeat 간격 N 의 기본값을 문서에서 정하지 않는다 — 근거: 근거 있는 값이 없다. 구현 시 이 저장소·zeroday 의 `loop_steps` 간격을 실측해 적고 설정 가능하게 둔다. 틀렸을 때 손해: 첫 실측 전까지 heartbeat 누락 감지가 꺼진 상태(Stop 훅 감지만 동작).
- 2026-09-15: `verified` 계산은 이번에 `exit_code`(러너·Bash 훅) · 커밋 존재 · 게이트 판정 세 가지만 — 근거: `done_when` 형식(G-21)은 계획 4 봉투와 함께 정한다. 그 전까지 `done_when` 없는 작업은 `verified: none` 이 정상.

## 7. 발견·예외

- `loop_decisions` 를 journal 로 완전히 대체하지 않고 병기한다 — `hermes_loop_report.py` 가 `loop_decisions` 를 읽어 report.html 을 만든다. 대체(단계적 흡수)는 계획 5 이후 별도. decision-log J-05 를 이 내용으로 정정했다(2026-09-16).
- 기존 `messages` 테이블(`hermes-message.py`)은 설계상 폐기 대상(skill-proposal-delivery §4)이나 이번 범위 밖 — 계획 5 에서 정리.
- **같은 커널 틱에서는 "이후" 가 없다**(Step 1 여파): 설치 영수증에서 겪은 것과 같은 문제를
  이 계획에서도 만날 뻔했다. 시각 비교로 "그 뒤에 일어난 일" 을 고를 때는 틱을 넘겼는지 확인해야 한다.
- **설치기에 `SubagentStop` 훅 지원이 아예 없었다**(Step 4): 계획 §4 는 이 훅이 있다고 전제했으나
  `lib/settings_gen.sh` · `lib/generate_settings_json.py` 어디에도 없었다. 훅 종류를 하나 더하자
  `generate_settings_json` 복잡도가 기준선 48을 넘어 50이 됐고, if 4개를 표 하나로 접어 46으로
  **낮춘 뒤** 기준선도 46으로 내렸다(회피가 아니라 개선).
- **기본값 판정이 기존 테스트를 깼다**(Step 5): heartbeat 기본값을 120분으로 넣자
  `gap-check` 가 "방금 시작한 작업" 을 더 이상 누락으로 보지 않게 되어, 그 전에 쓴 단언 3개가
  실패했다. 세션 종료용 `--all` 을 따로 두는 것이 맞는 설계였고 테스트를 그에 맞게 고쳤다.
- `hermes_loop_decisions.py` 가 `.deprc` 의 어느 계층에도 없었다(R-dep-4 경고). 새 모듈 6개와 함께
  실측 import 그래프로 tier 를 계산해 등록했다(0·1·2·3).

## 8. 회고

- **잘된 것 — 기계가 믿지 않게 만든 것.** `verified` 를 입력으로 받지 않고 기록기가 다시 계산하게
  한 덕에, 에이전트가 `verified: pass` 를 주장해도 증거가 없으면 `none` 으로 남는다. "주장 성공 ·
  기계 실패"(`mismatch`) 보기가 그 자리에서 공짜로 나온다.
- **잘된 것 — 허용목록이 원문 유입을 실제로 막는다.** `evidence.command` 를 이름만 남기게 해서
  `curl -H "Authorization: Bearer …"` 를 넣어도 `curl` 만 저장된다(테스트로 고정). 모르는 칸은
  조용히 버리지 않고 거부한다 — 버리면 기록자가 계속 같은 실수를 한다.
- **잘못된 것 — 계획서가 설치기의 실제 능력을 확인하지 않았다.** `SubagentStop` 훅이 있다고
  전제했으나 없었다. 계획 §4 "영향 영역" 을 쓸 때 훅 배열 이름을 실측했더라면 Step 4 범위가
  처음부터 정확했을 것이다.
- **잘못된 것 — 기존 테스트를 깨는 기본값.** 값을 정하는 변경은 그 값을 전제하던 단언을 깬다.
  실측으로 값을 정한 것은 맞았지만, 정하기 전에 어떤 단언이 "값 없음" 에 기대고 있는지 먼저
  봤어야 했다.
- **다음 룰 후보:** "작업 이력은 원문을 담지 않는다(허용목록)" → `hermes_journal_schema.validate`
  가 강제 장치이고 `tests/hermes-journal-test.sh` §3 이 검증한다. R 룰로 승격할 만하다.
