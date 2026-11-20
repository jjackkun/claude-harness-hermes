# respect-skill-session-boundaries
<!-- hermes:auto-generated version:1 created:2026-11-19 -->

## 문제 상황
다중 에이전트 세션의 결정화 스킬들(redact, legacy-venv, skip-nbbang-run)이 현재 세션의 커밋에 포함되어, 세션 간 경계가 무너짐.

## 규칙
- [ ] `.hermes/skills/` 커밋 전에 파일의 세션 출처 확인
- [ ] 다른 에이전트 세션의 스킬은 `git reset` 또는 `.gitignore` 로 제외
- [ ] `git add` 시 경로를 명시; 광범위 와일드카드 사용 금지
- [ ] 각 세션은 자신이 생성한 스킬만 커밋

## 근거
- 감지 횟수: 3회 (redact, legacy-venv, skip-nbbang-run)
- 패턴 키: skip-hermes-skills-commit-multiagent-session
