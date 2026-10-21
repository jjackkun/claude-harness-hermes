# redact-usernames-not-paths
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
hermes redaction이 절대 경로에서 사용자명을 가릴 때, `/home/[REDACTED:NAME]/...` 를 `/home/[REDACTED:NAME]/...` 로 변환하면 경로 자체가 깨져 에이전트의 Read/Edit 실패를 초래합니다. 특히 loop·summon에서 큰 문제.

## 규칙
- [ ] 홈 경로(`/home/[user]/` 형태)는 경로 자체를 보존하려고 `$HOME` 자리표시자로 치환
- [ ] 경로 밖의 사용자명(로그, 설정값, 명부, 속성명)만 선택적으로 가림
- [ ] redact_keep_paths() 함수로 홈 디렉터리 판정 및 보존 로직 분리
- [ ] 시험 케이스: 절대경로·상대경로·파일명·사용자명 혼재 — 6개 이상 커버

## 근거
- 감지 횟수: 1회 (2026-10-21)
- 패턴 키: redact-home-as-token
