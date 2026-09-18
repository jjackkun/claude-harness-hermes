# 2026-09-18-plan-stale-completion — R-plan-stale·R-plan-missing 이 완료 커밋을 오발화하지 않게

> 출처: `docs/exec-plans/backlog/plan-stale-completion-blindspot.md` (본 계획으로 승격, backlog 파일 삭제)
> 설계 결정 인용: 없음 — pre-commit 게이트 판정 경계 수정. 원장 결정과 무관.

## 1. 동기 (Why)

`R-plan-stale` 은 `active/` 에 스테이징된 계획서가 있는지만 본다. 계획서를 `completed/` 로 옮기며
마무리하는 커밋에서는 `active/` 에 스테이징된 것이 없으므로 경고가 뜬다 — **계획서를 가장 성실히
갱신한 커밋(회고까지 씀)에서 게이트가 정반대로 발화한다.** 마지막 active 계획을 옮기면 `active/`
가 비어 `R-plan-missing` 까지 함께 오발화한다.

실측(2026-09-18):
- `.harness/gate-events.jsonl` R-plan-stale 판정 85건 중 warn 42(49%).
- 2026-09-01 이후 88커밋 중 완료 계획서(A/R → `completed/`)와 작업 코드를 함께 담은 커밋 13건(15%).
  이 세션의 최근 커밋 4건(c5d1ee0·c9ddc38·280d36b·25c1ba0)이 모두 그 경우였고 매번 경고를 무시했다 —
  무시가 습관이 되면 경고 채널이 죽는다(core-beliefs R-plan-stale 절이 우려한 그 상황).

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — `git mv active/x.md completed/x.md` + 작업 코드 커밋에서 R-plan-stale·R-plan-missing 둘 다 발화하지 않는다
  — 검증: `tests/plan-stale-completion-test.sh` (a)
- [x] 목표 2 — `completed/` 에 새 계획서를 바로 추가(A)하는 커밋도 같다 — 검증: 같은 테스트 (b)
- [x] 목표 3 — 예외가 우회로가 되지 않는다: 이미 있던 `completed/*.md` 를 **수정(M)** 만 하고 코드를 바꾸면
  여전히 경고한다 — 검증: 같은 테스트 (c)
- [x] 목표 4 — 완료 계획서 없이 코드만 바꾸면 기존과 같이 경고한다(회귀 없음) — 검증: 같은 테스트 (d) +
  `tests/harness-hooks-smoke.sh` 21·22 그대로 통과
- [x] 목표 5 — 게이트 이벤트에 pass 사유가 "완료 커밋" 으로 구분돼 남는다 — 검증: 테스트 (a) 에서 `gate-events.jsonl` grep

## 3. 비목표 (Out of Scope)

- `R-retro` 판정 변경 — 완료 커밋의 회고 유무는 그쪽이 계속 본다. 여기서는 "계획서가 따라왔는가" 만 인정.
- 차단으로 승격 — 경고 유지.
- 소우주 재전파 — 사용자 지시 시.

## 4. 영향 영역

- 코드: `assets/hooks/pre-commit.sh` §8 — `completed/` 로의 A/R 스테이징을 "계획서가 따라왔다" 로 인정
- **신규 파일 목록**:
  - `tests/plan-stale-completion-test.sh` — 완료 커밋 4사례(이동·신규·수정만·코드만)에서 두 게이트의 발화 여부를 임시 저장소로 실측
- 룰: R-plan-stale · R-plan-missing (core-beliefs 절에 예외 한 문단 추가)
- 데이터: 없음
- 외부 의존: 없음

## 5. 단계 (Steps)

### Step 1. 테스트 먼저 (RED) [단순]
- 산출: `tests/plan-stale-completion-test.sh`, `run-all.sh` 등록
- 검증: (a)(b) 빨강, (c)(d) 초록

### Step 2. 게이트 수정 (GREEN) [단순]
- 산출: pre-commit §8 에 `COMPLETED_STAGED` 판정 추가, core-beliefs 절 보강
- 검증: 전용 테스트 전부 초록 + 스모크 21·22 통과 + 전체 스위트

### Step 3. 라이브 복사본 갱신·backlog 정리 [단순]

## 6. 의사결정 로그

- 2026-09-18: A/R 만 인정하고 M 은 인정하지 않는다 — 근거: R-retro 와 같은 경계("completed/ 로 옮기는 행위가 완료 선언").
  옛 완료 계획서의 오타 수정이 코드 커밋의 면죄부가 되면 안 된다.
- 2026-09-18: R-plan-missing 도 같은 예외를 받는다 — 근거: 마지막 active 계획을 옮기는 커밋이 "계획 없음" 으로 찍히는
  것은 같은 맹점의 다른 얼굴이다.

## 7. 발견·예외

- 테스트 격리: 전체 설치 대신 `pre-commit.sh`·`plan_state.py`·`gate_emit.sh`·`gate_event.py` 4개만 복사한 임시 저장소로
  충분했다(실행 수 초). 게이트 판정 테스트의 표준 형태로 쓸 만하다.
- 라이브 복사본 갱신 중 `scripts/hooks/pre-commit.sh` 를 실수로 만들었다(원래 없는 경로) — 즉시 제거. pre-commit 의
  라이브 자리는 `.git/hooks/pre-commit` 하나다.
- 스모크 21·22 는 손대지 않고 그대로 통과(113/113) — 기존 경고 경로에 회귀 없음.

## 8. 회고 (완료 시 작성)

- 잘된 것: RED 가 정확히 a·a2·b 세 경우에서만 났고 c·d 는 처음부터 초록 — 예외 경계가 의도대로 좁다.
  이벤트 사유("완료 커밋")를 따로 남겨 발화율 보고에서 정당 통과와 구분된다.
- 잘못된 것: 이 맹점을 2026-09-08 에 적어 두고 열흘간 커밋 4건에서 경고를 무시했다. 무시가 쌓이기 전에 고쳤어야 했다.
- 다음 룰 후보: "경고를 같은 사유로 3회 무시하면 그 게이트의 판정을 고치는 작업을 backlog 가 아니라 active 로 올린다".
  `gate_report.py` 의 warn 연속 횟수로 잴 수 있다.
