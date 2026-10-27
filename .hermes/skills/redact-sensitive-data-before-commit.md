# redact-sensitive-data-before-commit
<!-- hermes:auto-generated version:1 created:2026-10-26 -->

## 문제 상황
R-privacy 게이트가 커밋에 포함된 이메일, 비공개 저장소 이름, 개인 이름 같은 민감한 정보를 탐지하고 차단함. 매번 수정 후 재커밋해야 하는 반복 발생.

## 규칙
- [ ] 커밋 전에 문서·파일에서 이메일 주소([REDACTED:EMAIL] 패턴) 찾기 → [REDACTED:EMAIL] 로 바꾸기
- [ ] 비공개 저장소나 팀 이름(특정 조직·개인 저장소) → [REDACTED:REPO] 또는 [REDACTED:NAME] 으로 바꾸기
- [ ] 개인 이름이나 닉네임이 기술 내용과 무관하게 노출되면 → [REDACTED:NAME] 으로 바꾸기
- [ ] mask 스킬이나 복잡한 가리기 대신, 단순 텍스트 [REDACTED:*] 형식만 사용
- [ ] `git diff` 를 읽고 민감한 정보가 남아 있는지 마지막 확인 후 커밋

## 근거
- 감지 횟수: 8건 (차단 7회, 통과 1회)
- 패턴 키: r-privacy
- 수정 기록: agent-dispatch-rules-vs-model.md 이메일 패턴 가리기로 게이트 통과 (최근)
