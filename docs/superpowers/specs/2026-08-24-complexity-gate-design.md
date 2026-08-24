# R-cx — 순환 복잡도 게이트

> 작성일: 2026-08-24
> 목적: "파일이 몇 줄인가" 외에 "함수가 얼마나 꼬였는가"를 재는 축을 하네스에 추가한다.

## 개요

현재 하네스에는 **복잡도를 재는 장치가 하나도 없다.** `radon`·`mutmut`·cyclomatic·CRAP
전 항목 검색 결과 0건이고, ESLint 설정(`assets/lint-configs/eslint/`)에도 `max-lines` 만 있고
`complexity`·`max-depth`·`max-params` 룰이 없다.

즉 `R-size` 는 파일 크기만 본다. **500줄 한도를 지키면서 순환 복잡도 48 짜리 함수를 쓰는 것은
지금 완전히 통과한다.** 실제로 이 저장소에 그런 함수가 두 개 있다.

## 문제 — 실측

AST 기반 순환 복잡도 측정(2026-08-24, `scripts/`·`lib/`·`assets/hooks/` 의 파이썬 함수 295개).

### 상위 위반

| 복잡도 | 위치 |
|---|---|
| 48 | `scripts/hermes-search.py:330` `main` |
| 48 | `lib/generate_settings_json.py:145` `main` |
| 27 | `scripts/hermes_save_session_patterns.py:82` `extract_patterns` |
| 19 | `scripts/hermes-loop.py:83` `_drive` |
| 17 | `scripts/hermes_save_session_signals.py:82` `detect_objective_signals` |
| 16 | `scripts/hermes_skills.py:29` `extract_keywords` |
| 16 | `scripts/hermes_loop.py:167` `read_goal_md` |
| 16 | `scripts/hermes-correlate.py:52` `session_tool_tokens` |

### 전체 분포

```text
복잡도: 1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  19  27  48
함수수: 61  38  34  31  30  19  14  14  13  10  11   4   4   2   2   3   1   1   1   2
```

누적: 복잡도 11 이하가 275개(93%), 12 이상이 20개(7%).

**그러나 게이트는 파일 단위로 차단한다.** 위반 함수 20개는 16개 파일에 흩어져 있고,
대상 파일 37개 중 **16개(43%)** 가 임계 12 에서 즉시 차단된다.

| 파일 최대 복잡도 | 파일 |
|---|---|
| 48 | `lib/generate_settings_json.py`, `scripts/hermes-search.py` |
| 27 | `scripts/hermes_save_session_patterns.py` |
| 19 | `scripts/hermes-loop.py` |
| 17 | `scripts/hermes_save_session_signals.py` |
| 16 | `scripts/hermes-correlate.py`, `scripts/hermes_loop.py`, `scripts/hermes_skills.py` |
| 15 | `scripts/hermes-cleanup.py`, `scripts/hermes-export-history.py` |
| 14 | `lib/generate_codex_hooks.py` |
| 13 | `assets/hooks/plan_state.py`, `scripts/hermes-dream.py`, `scripts/hermes-lifecycle.py`, `scripts/hermes-reindex.py` |
| 12 | `scripts/hermes_lifecycle_apply.py` |

"함수의 7%" 와 "파일의 43%" 는 도입 판단이 갈리는 차이다. 아래 도입 전략이 여기서 나온다.

## 설계

### 임계값 12

**근거는 분포의 절벽이다.** 함수 수가 `11:11개 → 12:4개` 로 급락한다.
1~11 구간은 10~61개로 두텁게 이어지다가 12 에서 4개로 끊긴다.
임계를 이 절벽에 놓으면 정상 코드의 대다수를 건드리지 않으면서 이상치만 잡는다.

**영상(로버트 마틴)의 권고 6~8 을 그대로 쓰지 않는 이유**:
그 값은 CRAP 스코어 기준이고 여기서 잰 것은 순환 복잡도 단독이라 **척도가 다르다.**
또한 이 저장소 실측에서 그 구간은 과발화한다 —
임계 8 이면 68개(23%), 임계 6 이면 101개(34%) 가 걸린다.
임계는 남의 숫자가 아니라 우리 분포에서 나와야 한다.

**단계적 하향**: 12 로 시작해 위반 20개를 정리한 뒤,
분포를 다시 재서 다음 절벽으로 내린다. 처음부터 낮게 잡아 20% 를 막으면 우회가 상시화된다.

### 도입 전략 — 라쳇(ratchet)

임계 12 를 일괄 적용하면 파일의 43% 가 막힌다. 그 상태로 켜면
게이트를 끄거나 `--no-verify` 로 우회하는 것이 정상 작업 흐름이 된다.

