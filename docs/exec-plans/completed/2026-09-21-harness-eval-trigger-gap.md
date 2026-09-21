# 2026-09-21-harness-eval-trigger-gap — 규칙을 바꾸면 harness-eval 을 돌릴 때라고 알린다

> 출처: backlog `harness-eval-trigger-gap` — 2026-09-21 반대 심문(devil-advocate) 시험 1에서 반증 조건을 돌려 세 건 모두 성립 확인. 같은 날 사용자 "진행하자".

## 1. 동기 (Why)

harness-eval 을 만든 이유가 "규칙이 실제로 작동하는지 잰 적이 없어 두 달 몰랐다" 였다. 그런데 그 도구도 **아무것에도 불리지 않는다** — 사람이 기억해서 돌려야만 돈다.
원인이던 사각지대(사람의 기억에 기댐)를 새 도구가 그대로 물려받았다. 게다가 착수하며 확인해 보니 **마지막 실행 기록마저 사라졌다**(아래 §2-bis).

R3 는 "게이트 안에서 모델을 부르지 않는다" 이지 "알리지도 않는다" 가 아니다. 돌리는 것은 사람, **돌릴 때가 됐다고 알리는 것**은 기계가 할 수 있다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 규칙·강제 파일이 스테이징된 공장 커밋에서 **R-eval 경고**가 뜬다(차단 아님). 마지막 실행이 며칠 전인지(또는 기록 없음)와 돌릴 명령을 함께 준다. 검증: `bash tests/eval-reminder-test.sh` 의 [b][c].
- [x] 목표 2 — 소우주·무관 파일에서는 **조용하다**. 검증: 같은 시험 [a][d] (harness-eval 이 없는 저장소 · 무관 파일만 스테이징).
- [x] 목표 3 — 평가를 돌리면 직전 실행보다 `attempt_rate` 가 **오른** 칸을 표 위에 알린다. 검증: `bash tests/harness-eval-test.sh` 의 drift 절.
- [x] 목표 4 — 설계 문서의 비용 산식이 실제 기본값과 맞는다. 검증: `grep -c '1,890' docs/design-docs/agent-eval-llm-path.md` ≥ 1 (시나리오 7 × 3 × k3 = 63 호출/회 — 반론이 쓴 54·1,620 은 시나리오 6 시절 값).

## 2-bis. 착수 전 확인한 사실 (2026-09-21)

| 확인한 것 | 결과 |
| --------- | ---- |
| 룰 변경 시 평가를 부르는 장치 | **0곳** — `pre-commit.sh`·리마인더 훅·스킬 어디에도 `harness-eval` 호출·언급 없음 |
| 마지막 실행 기록 `.harness/evals/` | **폴더가 없다.** 9-20 첫 실측 결과(`2026-09-20_201344.json`)가 계획서에 인용돼 있으나 파일은 사라졌다. `.harness/` 는 git 무시 경로 |
| harness-eval 배포 범위 | **공장 전용** — `presets/`·`lib/` 어디에도 복사 목록 없음. 소우주에는 `scripts/harness-eval.py` 가 없다 |
| 시나리오 | 7개(`tests/agent-evals/*.json`) — 9-20 이후 `soul-self-approve` 추가 |
| 트리거 경로의 커밋 빈도 | 최근 30일 186 커밋 중 **25(13%)** 가 `assets/rules/`·`assets/hooks/claude-pretooluse-*`·`assets/skills/hermes-agent/`·`tests/agent-evals/` 를 건드림 |
| `attempt_rate` 비교 | `harness_eval_grade.summarize` 가 계산만 한다. 임계·비교·경고 0 |
| 러너 기본값 | `--k 3` · 단계 3 → 시나리오 7 × 3 × 3 = **63 호출/회** |

## 3. 비목표 (Out of Scope)

- **게이트가 평가를 돌리는 것** — R3·크레딧. 알리기만 한다.
- 차단 — 평가를 안 돌렸다고 커밋을 막지 않는다. 13% 빈도로 막으면 꺼진다.
- 결과를 git 추적 파일로 옮기는 것 — 기록이 사라지면 경고가 "기록 없음" 으로 뜬다(안전한 쪽). 사라진 원인 조사는 별건.
- 소우주 배포 — harness-eval 자체가 공장 전용이다.

## 4. 영향 영역

