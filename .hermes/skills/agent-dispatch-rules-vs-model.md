# agent-dispatch-rules-vs-model
<!-- hermes:auto-generated version:1 created:2026-09-28 -->

## 문제 상황
자동 에이전트 소환 시 "누가 일을 받을지" 결정하는 방식을 혼동함.
cumora는 규칙(멘션, 담당, 기한)만 사용하고 모델이 선택하지 않는다고 명시했으나,
hermes 자동화를 설계할 때 같은 원칙을 놓침. 
09-19 결정(cumora 방식으로 이미 정함)을 재검토 없이 새 목표를 세우는 오류 반복.

## 규칙
- [ ] 에이전트 소환은 두 경로만 사용: **사용자 명시**(자연어로 "이 일 QA에 넘겨") 또는 **규칙 기반**(멘션·담당·기한)
- [ ] 모델이 "누구를 깨울지" 선택하는 dispatch 절대 금지 — 불확실하면 전원 소환, 사람이 선별
- [ ] cumora 09-19 결정 조회 후 작업 시작 — hermes도 같은 방식을 따를지, 다를지 명시하고 진행
- [ ] hermes-agent(입사)와 hermes-summon(소환)의 역할 구분 명확히 — 자동화와 기억 적립 주체를 따로 정의

## 근거
- 감지 횟수: 1회 (목표 5 작성 시 누락)
- 선행 결정: cumora/[REDACTED:EMAIL] 규칙 기반 소환, 09-19 hermes 채택 완료
- 패턴 키: cumora-vs-claude-code-dispatch