대신 **파일별 기준선을 동결하고, 나빠질 때만 차단한다.**

| 대상 | 임계 |
|---|---|
| 기준선에 없는 파일 (신규·정상) | **12** |
| 기준선에 있는 파일 | **그 파일의 현재 최대값** |

`.cxbaseline` 에 위 표의 16개 파일과 현재 최대값을 기록한다.
`hermes-search.py` 는 48 을 넘으면 차단되고, 47 로 줄이면 기준선이 함께 내려간다.

**기준선은 내려가기만 한다.** 값이 개선되면 자동으로 갱신하고,
악화되면 차단한다. 리팩터링을 강제하지 않으면서 후퇴를 막는다.

기준선 파일이 비면 전부 임계 12 가 적용된다 — 새 프로젝트의 기본 동작이다.

### 대상과 발화

| 항목 | 값 |
|---|---|
| 발화 지점 | `pre-commit` 의 신규 단계 `R-cx` |
| 대상 | 스테이징된 `.py` (`R-size` 의 `PY_FILES` 재사용) |
| 행동 | **차단** (기준선 초과 시) |
| 조정 | `.harnessrc` 의 `MAX_COMPLEXITY` (기본 12), `.cxbaseline` |

**차단하는 이유**: `R-iface` 와 달리 분포에 명확한 절벽이 있다.
간극이 있으므로 "그 아래는 안전"이라고 말할 근거가 있고, 따라서 차단이 성립한다.

### 측정 도구

`radon` 이 설치돼 있지 않다(2026-08-24 확인). 두 경로가 있다.

**경로 1 — `radon` 도입.** 표준 도구이고 CRAP 확장 경로가 열린다.
WSL 환경이므로 **설치는 사용자가 직접 수행해야 한다**:

```bash
pip install radon
```

**경로 2 — AST 자체 구현.** 파이썬 표준 `ast` 모듈만으로 계산한다.
외부 의존이 없어 설치 없이 어디서나 돈다. 본 스펙의 실측이 이 방식으로 이뤄졌다.

**경로 2 를 권장한다.** 하네스는 여러 프로젝트에 설치되는 도구이고,
각 프로젝트에 `radon` 설치를 요구하면 설치 실패가 곧 게이트 침묵이 된다.
`check-secrets.py`·`plan_state.py` 가 이미 표준 라이브러리만 쓰는 것과 같은 판단이다.

계산 규칙(McCabe 근사): `if`/`for`/`while`/`except`/`with`/`assert` 각 +1,
`and`/`or` 는 피연산자 수 -1, 조건 표현식 +1, 컴프리헨션 +1(내부 `if` 마다 추가 +1).

### JS/TS

ESLint `complexity` 룰을 `assets/lint-configs/eslint/` 에 추가하고 `R-lint` 가 흡수한다.
별도 단계를 만들지 않는다 — 이미 ESLint 를 도는 경로가 있다.

임계값은 파이썬과 별도로 산정한다. 이 저장소에는 측정할 JS 코드가 거의 없으므로,
**JS 임계는 실제 JS 프로젝트에서 분포를 재기 전까지 확정하지 않는다.**

## 검증

| 항목 | 방법 |
|---|---|
| 임계 동작 | 복잡도 12 함수 → 차단, 11 → 통과 |
| 계산 정확도 | 위 실측 표의 8개 함수를 재측정해 같은 값이 나오는지 |
| 라쳇 — 후퇴 차단 | `hermes-search.py` 를 49 로 만들면 차단 |
| 라쳇 — 개선 허용 | 47 로 줄이면 통과, 기준선이 47 로 갱신 |
| 라쳇 — 신규 파일 | 기준선에 없는 파일은 12 로 판정 |
| `.harnessrc` override | `MAX_COMPLEXITY=20` 설정 시 19 짜리 `_drive` 통과 |
| 파싱 실패 | 문법 오류 파일 → 조용히 통과(다른 게이트 관할), 크래시 없음 |

`tests/complexity-gate-test.sh` 를 추가한다.

## 미해결

1. **기준선 파일의 갱신 주체.** 값이 개선됐을 때 훅이 `.cxbaseline` 을 자동으로 고쳐 쓰면
   커밋에 포함되지 않은 변경이 워킹트리에 생긴다. 자동 갱신 / 경고 후 수동 갱신 중
   결정이 필요하다. 후자가 안전하나 마찰이 있다.
2. **`main()` 예외 여부.** 상위 2개가 모두 argparse 디스패치 `main` 이다.
   진입점의 분기는 성격이 다르다는 주장이 가능하나, 48 은 그 논리로도 방어되지 않는다.
   예외를 두지 않는 쪽으로 기울지만 실제 코드를 보고 판단한다.
