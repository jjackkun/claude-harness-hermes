# 2026-09-08-resolve-gate-warnings — 커밋마다 뜨던 경고 세 건을 없앤다

## 1. 동기 (Why)

`62cff80` 커밋에서 경고 세 건이 함께 떴다. 셋 다 오늘 처음이 아니라 **여러 커밋에서
반복**된 것이고, 반복되는 경고는 무시되기 시작한다 — 오늘 세션에서 `R-plan-stale` 이
커밋 4건 전부에서 발화하고 4번 다 그냥 지나간 것이 그 증거다.

1. `[R-dep-4] assets/hooks/doc_counts.py — 계약(.deprc)에 tier 가 없다.`
2. `[R-test] 스테이징된 .py 가 있으나 수집된 테스트가 0개다.`
   실측: `PYTEST_DIR=tests` 로 잡히는데 `tests/` 에는 `.sh` 만 있어 수집이 0이다.
   `.py` 판정 모듈들은 bash 통합 시험으로만 검증돼 왔고 단위 시험이 하나도 없다.
3. `[R-plan-stale] 코드는 바뀌었는데 계획서가 따라오지 않음.`
   `docs/exec-plans/active/2026-09-03-gate-telemetry.md` 의 **목표 4 가 미완**으로 남아
   active/ 에 계속 머물러 있기 때문이다.

목표 4 는 "R-plan-missing 이 실제로 발화하는지 답한다" 인데, 답할 수 없었던 이유가
오늘 드러났다: **`R-plan-missing` 과 `R-plan-stale` 은 `gate_add` 계장이 아예 없다.**
`gate_report.py` 출력에 두 룰이 등장하지 않는다 — 화면에는 경고를 찍으면서 발화 기록은
남기지 않는다. 계장 없는 게이트는 발화율로 승격·강등을 판단할 수 없다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — R-dep-4 가 사라진다. (tier 0 등재, depcheck 출력 없음 확인)
      검증: `python3 assets/hooks/depcheck.py assets/hooks/doc_counts.py` 출력 없음.
- [x] 목표 2 — `R-plan-missing`·`R-plan-stale` 이 발화를 기록한다. (세 분기 전부 계장, pass 포함)
      검증: 커밋 후 `gate_report.py` 표에 두 룰의 행이 나타난다.
- [x] 목표 3 — 답변 기록 완료: `docs/audits/2026-09-08-plan-gate-firing.md`. 판정은 '무발화'도 '제외 범위 과대'도 아닌 **계장 부재**.
      검증: 감사 문서가 존재하고, "무발화" 인지 "제외 범위 과대" 인지 판정이 적혀 있다.
- [x] 목표 4 — `pytest tests -q` 8개 수집·통과. 파싱을 일부러 깨자 해당 시험이 실패해 회귀를 실제로 잡음을 확인.
      검증: `pytest tests -q` 가 1개 이상 수집·통과하고, 커밋 시 R-test 경고가 없다.
- [x] 목표 5 — 전체 시험 통과. 검증: `bash tests/run-all.sh` 47+ 통과 / 0 실패.

## 3. 비목표 (Out of Scope)

- **나머지 미계장 게이트 6종(R-acc · R-cov · R-fmt · R-lint · R-struct · R-test)은
  이번에 계장하지 않는다.** 목표 4 를 답하는 데 필요한 것은 계획 축 두 개뿐이고,
  6종을 한꺼번에 건드리면 이 작업이 "게이트 전수 계장" 으로 번진다.
  backlog 에 남겨 별도로 다룬다.
- 파이썬 단위 시험을 `.py` 판정 모듈 전체로 넓히지 않는다. R-test 를 되살리는 데
  필요한 최소는 실제로 틀릴 수 있는 경로 하나이고, 그것이 `doc_counts.py` 의 파싱이다.
  빈 테스트로 경고만 끄면 게이트가 죽은 채 통과 표시를 낸다.

## 4. 영향 영역

