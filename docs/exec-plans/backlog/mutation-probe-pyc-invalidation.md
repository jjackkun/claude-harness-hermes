# mutation-probe 가 남기는 stale `.pyc` 무효화

> 출처: `docs/exec-plans/active/2026-09-03-gate-telemetry.md` §7 (Step 1 실행 중 발견)

## 문제

`scripts/mutation-probe.py` 는 대상 소스를 변이 → 테스트 → 복원한다. 이 세 동작이
**같은 초 안에** 일어나고 변이가 **파일 크기를 바꾸지 않으면**(`== → !=`, `< → <=` 등),
CPython 의 기본 pyc 검증(mtime 초 단위 + size)이 통과해 **변이본 바이트코드가
복원 후에도 재사용된다.**

관측(2026-09-03): `assets/hooks/gate_event.py` 를 대상으로 돌린 뒤
`import gate_event` 가 모듈 본문을 엉뚱하게 실행해 `tests/gate-event-test.sh` 의
스키마 단언이 깨졌다. `rm __pycache__/gate_event*.pyc` 로 즉시 정상화됐고,
`python3 -B` 로도 재현되지 않았다.

## 왜 지금 고치지 않았나

게이트 텔레메트리 계획의 범위 밖이다. 당장은 해당 테스트가 `python3 -B` 를 쓰는 것으로
막았다(적용 완료). 그러나 이 우회는 **테스트마다 기억해야 하는 규율**이라 반드시 샌다.

## 해야 할 일

- `mutation-probe.py` 의 복원 경로(`try/finally` + 시그널 핸들러)에서 대상 파일의
  `__pycache__/<name>.*.pyc` 를 함께 지운다. 복원과 캐시 무효화는 한 동작이어야 한다.
- 복원 3중 방어(finally / 시그널 / 종료 시 대조)와 같은 자리에 넣는다 —
  한 곳만 지우면 크래시 경로에서 캐시가 살아남는다.
- 재현 테스트: 크기가 같은 변이(`== → !=`)를 주입·복원한 뒤
  `import` 결과가 원본과 같은지 단언.

## 근거

- `docs/design-docs/core-beliefs.md#r-mut` — "복원이 이 도구의 안전 요건이다.
  소스를 망가뜨린 채 종료하는 도구는 사고다." 바이트코드를 망가뜨린 채 종료하는 것도 같다.
