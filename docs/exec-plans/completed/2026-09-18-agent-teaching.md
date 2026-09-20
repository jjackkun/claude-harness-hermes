# 2026-09-18-agent-teaching — 리뷰가 기억이 되는 경로 + 사람의 가르침 (설계 teaching.md 구현)

> 출처: `docs/hermes-universe/design/agent/teaching.md` (2026-09-18, 사용자 원칙 두 개 확정)
> 설계 결정 인용: C-21(리뷰→기억, 3회면 개인 스킬) · C-22(`teach`) · C-25(회의 = 순차 회람)·C-26(아카이브 = 소우주까지, 기억 승격) — 둘은 **이 계획의 비목표**(별도 계획 `agent-meeting`) ·
> C-23·C-24(직급 모델·봉투 무게 라우팅 — 모양은 확정, **값·임계는 09-29 관측 뒤**; 이 계획의 비목표, 별도 계획)
> 착수 조건: `agent-hire-form` 이 끝나 명부에 수습 1명 이상이 실제로 있을 것(그래야 리뷰 사슬을 실 데이터로 검증한다).
> 착수 조건 2 (2026-09-19 추가): `agent-memory-roundtrip` 목표 1·2 가 끝나 기억 이벤트가 MEMORY.md 로 보이고 컴퓨터 간 왕복할 것 — 리뷰가 만드는 기억이 한 컴퓨터에 갇히지 않게.
> → 2026-09-20 충족: roundtrip·transport-plain 완료(completed/). 기억 이벤트는 평문 운반으로 컴퓨터를 따라간다.

## 1. 동기 (Why)

teaching.md 개요의 실측 그대로: 학습 재료가 사람의 대화(Stop 훅 요약 → `main`)뿐이라 상급자 리뷰도 사람의 지적도 담당 에이전트의
기억에 닿지 않는다. C-21·C-22 는 그 길을 정했고, 이 계획이 그것을 코드로 옮긴다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 (C-21) — `resolve(…, "finished")` 가 닫히면 같은 unit 바로 위 rank 에게 `review` 봉투가 자동으로 열린다(위 rank 없으면 `human`).
  `inputs` 는 원 봉투 id·커밋·done_when 결과 참조만 — 검증: `bash tests/hermes-teaching-test.sh` 리뷰 절(픽스처 조직 2단·에이전트 2명)
- [x] 목표 2 (C-21) — 리뷰 봉투를 `approved`/`corrected(about, body)` 로 닫으면 리뷰받은 에이전트의 `memory_events` 에 `memory.added`
  (`about` 필수, `source_event=review:<봉투 id>`)가 남는다. `about` 없는 `corrected` 는 거부. `about` 은 `<domain>/<slug>` 형식만 받는다
  (domain 고정 집합 gate·test·git·debug·workflow·file·sync·agent, slug 는 `^[A-Za-z0-9][A-Za-z0-9._-]*$` ≤128자), `kind` 는 observation·preference·fact·decision·note 5종,
  본문·about 에 비밀 패턴 `(api[_-]?key|token|secret|password|authorization|credentials?|auth)` 뒤 값은 `[REDACTED]` — 검증: 같은 테스트 기억 절(형식 위반 3종 거부)
- [x] 목표 3 (C-21) — 같은 `about` 의 `corrected` 3회 → 그 에이전트 개인 스킬 결정화(기존 결정화 루프, 철회 보류·도움률 강등 적용)
  결정화되면 원 기억은 지우지 않고 `memory.revised`(body="스킬 <이름> 으로 승격", revises=원 memory_id) 한 건씩 남기며, MEMORY.md 는 그 about 을 한 줄로 접는다
  — 검증: 같은 테스트 결정화 절(`claude` 가짜 실행파일, 승격 뒤 `memory_events` 행 수 = 원 3 + revised 3)
- [x] 목표 4 (C-22) — `hermes-agent.py teach "<이름>" --about <주제> "<한 줄>"` 가 `memory.added(by=human:…, source_event=teach)` 를 남기고,
  `about` 없으면 거부. 철회는 기존 `memory.retracted` — 검증: 같은 테스트 teach 절 + `hermes-roster-test.sh` 회귀
