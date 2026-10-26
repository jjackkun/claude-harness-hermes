# mask-sensitive-data-before-commit
<!-- hermes:auto-generated version:1 created:2026-10-26 -->

## 문제 상황
R-privacy 게이트가 commit에 포함된 민감한 정보(비공개 저장소 이름, 이메일 주소, 토큰 패턴)를 감지하여 차단함. 이메일·저장소명·개인정보를 [REDACTED:TYPE] 형식으로 가리면 게이트를 통과하면서도 기록을 남길 수 있음.

## 규칙
- [ ] commit message에서 비공개 저장소 이름(`-private`, `-personal` 등)을 `[REDACTED:REPO]`로 마스킹
- [ ] 이메일 주소(사용자·도메인)를 `[REDACTED:EMAIL]`로 마스킹
- [ ] API 키·토큰·시크릿 패턴을 `[REDACTED:SECRET]`으로 마스킹
- [ ] 개인 신원정보(전화번호, 주민번호 등)를 `[REDACTED:PII]`로 마스킹
- [ ] commit 전 `git diff`로 민감한 정보 포함 여부 스캔
- [ ] 파일 내용(`agent-dispatch-rules-vs-model.md` 같은 문서)에도 동일하게 적용

## 근거
- 감지 횟수: 7회
- 패턴 키: privacy-gate-redaction-pattern
- 사례: R-privacy 버그 수정(0bb7e0c) 후 3곳 전파 시 마스킹으로 게이트 통과
