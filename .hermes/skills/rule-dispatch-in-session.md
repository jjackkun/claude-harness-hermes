# rule-dispatch-in-session
<!-- hermes:auto-generated version:1 created:2026-09-29 -->

## 문제 상황
세션 중 에이전트가 직접 Claude API를 호출하거나 모델에 의존해 소환 결정을 내리는 대신, 규칙 기반 에이전트 소환(cumora) 시스템과 프롬프트 지시만 사용해야 한다는 규칙을 적용해야 함.

## 규칙
- [ ] 세션 중 `anthropic` SDK 직접 호출 금지 (R3 준수)
- [ ] 에이전트 소환은 @멘션·칸반 배정·기한·idle 주기 등 규칙 기반만 사용
- [ ] 기억 적립은 프롬프트 지시에 따라 `hermes-summon.py note` 명령으로만 실행
- [ ] ECC 도구 로그 관찰 거부 (비용 관리, R3)
- [ ] 사람 선택이 필요하면 모델 판정 대신 프롬프트 체크리스트로 표시

## 근거
- 결정 일시: 2026-09-19
- 관련 규칙: R3 (LLM 경로 강제), R1 (실행 모드 격리)
- 패턴 키: no-direct-claude-invocation-in-session
