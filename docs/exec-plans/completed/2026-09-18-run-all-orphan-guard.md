# 2026-09-18-run-all-orphan-guard — run-all.sh 고아 테스트 검사

> 출처: `docs/exec-plans/backlog/run-all-orphan-test-guard.md` (본 계획으로 승격, backlog 파일 삭제)
> 상위 출처: `completed/2026-09-03-r5-false-positive.md` §7·§8
> 설계 결정 인용: 없음 — 테스트 러너 내부 검사. 원장 결정과 무관.

## 1. 동기 (Why)

`tests/run-all.sh` 는 실행할 테스트를 **명시 목록**으로 갖는다. 새 테스트 파일을 만들고
목록에 넣지 않으면 그 테스트는 한 번도 실행되지 않는다. 2026-09-03 에 한 세션이 만든
테스트 6개가 전부 미등록 상태였던 것을 우연히 발견했다(`gate-event`·`gate-report`·
`gate-instrumentation`·`gate-precommit-instrumentation`·`mutation-trigger`·`r5-detection`).
같은 형태의 **조용한 건너뜀**(R-test 가 0개로 통과, pre-commit 이 `.review-dirty` 미독 등)이
이 저장소의 반복 결함이다.

착수 시점 실측(2026-09-18): `tests/` 의 `*-test.sh`·`*smoke*.sh` 71개(preset-integrity 포함)
중 고아 0 · 목록에 있으나 파일 없음 0. 즉 지금은 깨끗하지만 지키는 장치가 없었다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — `tests/*-test.sh`·`*smoke*.sh` 중 러너 목록에 없는 파일이 있으면 run-all 이 **실패**한다
  — 검증: 사본 러너에 가짜 `zzz-orphan-test.sh`·`zzz-smoke.sh` 를 심고 `--check-orphans` rc 1 + 이름 보고
- [x] 목표 2 — 목록에 있으나 파일이 없어도 실패한다 — 검증: 사본에서 `hermes-roster-test.sh` 삭제 → rc 1
- [x] 목표 3 — 의도적 제외는 침묵이 아니라 `SKIP_TESTS` 명시로만 가능하다 — 검증: `SKIP_TESTS=zzz-orphan-test.sh` 로 rc 0
- [x] 목표 4 — 검사가 전체 실행 경로의 첫 단계로 돈다 — 검증: `run_step "고아 테스트 검사" orphan_test_check` 존재 + 전체 스위트 통과
- [x] 목표 5 — 실 저장소는 고아 0 · 결손 0 — 검증: `bash tests/run-all.sh --check-orphans` rc 0

## 3. 비목표 (Out of Scope)

- `tests/fixtures/`·하위 디렉터리의 셸 파일(테스트가 아니라 재료) — `-maxdepth 1` 로 제외
- `run-all.sh` 자체를 `*-test.sh` 로 취급하는 것 (이름 규약상 해당 없음)
- 소우주 전파(러너는 우주 전용, `presets/` 복사 목록에 없음)

## 4. 영향 영역

- 코드: `tests/run-all.sh` — 실행 목록을 `REGISTERED_TESTS` 배열로 승격, `INTEGRITY_TESTS`(§2 개별 실행분),
  `orphan_test_check` 함수, `--check-orphans` 단독 실행 옵션, 첫 `run_step` 으로 등록
- **신규 파일 목록**:
  - `tests/run-all-orphan-guard-test.sh` — 고아 검사가 실제로 빨강을 내는지 사본 러너로 검증(가짜 고아·결손·명시 스킵·smoke 패턴)
- 룰: 없음 (러너 내부 정적 검사. 승격 후보는 §8)
- 데이터: 없음
- 외부 의존: 없음

## 5. 단계 (Steps)

### Step 1. 테스트 먼저 (RED) [단순]
- 산출: `tests/run-all-orphan-guard-test.sh` 10 단언
- 검증: 옵션 없는 러너를 그대로 돌려 전체 스위트가 시작됨(빨강 대신 멈춤 — §7)

### Step 2. 러너 구현 (GREEN) [단순]
- 산출: `REGISTERED_TESTS` 배열 + `orphan_test_check` + `--check-orphans`
- 검증: `--check-orphans` → "고아 테스트 0 · 결손 0 (등록 71개)" rc 0; 가드 테스트 10/10

### Step 3. 전체 스위트 + backlog 정리 [단순]
- 검증: `bash tests/run-all.sh` 전체 초록(실행 수 +1 = 고아 검사 단계, 테스트 +1)

## 6. 의사결정 로그

- 2026-09-18: 목록을 `for t in \` 나열에서 `REGISTERED_TESTS=( )` 배열로 바꿈 — 근거: 검사 함수가 같은 자료를
  읽어야 목록과 검사가 어긋나지 않는다(목록을 두 벌 두면 두 번째 조용한 건너뜀이 생긴다).
- 2026-09-18: `preset-integrity-test.sh` 는 §2 무결성 단계에서 개별 실행되므로 `INTEGRITY_TESTS` 로 따로 인정 —
  근거: 실행 순서를 바꾸지 않으면서 고아로 오판하지 않게.
- 2026-09-18: 결손(목록에 있으나 파일 없음)도 같은 검사에서 실패 — 근거: 러너가 "파일 없음" 으로 FAIL 을 내긴 하지만
  원인이 이름 오타인지 삭제인지 첫 단계에서 한 번에 보여야 한다.
- 2026-09-18: 검사를 §1 첫 단계로 둠 — 근거: 고아가 있으면 뒤 결과 전체가 불완전하다는 뜻이라 가장 먼저 알려야 한다.

## 7. 발견·예외

- 테스트를 먼저 쓰고 돌렸을 때 `--check-orphans` 를 모르는 옛 러너가 인수를 무시하고 전체 스위트를 시작해
  300초 타임아웃으로 백그라운드로 넘어갔다. RED 확인은 "옵션 미인식 → 전체 실행" 이라는 형태로 나왔다.
  교훈: 러너에 옵션을 넣는 테스트는 RED 단계에서 `grep` 정적 단언부터 돌리는 편이 싸다.
- 첫 실행 1건 실패는 테스트 정규식이 통과 메시지("✓ 고아 테스트 0")까지 셈. `✗` 만 세도록 고침.

- 전체 스위트 첫 실행에서 `design-cover-gate-test.sh` 가 실패했다(기존 결함, 본 변경과 무관): 기준선 항목이 0이 된
  280d36b 이후 `design_cover.py baseline` 이 빈 줄 하나를 더 내고, 커밋 시 포맷터가 파일 끝 빈 줄을 지워 diff 1줄.
  판정기가 틈 0일 때 빈 줄을 내지 않도록 고쳤다(`assets/hooks/design_cover.py`). 20/20.

## 8. 회고 (완료 시 작성)

- 잘된 것: 가짜 고아·가짜 결손·명시 스킵·smoke 패턴 네 경로 모두 실제 rc 로 확인. 배열 단일화로 목록 이중화 회피.
- 잘못된 것: RED 를 전체 러너 실행으로 확인하려다 5분 낭비.
- 다음 룰 후보: "명시 목록형 러너/설치 목록은 디렉터리 실측과 대조하는 검사를 함께 둔다" —
  `presets/*.conf` 복사 목록(이미 install-closure-test 가 담당)과 같은 계열. 3회 반복 시 R 룰 승격.
