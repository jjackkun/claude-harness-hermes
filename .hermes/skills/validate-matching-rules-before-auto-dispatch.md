# validate-matching-rules-before-auto-dispatch
<!-- hermes:auto-generated version:1 created:2026-09-28 -->

## 문제 상황
hermes-agent 에서 자동 할당/소환 기능을 설계할 때, 담당 매칭 규칙을 먼저 정하지 않고 모델이 자동으로 판별하려 하면, 문서·결정·구현이 어긋나고 범위가 불명확해진다. auto-owner-summon 사례에서 "알림까지만"과 "자동 진행"이 모순되었고, 조건 2(기억 자동 적립)는 문서 없이 논의되어 규칙이 없었다.

## 규칙
- [ ] 자동화 규칙 먼저: file 편집/CLI 호출 패턴 → 축 값(담당) 매핑을 문서화
- [ ] 매칭은 규칙 기반만—자동 판별·문장 분석 금지
- [ ] 모든 이벤트는 검증 가능한 CLI 명령(`hermes-agent.py match`)으로만 기록
- [ ] 자동화 범위 정의 시 문서·결정·구현 일관성 즉시 점검

## 근거
- 감지 횟수: 1회
- 패턴 키: summon-rule-matching-before-model