- 코드: `.deprc` (tier 등재), `assets/hooks/pre-commit.sh` + `scripts/hooks/pre-commit.sh`
  (계획 축 2종 `gate_add` 계장)
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `tests/test_doc_counts.py` — `doc_counts.py` 의 배열 파싱 계약이 조용히 틀리지
    않는지 단언한다 (이 게이트 전체가 딛고 선 지점이므로 여기만 단위 시험한다).
  - `docs/audits/2026-09-08-plan-gate-firing.md` — 계획 축 게이트(R-plan-missing /
    R-plan-stale)가 실제로 발화하는지에 대한 판정과 근거를 남긴다.
- 룰: 신설 없음. 기존 R-dep · R-test · R-plan-stale 의 위반 해소.
- 데이터: 없음.
- 외부 의존: `pytest` — 이미 R-test 가 찾는 도구이고 새로 들이는 것이 아니다.

## 5. 단계 (Steps)

### Step 1. `.deprc` 에 tier 등재 [단순]

- 산출: `doc_counts.py` → tier 0 (표준 라이브러리만 쓰는 잎 모듈)
- 검증: 목표 1

### Step 2. 계획 축 게이트 계장 [Impl]

- 산출: `gate_add R-plan-missing|R-plan-stale warn|pass` 를 세 분기 전부에 배치
- 검증: 목표 2. 통과(pass)도 기록해야 발화율의 **분모**가 생긴다.

### Step 3. 판정과 기록 [단순]

- 산출: `docs/audits/2026-09-08-plan-gate-firing.md`
- 검증: 목표 3. gate-telemetry 계획의 목표 4 체크 후 `completed/` 로 이동.

### Step 4. `doc_counts.py` 단위 시험 [Impl]

- 산출: `tests/test_doc_counts.py`
- 검증: 목표 4·5

## 6. 의사결정 로그

- 2026-09-08: 경고를 "무시해도 되는 것" 으로 두지 않고 없애기로 한다 — 근거: 반복되는
  경고는 채널 전체를 무디게 만든다. 오늘 `R-plan-stale` 이 4번 발화하고 4번 무시됐다.
- 2026-09-08: `R-plan-missing`·`R-plan-stale` 에 **pass 도 기록**한다 — 근거: 차단만
  기록하면 발화율의 분모가 없어 "안 걸렸다" 와 "판정하지 않았다" 가 구분되지 않는다.
- 2026-09-08: 미계장 6종은 backlog 로 미룬다 — 근거: 비목표 참조.
- 2026-09-08: R-test 를 빈 테스트로 끄지 않고 실제로 틀릴 수 있는 경로를 시험한다 —
  근거: `R-test` 가 몇 달간 "수집 0개" 로 조용히 통과하던 것이 이 저장소의 실제 사고다.

## 7. 발견·예외

- **R-iface 가 `tests/test_doc_counts.py` 생성을 막았다** (공개 심볼 8, 은닉 0%).
  pytest 는 `test_` 로 시작하는 **공개** 함수만 수집하므로 밑줄로 감출 수 없다.
  8개가 지는 책임은 하나다 — `doc_counts.py` 의 파싱 계약. 룰이 정한 절차대로
  파일 상단에 `R-iface-waiver` 근거를 남기고 진행한다. 우회가 아니라 룰이 명시한 경로다.

## 8. 회고

경고 세 건을 없애려다 **게이트 16종 중 8종이 발화 기록을 남기지 않는다**는 것을
찾았다. 경고를 "무시해도 되는 잡음" 으로 두지 않고 원인까지 파고든 것이 값을 했다.

R-iface 가 pytest 파일 생성을 막은 것은 룰이 제대로 동작한 사례다. 우회하지 않고
룰이 명시한 waiver 절차(근거를 파일 상단에 남기기)를 따랐다 — 근거를 적게 만드는
것이 이 waiver 의 목적이고, 실제로 적으면서 "이 8개가 지는 책임은 하나" 임을
스스로 확인하게 된다.

R-test 를 빈 테스트로 끄지 않은 것도 중요하다. 파싱을 일부러 깨서 시험이 실패하는
것을 확인했다 — 통과만 보는 검증은 게이트가 죽은 것을 못 잡는다.
