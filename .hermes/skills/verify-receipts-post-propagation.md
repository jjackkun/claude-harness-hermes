# verify-receipts-post-propagation
<!-- hermes:auto-generated version:1 created:2026-10-15 -->

## 문제 상황
헤르메스 전파 후 각 프로젝트의 영수증(원격 최신 커밋 해시)을 검증하고 추적 대상 파일의 일관성을 확인하는 단계가 문서화되지 않아, 일관성 오류를 사후 발견하고 재수정하는 상황 반복.

## 규칙
- [ ] 전파 완료 직후 각 저장소별 원격 최신 커밋을 기록하고 공장 영수증과 비교
- [ ] .gitignore 추적 규칙(.hermes/skills/**, .hermes/journal.jsonl 등)이 각 프로젝트에 적용됐는지 확인
- [ ] 세션 파일(*.md 스킬)과 공유 파일(journal.jsonl)의 커밋 경계를 명확히 하고 배제 대상 문서화
- [ ] 미추적 스킬은 로컬만 유지하고 리모트 겹침 여부를 커밋 전 스캔
- [ ] 수정 파일 목록을 세션 기록에 남기고 전파 후 각각 원격 반영 확인

## 근거
- 감지 횟수: 3회
- 패턴 키: hermes-receipt-verification-procedure
