# prompt-injection-safety-audit
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
프롬프트 가림/필터링 처리가 여러 파일에서 일관되지 않게 구현됨. docstring에 가림 상태가 명시되지 않아 중복 처리 발생(summon 중복 가림). U8·U13 사고 유도 문자열이 체계적으로 검증되지 않은 채 여러 곳에 산재.

## 규칙
- [ ] 프롬프트/사용자 입력을 받는 함수의 docstring에 "이미 가려진 값" 또는 "가려지지 않은 입력" 명시
- [ ] 한 프롬프트의 가림/검증은 한 곳에서만 수행 — 중복 처리 제거
- [ ] 함수 매개변수 이름을 `prompt` 대신 `prompt_cleaned` / `raw_prompt` 로 상태 명확히
- [ ] 사고 유도 패턴(U8·U13 스타일) 검증 여부를 docstring에 기록
- [ ] 프롬프트 로직 변경 시 `docs/audits/YYYY-MM-DD-prompt-*.md` 감사 기록 작성

## 근거
- 감지 횟수: 6곳 파일(hermes_search_fallback, hermes-evolve-skill, hermes-summon, hermes-manager, hermes_loop_prompt, hermes_redact)
- 감사 결과: 17 findings (High 7, Medium 8, Low 2) — 2026-09-28-prompt-audit.md
- 패턴 키: prompt
