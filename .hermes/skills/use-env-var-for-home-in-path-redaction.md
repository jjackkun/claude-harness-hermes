# use-env-var-for-home-in-path-redaction
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
Hermes summon/loop 에이전트가 절대경로를 REDACTED 처리할 때 홈 디렉터리까지 가려서 에이전트의 Read/Edit이 존재하지 않는 경로에 접근 → 파일 I/O 실패.

## 규칙
- [ ] 홈 디렉터리는 `$HOME` 환경변수로 대체 (가리지 않음)
- [ ] 경로 밖의 사용자명만 REDACTED로 처리
- [ ] 경로 가리기(redact_keep_paths 등)에서 홈은 특수 케이스로 취급
- [ ] 절대경로 생성하는 모든 에이전트 호출 전에 적용

## 근거
- 감지 횟수: 8회
- 패턴 키: home
- 프로젝트: terminal-shipping, claude-harness-hermes
