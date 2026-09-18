# 2026-09-18-mutation-probe-pyc — mutation-probe 복원 시 stale `.pyc` 무효화

> 출처: `docs/exec-plans/backlog/mutation-probe-pyc-invalidation.md` (본 계획으로 승격, backlog 파일 삭제)
> 상위 출처: `completed/2026-09-03-gate-telemetry.md` §7
> 설계 결정 인용: 없음 — 도구의 복원 안전 요건(R-mut) 보강. 원장 결정과 무관.

## 1. 동기 (Why)

`scripts/mutation-probe.py` 는 변이 → 테스트 → 복원을 같은 초 안에 한다. 변이가 파일 크기를 바꾸지
않으면(`==`→`!=` 등) CPython 의 pyc 검증(mtime 초 + size)이 통과해 **원본 바이트코드가 변이본 대신
실행되거나(가짜 생존), 변이본 바이트코드가 복원 후에도 재사용된다(테스트 오염, 2026-09-03 관측).**
당시 우회는 해당 테스트에 `python3 -B` 를 붙이는 것 — 테스트마다 기억해야 하는 규율이라 샌다.

실측(2026-09-18): 원본 pyc 생성 → 같은 크기 변이 + 같은 mtime → `import m; m.f(1,1)` 이 `True`(원본 결과).
이 세션 셸은 `PYTHONDONTWRITEBYTECODE=1` 이라 평소엔 안 보이지만, 도구는 환경에 기대면 안 된다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — `_Guard.write()`·`restore()` 뒤에는 대상의 `__pycache__/<stem>.*.pyc` 가 남지 않는다
  — 검증: `tests/mutation-probe-test.sh` "pyc 무효화" 절 (Guard 단위)
- [x] 목표 2 — 탐침 실행 전체 뒤 `import` 결과가 원본과 같다(변이본 pyc 잔존 없음) — 검증: 같은 절 (엔드투엔드,
  `env -u PYTHONDONTWRITEBYTECODE`)
- [x] 목표 3 — 시그널 복원 경로도 같은 무효화를 거친다 — 검증: `restore()` 한 곳에 넣어 세 경로(finally/시그널/종료 대조)가 공유

## 3. 비목표 (Out of Scope)

- 소우주 전파 — 도구는 복사 목록에 없다(훅만 전파되고 도구는 프로젝트 소유).
- `python3 -B` 우회를 쓴 기존 테스트의 되돌리기 — 무해하므로 그대로 둔다.

## 4. 영향 영역

- 코드: `scripts/mutation-probe.py` `_Guard` — `_purge_pyc()` 를 `write()`·`restore()` 에서 호출
- **신규 파일 목록**: 없음 (`tests/mutation-probe-test.sh` 에 절 추가)
- 룰: R-mut (core-beliefs 절에 한 줄)
- 데이터: 없음

## 5. 단계 (Steps)

### Step 1. RED — 테스트 절 추가 [단순]
### Step 2. GREEN — `_purge_pyc` [단순]
### Step 3. 전체 스위트·backlog 정리 [단순]

## 6. 의사결정 로그

- 2026-09-18: 무효화를 `write()` 에도 넣는다(복원만이 아니라) — 근거: 변이 직후 원본 pyc 가 재사용되면
  변이가 "생존" 으로 오판된다. 대칭적 문제라 한 함수로 양쪽을 막는다.
- 2026-09-18: `importlib.util.cache_from_source` 로 경로를 구하고 같은 stem 의 다른 태그(`.opt-1.pyc` 등)도 glob 으로 지운다
  — 근거: 최적화 수준별 pyc 가 따로 있고, 어느 것이 재사용될지 도구는 모른다.

## 7. 발견·예외

- 이 셸 환경은 `PYTHONDONTWRITEBYTECODE=1` 이라 첫 재현이 실패했다(pyc 자체가 안 생김). 테스트는 `env -u` 로 벗긴다 —
  환경이 결함을 가리는 사례. 다른 세션·소우주에서는 pyc 가 생긴다.
- RED 에서 "복원 뒤 import 가 원본을 본다" 는 우연히 통과했다(원본 pyc 가 계속 재사용돼 결과만 맞음). 통과 이유가 틀린
  단언은 앞의 두 단언(write/restore 뒤 pyc 0)이 잡는다.

## 8. 회고 (완료 시 작성)

- 잘된 것: 가짜 생존(변이 직후 원본 pyc 실행)을 실측으로 잡았다 — backlog 는 복원 오염만 적었는데 대칭 결함이 하나 더 있었다.
- 잘못된 것: 2026-09-03 에 `python3 -B` 우회로 덮고 보름을 뒀다.
- 다음 룰 후보: "환경변수로만 막히는 결함은 결함이다 — 테스트는 그 변수를 벗기고 잰다"(`env -u`). 3회 반복 시 승격.