- [x] 목표 5 (C-22) — `hermes-agent` 스킬이 "X 한테 이거 가르쳐" 를 `teach` 로 옮긴다(트리거 문구 추가) — 검증: skill-creator `run_eval.py`
- [x] 목표 6 (C-21, hermes-dashboard 계획으로 이관) — 대시보드 에이전트 판에 에이전트별 `about` 지적 누적 수 — 검증: `bash tests/hermes-dashboard-test.sh` (계획 hermes-dashboard 와 합류)
- [x] 목표 7 (C-25·C-26 경계) — 이 계획은 회의·아카이브 승격을 구현하지 않는다. 소환 러너가 에이전트 1명·세션 1개인 현 상태를 확인만 한다 — 검증: `grep -c` 로 러너에 다중 에이전트 인자 0
- [x] 목표 9 (cumora 식 자기 기록) — 소환 러너(`hermes-summon.py run`)의 지시문 꼬리에 "끝나기 전에 배운 것 한 줄을 `python3 scripts/hermes-agent.py note \"<한 줄>\" --about <domain>/<slug>` 로 남겨라" 가 붙고,
  `note` 는 `memory.added(by=agent:<id>, source_event=task:<nonce>)` 를 남긴다. 모델 추가 호출 0 — 검증: `hermes-teaching-test.sh` note 절 + 러너 지시문 grep
- [x] 목표 10 (주입 선별) — 세션 시작 훅이 MEMORY.md 전체 대신 **핀 전체 + 이번 봉투 about/키워드 일치 상위 6 + 최근 4** 만 넣고, 4,096 B 를 넘으면
  ECC 식 마커 `[…잘림 N B — 원문 <경로>]` 를 붙인다(기존 clipped 재사용). `hermes-agent.py pin <이름> <memory_id>` 가 핀을 토글한다 — 검증: `hermes-teaching-test.sh` 주입 절(기억 15건 → 10건 + 마커)
- [x] 목표 8 — 설치 폐로·의존 계층 — 검증: `bash tests/install-closure-test.sh` · `bash tests/dep-contract-test.sh` · `bash tests/run-all.sh --check-orphans`

## 3. 비목표 (Out of Scope)

- C-23(직급→모델)·C-24(봉투 무게→모델) — 모양은 확정됐으나 값·임계 미정. `agent-model-routing-blindspot`(09-29) 관측 뒤 별도 계획에서 구현.
- 리뷰어가 코드를 고치는 것 — 리뷰는 승인/지적만. 재작업은 원 담당의 새 봉투.
- 사람 대화(Stop 훅 요약)의 학습 경로 변경 — 그대로 `main` 에게.
- C-25(회의 순차 회람)·C-26(아카이브 = 소우주, 기억 승격) 구현 — 별도 계획 `agent-meeting`(참석자가 실제로 2명 이상 생긴 뒤).

## 4. 영향 영역

- 코드: `scripts/hermes_handoff.py`(finished → review 봉투 자동 개봉, approved/corrected 닫기), `scripts/hermes-agent.py`(`teach`·`note`·`pin`), `scripts/hermes-summon.py`(지시문 꼬리),
  `scripts/hermes_memory_view.py`(승격 about 접기), `assets/hooks/claude-sessionstart-agent-soul.sh`(주입 선별),
  `assets/skills/hermes-agent/SKILL.md`(teach 트리거)
- **신규 파일 목록**:
  - `scripts/hermes_review_chain.py` — finished 봉투에서 리뷰어(바로 위 rank 또는 human)를 고르고 review 봉투 칸을 조립·기억 이벤트로 옮긴다(표준 모듈 + roster/org/memory_events import)
  - `tests/hermes-teaching-test.sh` — 조직 2단·에이전트 2명 픽스처로 리뷰 자동 개봉·기억 기록·3회 결정화·teach·about 거부 실측
  - `scripts/hermes_crystallize_evidence.py` — 결정화 증거 수집(검색어·세션 증거·기억 증거·패턴 수). hermes-crystallize.py 가 R-size 500 을 넘어 떼어냄. 공개 함수 5개
  - `scripts/hermes_review.py` — 리뷰 봉투 닫기(approved/corrected → 기억 + 3회 결정화). handoff 와 review_chain 위의 상위 모듈(순환 금지). 공개 함수 2개
  - `scripts/hermes_memory_select.py` — 세션 시작 주입에 넣을 기억을 고른다(핀 전부 → 과제 낱말 겹침 상위 6 → 최근 4)와 그 본문 렌더. 파일 MEMORY.md 는 건드리지 않는다. 공개 함수 2개
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

- 2026-09-20: 자기 기록은 cumora 식(프롬프트가 `note` 를 부르게) — 근거: `docs/audits/2026-09-19-memory-md-reference.md` 쟁점 1. ECC 식 도구 로그 관찰+observer 는 R3·비용으로 제외.
- 2026-09-20: 주입은 핀 + about 일치 6 + 최근 4 — 근거: 같은 문서 쟁점 2(ECC 6 · cumora 10 사이). 의미검색은 R3 로 불가, 키워드 매칭(`hermes_search_fallback`) 재사용.
- 2026-09-20: `about` = `<domain>/<slug>` · `kind` 5종 · redact 정규식 — 근거: 같은 문서 쟁점 3. 원격 평문 칸이라 봉투 누출 게이트도 통과해야 한다.
- 2026-09-20: 승격 뒤 원 기억은 남기고 `memory.revised` 로 표시 — 근거: 같은 문서 쟁점 4(ECC `evolved_from`), INSERT 전용(C-14)과 일치. confidence 감쇠는 두 곳 다 미구현이라 채택 안 함.

