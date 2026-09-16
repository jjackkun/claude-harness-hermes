# 2026-09-15-agent-identity — 명부·SOUL·조직 정의·소환 러너·기억 이벤트·인계 봉투

> 헤르메스 우주 구현 계획 **4/5**. 설계 원천: `design/agent/identity.md`(A-02~A-09, RV-05 · RV-06), `creation-and-organization.md`(C-01~C-17, RV-17), `memory-events.md`(C-14~C-16, RV-11), `handoff-contract.md`(H-01~H-05, RV-07 · RV-08).
> 선행: 계획 2(`universe.id`, `agents.json` 의 `main`, `journal_events`), 계획 3(기억 이벤트의 원격 보존 경로 `memory/`).
> 다음 계획: `2026-09-15-skill-layers-delivery.md` — 개인 스킬 경로가 `agent_id` 를 쓴다.

## 1. 동기 (Why)

- 에이전트는 하나뿐이고 스킬로 역할을 흉내 낸다. `assets/agents/*.md` 15개는 부를 때마다 백지에서 시작하는 역할 정의이지 계속 이어지는 개인이 아니다.
- 기록에 "누가 했는가" 가 없다(계획 2 가 칸을 만들었고, 이 계획이 실제 개인을 채운다).
- 명부 없이는 등록된 남의 id 사칭을 못 막는다(리뷰 R-5). V-4 확인: `SubagentStop` 의 `agent_type` 은 직무 템플릿 이름이지 우리 명부 id 가 아니다 → 소환 토큰이 필요하다.
- 기억을 `MEMORY.md` 에 직접 고쳐 쓰면 두 컴퓨터·두 세션이 동시에 부를 때 덮인다(C-14).
- 인계에 형식이 없어 `done_when` 없이 "성공" 을 주장한다(H-02).

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 명부 `.hermes/agents.json` 형식이 확정되고 검증기가 있다: `agent_id`(UUIDv7) · `name`(소우주 안 유일, 은퇴 이름 재사용 금지) · `status`(`probation|active|retired`) · `org`(`discipline` · `rank` · `unit`) · `template` · `created_at` · `approved_by`. 검증: `tests/hermes-roster-test.sh` — 중복 이름·은퇴 이름 재사용·모르는 상태값 거부.
- [x] 목표 2 — 입사·은퇴·복직 CLI: `hermes-agent.py hire <이름> --org … [--template …]`(사람만, 수습으로) · `promote`(→ active) · `retire` · `rehire`(RV-17). 검증: 테스트 상태 전이 6경로 + 폴더 `.hermes/agents/<agent_id>/{SOUL.md,MEMORY.md,skills/}` 생성.
- [x] 목표 3 — 조직 정의 `.hermes/organization.yaml` 스키마(G-14)와 공장 템플릿 3종(제품 개발 · 사무 · 빈 조직, G-15). 검증: 세 템플릿이 스키마 검증 통과, `unit` 마다 불변 `unit_id`(UUIDv7) 부여, 수직 축 맨 위 `human` 은 기계가 고정.
- [x] 목표 4 — 담당 매칭(C-11): 요청의 `discipline` · `unit` 값으로 명부를 찾고 더 많은 축이 맞는 쪽 우선, 없으면 "문의" 결과. 검증: 테스트 픽스처 — users 기획자 vs 공통 기획자, 없음 → `ask`.
- [ ] 목표 5 — 소환 러너 `hermes-summon.py` 가 `summons`(nonce · agent_id · requested_by · expires_at · used) 를 INSERT 하고 `HERMES_AGENT_ID` · `HERMES_SUMMON_NONCE` 를 넣어 `claude -p` 를 띄우며 `task.assigned` 를 남긴다(RV-06). 검증: 테스트 모의 `claude` 로 환경변수·이벤트·nonce 사용 표시 확인.
- [ ] 목표 6 — 세션 시작 훅이 nonce 를 검증한다: 짝 없음·재사용·만료면 행위자를 `system:unverified-session` 으로 바꾸고 경고. 검증: 테스트 4케이스. 세션은 멈추지 않는다.
- [ ] 목표 7 — PreToolUse 훅이 세션 안 Bash 의 `claude -p` 직접 호출을 막되, 허용 목록(`hermes-loop-run.sh` · `hermes-cron-run.sh` · `hermes-summon.py`)은 통과 — 판정은 명령줄이 아니라 **러너가 남긴 nonce 파일 존재**로. 검증: `tests/hermes-summon-guard-test.sh` — 직접 호출 차단, 러너 경유 통과, `bash -c 'exec hermes-loop-run.sh …'` 흉내는 nonce 없어 차단.
- [x] 목표 8 — 기억 이벤트 `memory_events`(UUIDv7 PK, `kind` · `about` · `revises` · `content_hash` · `source_event` · `body`)가 INSERT 전용이고, `MEMORY.md` 는 이벤트에서 계산한 보기다. 검증: `tests/hermes-memory-events-test.sh` — 갈라짐(같은 `revises` 둘)·같은 `about` 모순·`content_hash` 중복이 각각 "충돌"·"충돌"·"합침" 으로 표시, 최신이 자동 승리하지 않음.
- [x] 목표 9 — 규칙 충돌 표시(RV-11): 기억 `about` 키가 SOUL.md 또는 `assets/rules/**` 의 규칙 키와 겹치고 본문이 부정형이면 보기에 "규칙 충돌", `source_event` 하나면 "단일 사례". 검증: 테스트 픽스처 2건.
- [ ] 목표 10 — 인계 봉투 검증기: `goal` · `done_when` 없으면 시작 불가(기계 차단), `inputs` 는 참조만(경로·이벤트 id 형식), `expires_at` 선택. 되돌아오는 네 방식이 이벤트로 남는다. 검증: `tests/hermes-handoff-test.sh`.
- [ ] 목표 11 — 만료 판정은 세션 시작 훅(RV-08): 기한 지났는데 `task.started` · `handoff.question` 없는 봉투 → `handoff.expired` + 알림. 규칙 위반 지시는 `claimed: blocked` + `evidence.reason = rule:<이름>`(RV-07). 검증: 테스트 2케이스.
- [ ] 목표 12 — `done_when` 허용 형식(G-21) 첫 판: `test:<이름>` · `file:<경로>` · `gate:<규칙>` · `commit:<해시|HEAD>` · `manual` 다섯 가지. `manual` 만 `verified: none`. 검증: 각 형식의 기계 검증 함수 테스트.
- [ ] 목표 13 — 자연어 입사·소환이 스킬로 연결된다: `assets/skills/hermes-agent/SKILL.md` 가 "users 담당 입사시켜" · "이 일 QA 한테 넘겨" 를 위 CLI 로 안내. 검증: 스킬 description 트리거 평가(skill-creator 벤치) + 문서.
- [x] 목표 14 — 정체성 자산이 git 을 탄다(자체 리뷰 발견, planner-lite 정정): 현행 규칙은 `.hermes/*` 로 **내용물을** 무시하므로 하위 예외는 **디렉터리 단계마다** 풀어야 한다(`presets/workflow/hermes.conf:171-178` 의 `!.hermes/skills/` + `!.hermes/skills/**` 두 줄 패턴과 같은 이유). 마커에 순서대로: `!.hermes/agents/` · `!.hermes/agents/*/` · `!.hermes/agents/*/SOUL.md` · `!.hermes/agents/*/skills/` · `!.hermes/agents/*/skills/**` · `!.hermes/organization.yaml`, 그 **뒤에** 재무시 `.hermes/agents/*/MEMORY.md` · `.hermes/summons/`. 검증: 테스트가 `git check-ignore -v` 로 6경로를 고정 — SOUL·개인 스킬·organization.yaml 은 추적, MEMORY.md·summons·agents/*/ 의 그 밖 파일은 무시. 이 예외가 없으면 개인 스킬·SOUL 이 다른 컴퓨터로 가지 않는다.
- [x] 목표 15 — 은퇴 에이전트는 주입·매칭에서 빠진다(planner-lite 지적, RV-17 손해 직결): `retire` 뒤 그 에이전트의 개인 스킬·SOUL 은 파일로 남되 `hermes-search.py` 결과와 담당 매칭에서 0건. `rehire` 뒤 복귀. 검증: `tests/hermes-roster-test.sh` 은퇴/복직 전후 주입 결과 대조.
- [ ] 목표 16 — 구버전 스키마 호환(planner-lite 지적): `summons` · `memory_events` 테이블이 없는 기존 `state.db` 에서 세션 훅이 죽지 않고 한 줄 알린 뒤 exit 0. 지연 마이그레이션은 `_ensure_injection_source_column`(`scripts/hermes-search.py:53`) 패턴을 따라 훅이 첫 실행 때 만든다. 검증: 계획 2 이전 스키마 DB 사본으로 훅 실행 → exit 0 + 테이블 생성.

## 3. 비목표 (Out of Scope)

- 에이전트 복제 봉투(`kind: template`, G-23) — 계획 5 의 제안 배달 위에서.
- 에이전트 성적·강등 자동화(G-12) — 보기(`mismatch`)는 계획 2, 판단은 사람.
- 수습 방치 은퇴 기간(G-17) — 근거 없는 값 금지. 표시만.
- 요청 문장을 축 값으로 판별하는 모델 호출(G-16 문장 판별) — 이번에는 경로 감지 + 명시 인자만. 문장 판별은 스킬 안내로 에이전트가 인자를 채운다.
- 동료 사람 id 결정(G-13) — `git config user.name` 대조 + 명부의 `humans` 목록으로 최소 구현, 충돌 시 경고까지만.
- Claude Code 자체 메모리와의 관계(G-26) — 문서로 관계만 적고 통합하지 않는다.

## 4. 영향 영역

- 코드(수정): `presets/workflow/hermes.conf`(복사 목록 · 훅 등록 · 템플릿 설치), `scripts/hermes_journal.py`(행위자 결정에 nonce 검증 결과 반영), `scripts/hermes-loop-run.sh` · `scripts/hermes-cron-run.sh`(러너 경유 표시 = nonce 발급 호출), `scripts/hermes-init.py`(`summons` · `memory_events` 스키마), `assets/hooks/claude-sessionstart-sync-pull.sh`(계획 3)와 같은 자리에서 nonce·만료 판정 훅 순서 조정, `docs/hermes-universe/design/agent/*.md`(확정 표시). 세션 시작 훅은 계획 1(`factory-link-check`) · 3(`sync-pull`) · 4(`summons-verify`) · 5(`outbox-status`)로 **4개가 늘어난다** — 순서와 지연 총량은 §7.
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `scripts/hermes_roster.py` — 명부 `agents.json` 의 스키마 검증·조회·상태 전이 규칙(이름 유일, 은퇴 이름 재사용 금지)만.
  - `scripts/hermes_yaml_subset.py` — `organization.yaml` 이 쓰는 YAML 부분집합(스칼라 · 평면 목록 · 2단 맵)의 파서만(planner-lite 지적으로 `hermes_org.py` 에서 분리).
  - `scripts/hermes_org.py` — `organization.yaml` 스키마 검증·`unit_id` 부여·담당 매칭(더 많은 축 우선)만. 파싱은 위 모듈.
  - `scripts/hermes-agent.py` — CLI(`hire` · `promote` · `retire` · `rehire` · `list` · `whoami`) — 사람이 부르는 진입점, 정체성 폴더 생성.
  - `scripts/hermes_summons.py` — `summons` 테이블·nonce 발급·검증·사용 표시·만료.
  - `scripts/hermes-summon.py` — 러너: 명부에서 대상 찾기 → nonce → 환경변수 → `claude -p` 실행 → `task.assigned` · `task.finished`(usage 포함, V-8) 기록.
  - `scripts/hermes_memory_events.py` — `memory_events` 스키마와 INSERT(추가 전용)만.
  - `scripts/hermes_memory_conflicts.py` — 충돌 탐지(갈라짐 · `about` 모순 · 해시 중복)와 규칙 충돌·단일 사례 표시 계산만(읽기 전용).
  - `scripts/hermes_memory_view.py` — 이벤트와 충돌 표시에서 `MEMORY.md` 보기를 계산해 쓴다(파생, 사람이 고치지 않음).
  - `scripts/hermes_handoff.py` — 봉투 스키마·검증(`goal` · `done_when` 필수, `inputs` 참조 형식)·만료 판정·되돌아오는 네 이벤트 기록.
  - `scripts/hermes_done_when.py` — `done_when` 다섯 형식의 파싱과 기계 검증(`test:` · `file:` · `gate:` · `commit:` · `manual`)만.
  - `assets/hooks/claude-pretooluse-summon-guard.sh` — 세션 안 `claude -p` 직접 호출 차단(nonce 파일 기준 허용).
  - `assets/hooks/claude-sessionstart-summons-verify.sh` — nonce 검증 + 만료 봉투 판정·알림.
  - `assets/templates/agent/SOUL.md` — SOUL 머리말·본문 틀(역할 · 책임 경계 · 원칙 · 금지 · 도구).
  - `assets/templates/organization/product.yaml` · `office.yaml` · `empty.yaml` — 공장 조직 템플릿 3종(값만, 규칙 없음).
  - `assets/skills/hermes-agent/SKILL.md` — 자연어 입사·소환·인계 요청을 CLI 로 잇는 스킬.
  - `tests/hermes-roster-test.sh` · `tests/hermes-summon-guard-test.sh` · `tests/hermes-memory-events-test.sh` · `tests/hermes-handoff-test.sh` — 위 목표별 검증.
- 게이트 대비: 위 분리로 각 모듈 공개 심볼 7개 이하. `hermes-agent.py` CLI 는 서브커맨드 6개지만 공개 함수는 `main` 하나(서브커맨드는 `_cmd_*`).
- 룰: 새 R 룰 후보 "행위자 id 는 에이전트가 고르지 못한다(러너 발급)"(RV-06), "기억은 규칙 아래"(RV-11).
- 데이터: `summons` · `memory_events` 테이블 신설(INSERT 전용 트리거), `agents.json` 형식 확정(계획 2 의 `main` 항목과 호환 — 칸 추가만).
- 외부 의존: YAML 파서 — 표준 모듈에 없음. `organization.yaml` 은 **YAML 부분집합**(스칼라·평면 목록·2단 맵)만 허용하고 자체 파서(cumora `parseSkillMd` 와 같은 태도) 또는 JSON 병행 — §6.

## 5. 단계 (Steps)

### Step 1. 명부·조직 정의·CLI [Plan/Impl/Review]

- 산출: `hermes_roster.py`, `hermes_org.py`, `hermes-agent.py`, 템플릿 3종 + SOUL 템플릿, `hermes.conf` 설치 시 템플릿 복사(`organization.yaml` 은 없을 때만 `empty.yaml`).
- 검증: 목표 1·2·3·4.
- Review 승격 사유: 공유 경계(모든 훅·러너가 명부를 읽음).

### Step 2. 소환 토큰·러너·가드 [Plan/Impl/Review]

- 산출: `hermes_summons.py`, `hermes-summon.py`, 두 훅, 기존 러너 2개가 nonce 를 발급하도록 수정.
- 검증: 목표 5·6·7. zeroday 헤드리스 루프(`hermes-loop-run.sh`)가 계속 도는지 `tests/hermes-loop-test.sh` 로 회귀 확인.
- Review 승격 사유: 보안(사칭 방지).

### Step 3. 기억 이벤트·보기 [Impl]

- 산출: `hermes_memory_events.py`, `hermes_memory_view.py`, 계획 3 의 `memory/` 원격 경로에 조각 사상 추가.
- 검증: 목표 8·9.

### Step 4. 인계 봉투 [Impl]

- 산출: `hermes_handoff.py`, 세션 시작 훅에 만료 판정, `done_when` 다섯 형식.
- 검증: 목표 10·11·12.

### Step 5. 스킬·문서·테스트 등록 [Impl]

- 산출: `hermes-agent` 스킬(skill-creator 로 description 평가), `run-all.sh` 등록, `doc_counts`, 설계 문서 확정 표시(G-12 형식 · G-14 · G-15 · G-21 · G-29 · G-30 닫힘).
- 검증: 목표 13 + `bash tests/run-all.sh` 0 실패.

## 6. 의사결정 로그

- 2026-09-15: `organization.yaml` 은 YAML 부분집합만 허용하고 자체 파서로 읽는다 — 근거: 표준 모듈에 YAML 이 없고 헤르메스는 pip 의존을 두지 않는다. 틀렸을 때 손해: 앵커·다중 문서 같은 YAML 기능을 못 쓴다(필요 없음).
- 2026-09-15: nonce 검증 실패는 세션 차단이 아니라 `system:unverified-session` 표시 — 근거: 리뷰 후속 결정. 훅 오류 하나로 zeroday 루프 전체가 멈추면 안 된다. 틀렸을 때 손해: 출처 불명 이력이 쌓임(보기에서 드러남).
- 2026-09-15: 소환 가드의 허용 판정은 명령줄이 아니라 nonce 파일(`.hermes/summons/<nonce>.pending`) 존재 — 근거: 리뷰 주의 항목(명령줄 흉내). 틀렸을 때 손해: 러너가 nonce 파일을 못 만들면 정상 소환도 막힘 → 러너는 파일 생성 실패 시 소환을 중단하고 사람에게 알린다.
- 2026-09-15: `done_when` 형식 다섯 가지로 시작 — 근거: G-21 은 열려 있었고, 하네스가 이미 쓰는 신호(테스트 이름 · 파일 · 게이트 · 커밋)가 이 넷이다. `manual` 은 사람 검증. 틀렸을 때 손해: 형식이 부족하면 `manual` 이 늘어 `none` 비율이 오른다 — 그 비율이 곧 다음 형식을 추가할 신호.
- 2026-09-16: 설계 문서 갱신으로 계획서와 설계가 일치 — 근거: 대조 77건.
- 2026-09-16: 설치 시 `organization.yaml` 이 없으면 `empty.yaml` 을 자동 복사한다(C-18, 사용자 위임 확정) — 근거: 설치 직후에도 `main` 의 조직 값과 담당 매칭이 동작해야 한다. 고르기는 사람이 나중에. 틀렸을 때 손해: 빈 조직을 잊고 두면 매칭이 항상 "문의".
- 2026-09-15: 문장 판별(G-16) 은 이번에 하지 않고 스킬 안내로 에이전트가 축 값을 인자로 채운다 — 근거: 모델 호출을 훅에 넣으면 세션 시작이 느려지고 R3(LLM 경로) 문제가 생긴다. 틀렸을 때 손해: 담당 찾기가 에이전트 판단에 기대어 오매칭 가능 — 매칭 결과를 `task.assigned` 에 남겨 나중에 대조.

## 7. 발견·예외

- **2026-09-16 Step 1 에서 드러난 것**
  - `!.hermes/agents/*/` 로 폴더 예외를 풀면 **폴더 안 전부**가 추적된다. 계획의 "그 밖 파일은 무시"
    를 지키려면 그 뒤에 `.hermes/agents/*/*` 로 내용물을 도로 무시하고 SOUL·skills 만 다시 풀어야
    했다. 재무시 줄 `MEMORY.md` 는 이 규칙에 흡수됐다. 테스트가 7경로를 고정한다.
  - `match_agents` 가 복잡도 19 로 시작해 세 번 쪼갰다(`_score` · `_candidates`). 컴프리헨션 안의
    `for`/`if` 도 분기로 센다는 것을 이때 확인했다.
  - YAML 부분집합 파서는 미종결 흐름 목록(`[1,`)을 스칼라로 통과시켰다 — 닫힘 검사를 넣었다.
  - 설치기가 `organization.yaml` 이 없을 때만 `empty.yaml` 을 복사하고, 있으면 `unit_id` 만 채운다.
    공장 자신에게도 `.hermes/organization.yaml`(빈 조직)이 생겼다.
- **2026-09-16 Step 3 에서 드러난 것**
  - 설계 문서가 `memory.added`(3절 형식 표)와 `memory.learned`(다른 절)를 섞어 썼다. 3절 형식
    표를 원천으로 삼아 `memory.added`·`memory.revised`·`memory.retracted` 로 갔다.
  - 부정형 판정 정규식이 `쓰지\u0020않는다`(공백 없이 붙은 `않는다`)를 놓쳤다. `않는다|않다` 를
    추가해 잡았다. 이 판정은 모델 없이 어휘로만 하므로(R3 회피) 틀리면 표시가 과할 뿐 데이터는 안전하다.
  - install-receipt-test 가 전체 러너에서만 간헐 실패(단독 18/18). 영수증이 '표식 이후 ctime
    변경' 으로 파일을 잡는데 러너 부하로 같은 초에 설치가 겹치면 드물게 누락된다. 플레이크로 판정.
- 계획 2 가 만든 `agents.json` 의 `main` 항목은 `org` 가 비어 있다. 이 계획에서 `empty.yaml` 조직(수직 `human → main`)에 맞춰 채운다.
- `assets/agents/*.md` 15개는 그대로 **직무 템플릿**으로 남고, `template: <이름>@factory` 로 참조된다. 옮기지 않는다.
- 세션 시작 훅이 계획 1 · 3 · 4 · 5 에서 각 1개씩 **4개 늘어난다**(`factory-link-check` · `sync-pull` · `summons-verify` · `outbox-status`). 계획 3 의 `sync-pull` 은 기존 `history-reindex` 교체라 순증은 fetch 한 번이지만, 나머지 셋은 순증이다. 이 계획의 Step 2 에서 **세션 시작 지연 총량을 실측**해 §8 에 적는다(기존 훅 전부 + 새 훅 4개, `time` 으로 SessionStart 훅 체인 1회 실행). 지연이 늘면 nonce 검증 · 만료 판정 · outbox 조회를 훅 하나로 합치는 것이 후속 후보 — 근거 없이 미리 합치지 않는다.
- SOUL.md 는 "사람 승인으로만 수정"(identity.md §5)인데 세션 안 편집을 막는 장치가 이 계획에 없다. 계획 1 의 변조 경고 훅(`claude-posttooluse-factory-tamper-warn.sh`)이 설치 목록 기준이라 SOUL 은 대상이 아니다 → 백로그 `docs/exec-plans/backlog/soul-edit-guard.md` 후보(이 계획에서 파일만 만들지 않고 §8 룰 후보로 남김).

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보: RV-06 · RV-11 을 R 룰로.
