# validate-org-before-summon
<!-- hermes:auto-generated version:1 created:2026-09-28 -->

## 문제 상황
에이전트 소환(hermes-agent 스킬) 작업을 시작하려고 할 때 `.hermes/organization.yaml` 의 조직 축(분야·직급·단위)이 비어있으면 `hire` 명령이 거부됩니다. 이 선행 조건을 빠뜨리면 사용자가 "축 값을 먼저 정의하세요" 피드백을 받은 후 회귀합니다.

## 규칙
- [ ] 에이전트 소환 또는 조직 변경 작업 시작 전 `.hermes/organization.yaml` 파일 확인
- [ ] `discipline`, `rank`, `unit` 중 하나라도 비어있으면 즉시 중단
- [ ] 사용자에게 "조직 축이 정의되지 않았습니다. 다음을 먼저 결정해 주세요" + 축 목록 제시
- [ ] 구체값은 사용자가 정하도록 하고, 제안이나 예시로 개입하지 않음

## 근거
- 감지 횟수: 3회
- 패턴 키: hermes-summon.py
- 근거: 세션 2 "축 값을 먼저 채워야 합니다", 세션 3-4 에서도 동일 전제 확인
