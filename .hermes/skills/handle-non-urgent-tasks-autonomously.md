# handle-non-urgent-tasks-autonomously
<!-- hermes:auto-generated version:1 created:2026-09-29 -->

## 문제 상황
비긴급 업무에 대해 명시적 봉투(업무 지시)를 기다리거나 사전 확인을 반복함으로써, 의사결정이 지연되고 독립성이 떨어진다. 우선순위가 낮은 일은 자가 계획·실행·기록으로 처리하여 민첩성을 높일 수 있다.

## 규칙
- [ ] 비긴급 업무: 봉투 요청 없이 즉시 `docs/exec-plans/active/YYYY-MM-DD-slug.md` 계획 작성
- [ ] 자동 결정(파일 구조·라이브러리·호출 패턴): 매 결정마다 확인하지 말고 진행
- [ ] 완료 후 회고 작성하고 `docs/exec-plans/completed/` 로 이동
- [ ] 예외: 보안·파괴적 작업·공유 경계 변경 시만 사전 승인 요청

## 근거
- 감지 횟수: 0회
- 패턴 키: handoff-for-non-urgent-work
