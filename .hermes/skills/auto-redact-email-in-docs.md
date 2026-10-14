# auto-redact-email-in-docs
<!-- hermes:auto-generated version:1 created:2026-10-08 -->

## 문제 상황
문서 및 코드 파일에 이메일 주소가 노출되면 R-privacy 게이트가 차단합니다. 특히 exec-plan, design-doc, audit 같은 저장소 문서에 실제 이메일이 남으면 privacy 검사에서 걸립니다.

## 규칙
- [ ] 저장소 문서(`.md`)에 실제 이메일 주소를 쓰지 않기 — 예시 도메인(`@example.com`) 또는 `[REDACTED:EMAIL]` 형식 사용
- [ ] 이메일을 언급해야 하면 개념적 설명(역할, 맥락)으로 충분한지 먼저 확인
- [ ] commit 메시지, 주석, 문서 본문에서 `user@domain`, `[REDACTED:EMAIL]` 패턴을 grep 확인
- [ ] 의도적으로 남겨야 하는 실제 이메일은 `.gitignore` 파일이나 환경변수로 처리

## 근거
- 감지 횟수: 1회
- 패턴 키: privacy-redaction-email-patterns
