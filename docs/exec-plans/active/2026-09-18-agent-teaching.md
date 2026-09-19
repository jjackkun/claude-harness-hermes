# 2026-09-18-agent-teaching — 리뷰가 기억이 되는 경로 + 사람의 가르침 (설계 teaching.md 구현)

> 출처: `docs/hermes-universe/design/agent/teaching.md` (2026-09-18, 사용자 원칙 두 개 확정)
> 설계 결정 인용: C-21(리뷰→기억, 3회면 개인 스킬) · C-22(`teach`) · C-25(회의 = 순차 회람)·C-26(아카이브 = 소우주까지, 기억 승격) — 둘은 **이 계획의 비목표**(별도 계획 `agent-meeting`) ·
> C-23·C-24(직급 모델·봉투 무게 라우팅 — 모양은 확정, **값·임계는 09-29 관측 뒤**; 이 계획의 비목표, 별도 계획)
> 착수 조건: `agent-hire-form` 이 끝나 명부에 수습 1명 이상이 실제로 있을 것(그래야 리뷰 사슬을 실 데이터로 검증한다).
> 착수 조건 2 (2026-09-19 추가): `agent-memory-roundtrip` 목표 1·2 가 끝나 기억 이벤트가 MEMORY.md 로 보이고 컴퓨터 간 왕복할 것 — 리뷰가 만드는 기억이 한 컴퓨터에 갇히지 않게.

## 1. 동기 (Why)

teaching.md 개요의 실측 그대로: 학습 재료가 사람의 대화(Stop 훅 요약 → `main`)뿐이라 상급자 리뷰도 사람의 지적도 담당 에이전트의
기억에 닿지 않는다. C-21·C-22 는 그 길을 정했고, 이 계획이 그것을 코드로 옮긴다.

## 2. 목표 (What — 검증 가능한 형태)

- [ ] 목표 1 (C-21) — `resolve(…, "finished")` 가 닫히면 같은 unit 바로 위 rank 에게 `review` 봉투가 자동으로 열린다(위 rank 없으면 `human`).
  `inputs` 는 원 봉투 id·커밋·done_when 결과 참조만 — 검증: `bash tests/hermes-teaching-test.sh` 리뷰 절(픽스처 조직 2단·에이전트 2명)
- [ ] 목표 2 (C-21) — 리뷰 봉투를 `approved`/`corrected(about, body)` 로 닫으면 리뷰받은 에이전트의 `memory_events` 에 `memory.added`
  (`about` 필수, `source_event=review:<봉투 id>`)가 남는다. `about` 없는 `corrected` 는 거부 — 검증: 같은 테스트 기억 절
- [ ] 목표 3 (C-21) — 같은 `about` 의 `corrected` 3회 → 그 에이전트 개인 스킬 결정화(기존 결정화 루프, 철회 보류·도움률 강등 적용)
  — 검증: 같은 테스트 결정화 절(`claude` 가짜 실행파일)
- [ ] 목표 4 (C-22) — `hermes-agent.py teach "<이름>" --about <주제> "<한 줄>"` 가 `memory.added(by=human:…, source_event=teach)` 를 남기고,
  `about` 없으면 거부. 철회는 기존 `memory.retracted` — 검증: 같은 테스트 teach 절 + `hermes-roster-test.sh` 회귀
- [ ] 목표 5 (C-22) — `hermes-agent` 스킬이 "X 한테 이거 가르쳐" 를 `teach` 로 옮긴다(트리거 문구 추가) — 검증: skill-creator `run_eval.py`
- [ ] 목표 6 (C-21) — 대시보드 에이전트 판에 에이전트별 `about` 지적 누적 수 — 검증: `bash tests/hermes-dashboard-test.sh` (계획 hermes-dashboard 와 합류)
- [ ] 목표 7 (C-25·C-26 경계) — 이 계획은 회의·아카이브 승격을 구현하지 않는다. 소환 러너가 에이전트 1명·세션 1개인 현 상태를 확인만 한다 — 검증: `grep -c` 로 러너에 다중 에이전트 인자 0
- [ ] 목표 8 — 설치 폐로·의존 계층 — 검증: `bash tests/install-closure-test.sh` · `bash tests/dep-contract-test.sh` · `bash tests/run-all.sh --check-orphans`

## 3. 비목표 (Out of Scope)

- C-23(직급→모델)·C-24(봉투 무게→모델) — 모양은 확정됐으나 값·임계 미정. `agent-model-routing-blindspot`(09-29) 관측 뒤 별도 계획에서 구현.
- 리뷰어가 코드를 고치는 것 — 리뷰는 승인/지적만. 재작업은 원 담당의 새 봉투.
- 사람 대화(Stop 훅 요약)의 학습 경로 변경 — 그대로 `main` 에게.
- C-25(회의 순차 회람)·C-26(아카이브 = 소우주, 기억 승격) 구현 — 별도 계획 `agent-meeting`(참석자가 실제로 2명 이상 생긴 뒤).

## 4. 영향 영역

- 코드: `scripts/hermes_handoff.py`(finished → review 봉투 자동 개봉, approved/corrected 닫기), `scripts/hermes-agent.py`(`teach`),
  `assets/skills/hermes-agent/SKILL.md`(teach 트리거)
- **신규 파일 목록**:
  - `scripts/hermes_review_chain.py` — finished 봉투에서 리뷰어(바로 위 rank 또는 human)를 고르고 review 봉투 칸을 조립·기억 이벤트로 옮긴다(표준 모듈 + roster/org/memory_events import)
  - `tests/hermes-teaching-test.sh` — 조직 2단·에이전트 2명 픽스처로 리뷰 자동 개봉·기억 기록·3회 결정화·teach·about 거부 실측
- 룰: R3(모델 호출 없음 — 리뷰어 선택·기억 기록은 규칙) · R-iface ≤7 · R-dep(`.deprc` 계층: review_chain 은 roster(2)·memory_events(0) 위 → tier 3, handoff(2) 가 import 하면 handoff 가 4 로 오름 — 착수 시 계층 재배치 확인)
- 설치: `hermes.conf` 복사 목록 → 12곳 전파
- 데이터: `memory_events` 추가 전용(스키마 불변), `journal_events` 에 `handoff.review` kind 추가(KINDS·CHECK 마이그레이션 — `hermes_journal_migrate.py` 경로)

## 5. 단계 (Steps)

### Step 1. 리뷰어 선택·봉투 조립 모듈 + 테스트(RED→GREEN) [Plan/Impl]
### Step 2. handoff finished 훅 → review 개봉, approved/corrected → memory [Impl]
### Step 3. teach 명령 + 스킬 트리거 + 결정화 연결 [Impl]
### Step 4. journal KINDS 마이그레이션·등록·전파·실 소우주 1곳(수습 1명) 시연 [Review]

## 6. 의사결정 로그

- 2026-09-18: C-23·C-24 를 이 계획에서 뺀다 — 근거: 모양은 확정됐지만 관측(09-29) 전에 값·임계를 정하면 틀린 채 굳는다(설계 §3·§4).
- 2026-09-18: 착수 조건을 "수습 1명 이상" 으로 — 근거: 명부 9곳 전부 `main` 1명이라 리뷰 사슬을 실 데이터로 검증할 대상이 없다.

## 7. 발견·예외

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:
