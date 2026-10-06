# Explicit Summon After Assignment
<!-- hermes:auto-generated version:1 created:2026-09-28 -->

## 문제 상황
백로그나 계획 문서에서 작업을 정의하거나 담당 에이전트가 이미 존재할 때, 
명시적으로 그 에이전트를 소환(summon)하지 않으면 에이전트는 자신에게 일이 
생겼는지 알 수 없다. 설계상 자동 라우팅 기능이 없으므로, 명시적 호출이 필수.

## 규칙
- [ ] 작업·백로그·계획 항목을 작성한 뒤, 담당 분야·조직이 정해져 있으면 즉시 `hermes-summon.py run` 또는 자연어로 호출
- [ ] 자동 라우팅을 기대하지 말 것 — 설계상 명시적 소환만 작동 (hook/추론 기반 자동 감지 없음)
- [ ] "봉투"(handoff)만 정의하고 열지 않는 패턴 감지 후 중단 — 정의 직후 소환까지 같은 턴에 완성

## 근거
- 감지 횟수: 1회
- 패턴 키: handoff-over-immediate-summon