## 7. 발견·예외

- 2026-09-20 Step 1·2 완료: `hermes_review_chain.py`(reviewer_for·open_review·close_review·record_teaching·check_about, tier 2) + `hermes_handoff.resolve(finished)` 뒤 자동 개봉 + `derive_kind` 가 `system:` 행위자를 지시로.
  테스트 `hermes-teaching-test.sh` 24단언(리뷰어 선택·자동 개봉·human 폴백·닫기→기억·마스킹·MEMORY.md·리뷰의 리뷰 없음·about 형식 5종 거부·corrected 누적 3) · handoff 55 · dep 21.
- 설계와 다른 점: journal 에 `handoff.review` kind 를 추가하지 않았다 — task.assigned 의 intent "리뷰: …" + decision `constraints=review-of=…;reviewee=…;verified=…` 로 표시(CHECK 마이그레이션 회피). 판정(approved/corrected)은 memory_events.source_event 에 남는다.
- 순환 import: 처음엔 같은 tier 에서 서로 늦게 부르게 했으나 depcheck 가 순환(R-dep-2)을 tier 와 별개로 차단했다 → review_chain 은 handoff 를 import 하지 않고
  개봉 함수를 인자로 받으며, 닫기(close_review)는 상위 모듈 `hermes_review.py`(tier 3)로 옮겼다. 자기 계약 검사가 미등록으로 잡던 `scripts/hooks/*.py` 7개도 tier 0 으로 등록.
- 2026-09-20 Step 3 완료: `hermes-crystallize.py --agent`(개인 층, 증거는 그 에이전트의 기억, 장부 키 `agent:<id>:<about>`) · `hermes_review.close_review` 가 3회째에 결정화 호출 ·
  `hermes-agent.py teach/note/pin` + `memory_pins` 표 · 소환 러너 지시문 꼬리(note) + `HERMES_TASK_HINT` · `hermes_memory_select.py`(핀 → 과제 관련 6 → 최근 4) 를 세션 시작 훅에 연결(DB 없으면 파일 폴백).
  테스트: teaching 40(가짜 claude 로 결정화 실측) · soul-inject 35(선별 6단언) · handoff 55 · roster 51 · summon 56 · memory-events 29 · dep 21 · closure 9.
- 발견(과마스킹): 자동 정답지에 명부 에이전트 이름을 넣자 작업 이력의 `chosen=QA담당` 이 가려져 summon·roster 테스트가 깨졌다 → 명부 이름 제외(기계 식별자). transport-plain §7 의 후보를 실측으로 닫음.
- 목표 5 의 run_eval 은 세션 안에서 돌지 않아(summon-guard) 트리거 문구·표·§7 절만 추가했다. 세션 밖 실행은 hire-form 계획 §7 과 같은 명령.
- 목표 6(대시보드 에이전트 판)은 `hermes-dashboard` 계획이 맡는다 — 여기서는 `memory_events` 의 `source_event LIKE 'review:%:corrected:%'` 를 about 별로 세면 된다는 것만 적어 둔다.

- 목표 6 은 `hermes-dashboard` 계획 목표 2(에이전트 판)에 "about 별 corrected 누적 수" 로 넘겼다. 셈은 `memory_events` 에서 `source_event LIKE 'review:%:corrected:%'` 를 about 별로.

## 8. 회고 (완료 시 작성)

- 잘된 것: 리뷰 → 기억 → 3회 결정화 → 선별 주입까지 한 사슬이 테스트(40단언, 가짜 claude)로 실측됐다. 기존 결정화 루프·봉투·명부를 재사용해 새 개념 없이 이었다.
- 잘못된 것: 순환 import 를 "같은 tier 면 된다" 고 짐작했다가 depcheck 에 막혀 모듈을 다시 나눴다. 복잡도·크기 게이트에 세 번 걸렸다 — 함수를 쓸 때 분기 수를 먼저 세야 했다.
  자동 정답지에 명부 이름을 넣어 다른 테스트를 깨뜨렸다(과마스킹은 실측 뒤 정한다는 교훈).
- 다음 룰 후보: "새 모듈은 tier 와 순환을 코드 쓰기 전에 .deprc 에 먼저 적는다" · "가르침(about)의 domain 집합은 설계 문서가 정본".