- 코드: `assets/hooks/pre-commit.sh`(R-eval 블록) · `scripts/harness_eval_grade.py`(`attempt_drift`) · `scripts/harness-eval.py`(직전 결과 비교 출력) · `tests/harness-eval-test.sh`(drift 절) · `tests/run-all.sh`
- **신규 파일 목록**:
  - `tests/eval-reminder-test.sh` — R-eval 경고가 뜨는 조건·안 뜨는 조건을 설치된 픽스처의 pre-commit 으로 가른다
- 룰: `docs/design-docs/core-beliefs.md` 에 `R-eval` 절(경고). 게이트 선언 `# GATE: R-eval warn`.
- 문서: `docs/design-docs/agent-eval-llm-path.md` 비용 산식.
- 데이터·외부 의존: 없음.

## 5. 단계 (Steps)

### Step 1. pre-commit R-eval 블록 [Impl] — `scripts/harness-eval.py` 가 있을 때만 판정(공장 표식)
### Step 2. attempt_rate drift [Impl] — grade 에 순수 함수, 러너는 직전 결과 파일을 읽어 넘긴다
### Step 3. 설계 문서 산식 갱신 [단순]
### Step 4. 시험 → 전체 → 커밋 [검증] — 새 시험은 고치기 전 상태에서 빨간지 확인

## 6. 의사결정 로그

- 2026-09-21: 판정기를 새 파일로 만들지 않고 pre-commit 안 **몇 줄 bash** 로 둔다 — 근거: 공장 전용이라 소우주 배포 배선이 필요 없고, 새 판정기 배선 누락이 오늘까지 2회 있었다.
- 2026-09-21: 공장 판별은 `scripts/harness-eval.py` 존재로 한다 — 근거: 이 경고가 가리키는 명령 그 자체라, 명령이 없는 곳에서 명령을 권하지 않게 된다.

## 7. 발견·예외

- **마지막 실행 기록이 사라져 있었다.** 9-20 첫 실측 결과 파일이 계획서에 인용돼 있지만 `.harness/evals/` 자체가 없다.
  git 무시 경로라 무엇이 지웠는지 추적할 수 없다. 경고는 이 상태를 "기록 없음" 으로 보여준다(안전한 쪽).
- **반론의 숫자도 낡았다.** 반대 심문이 쓴 54회/월 1,620 은 시나리오 6개 시절 값이고, 지금은 7개라 63회/월 1,890(크레딧 약 86%)이다.
  반론의 방향(산식이 낙관적)은 맞고 크기는 더 컸다. 반증을 돌릴 때 반론의 숫자도 다시 재야 한다.
- **시험 비용을 내가 늘렸다.** 러너는 부를 때마다 `project-claude.sh` 로 픽스처를 통째로 설치한다. 5절을 처음에 러너 3회로 짜서
  전체 시험이 600초를 넘겼다. 직전 결과를 파일로 심고 러너를 1회로 줄였다(harness-eval 시험 단독 78.6초, 31/31).
- **관측 규칙에 한 번 걸렸다.** 새 게이트가 `warn` 만 기록하고 `pass`·`skipped` 를 안 남겨 `gate-declaration-coverage-test` 가 빨갰다 —
  분모 없는 게이트는 발화율을 낼 수 없다. R-config 때는 지켰는데 이번엔 놓쳤다.
- 문서 개수 동기화를 시험 등록 **전**에 돌려 `doc-counts-gate-test` 가 빨갰다. 동기화는 등록 뒤 마지막에.

## 8. 회고 (완료 시 작성)

- 잘된 것: 새 시험을 먼저 쓰고 빨간 것을 확인한 뒤 구현했다(R-eval 6건 빨강 → 8/8, drift 3건 빨강 → 통과). 판정기 파일을 새로 만들지 않고
  pre-commit 안 몇 줄로 둬서, 오늘 두 번 있었던 "설치 배선 누락" 이 원천적으로 생길 수 없게 했다.
- 잘못된 것: 게이트 하나를 추가하며 기존 게이트 관례(pass/skipped 기록)를 따라 하지 않았고, 시험 하나를 추가하며 비용(픽스처 설치)을 재지 않았다.
  둘 다 전체 시험이 잡았지만, 전체 시험이 600초를 넘겨 확인이 두 바퀴 걸렸다.
- 다음 룰 후보: "새 게이트는 warn·pass·skipped 세 상태를 모두 기록한다" — 이미 `gate-declaration-coverage-test` 가 강제한다. 룰 승격 불필요, 관례를 먼저 보면 된다.
