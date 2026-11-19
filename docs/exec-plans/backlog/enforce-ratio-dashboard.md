# 대시보드에 "글 규칙 대 기계 검사" 흐름을 그린다

> 출처: 2026-11-19 결정화 검사 판정(`docs/exec-plans/active/2026-11-19-crystallize-check-first-plan.md`) 의 비목표.

## 문제

결정화가 이제 판정(covered · checkable · prose)을 `.hermes/enforce-verdicts.jsonl` 에 남긴다.
그러나 이 수가 시간에 따라 어떻게 움직이는지는 아무도 보지 않는다.
발표(Lauren Tan, AI Engineer Code Summit 2026-11-11)는 "결정적 검사 수 7 → 167" 을 성과 지표로 썼다.

## 할 일 후보

- `hermes-dashboard` 에 한 줄: 판정별 수 · checkable 후보 중 실제로 게이트가 된 수.
- `hermes_rule_candidates.py`(완료 계획서 §8 후보)와 장부의 checkable 후보를 한 표로 합칠지 정한다.
