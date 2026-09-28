# identity-folder-injection-at-session-start
<!-- hermes:auto-generated version:1 created:2026-09-18 -->

## 문제 상황
세션 훅 설계 시 정체성 폴더(SOUL.md, MEMORY.md)를 읽고 주입해야 한다는 요구사항이 설계 문서에는 명시되었으나, 구현 계획의 체크리스트 목표에는 빠져 구현 누락이 발생. 설계와 계획 간 추적(traceability) 부재.

## 규칙
- [ ] 설계 문서에 "정체성 폴더를 읽고 주입"이 명시되면 구현 계획 목표에 명시적 항목으로 추가
- [ ] 세션 훅 구현 시 `$AGENT_ID` 또는 사용자 신원 폴더 존재 여부 확인 단계 필수 포함
- [ ] 정체성 파일 크기 상한(각 4,096B)을 계획 요구사항으로 명시하고 구현에서 검증
- [ ] 비자명한 작업 수행 시 설계 요구사항(특히 "반드시 할 일")을 계획 체크리스트에 1:1 매핑하여 누락 방지

## 근거
- 감지 횟수: 1회
- 패턴 키: soul-injection-via-session-hook
