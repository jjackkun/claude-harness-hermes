# selective-redaction-keeps-paths
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
LLM 입력값에서 사용자명(홈 디렉터리 경로)을 가릴 때, `/home/[REDACTED:NAME]/…` 형태로 가리면 에이전트의 Read/Edit 도구가 경로를 파싱하지 못해 실패. hermes-summon·hermes-loop 실행 시 반복 발생했고, redact_keep_paths() 함수 추가로 해결.

## 규칙
- [ ] LLM 입력값 가릴 때 절대 경로 구조는 유지 — $HOME 자리표시자 사용
- [ ] 민감 정보(사용자명)는 경로 밖에서만 가림 — 프롬프트 문맥 내 사용자명은 [REDACTED:NAME] 처리
- [ ] 함수 redact_keep_paths(text, home_path) 추가 — 경로 재귀 보존, 사용자명만 선택적 가림
- [ ] 변경 후 도구 호출 경로 시험 (tests/hermes-redact-llm-input-test.sh) 6개 케이스 통과 확인

## 근거
- 감지 횟수: 3회 (summon, loop, redact 함수 적용)
- 패턴 키: redact-input-not-prompt
