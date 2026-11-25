# crystallized-skills-need-creator-vetting
<!-- hermes:auto-generated version:1 created:2026-11-25 -->

## 문제 상황
헤르메스의 `/hermes-crystallize`, `/hermes-dream` 명령으로 `.hermes/skills/` 에 생성된 스킬 파일들이 skill-creator 스킬 검증 없이 미커밋 상태로 방치되는 패턴. 소우주 여러 곳에서 "다른 세션 산출물"로 명시되지만 검증 절차 없이 처리됨.

## 규칙
- [ ] 헤르메스 명령(crystallize, dream)으로 `.hermes/skills/` 에 파일 생성 후, 반드시 skill-creator 스킬 호출
- [ ] skill-creator 검증 완료 시 frontmatter에 `verified_by: skill-creator`, `vetting_date: YYYY-MM-DD` 추가
- [ ] 미검증 스킬은 `.gitignore` 에 추가하거나, 커밋 게이트 R-plan 에서 경고하되, 사용자 승인 후만 커밋
- [ ] 여러 세션에서 같은 스킬이 반복 수정되면, 가장 최신 session-id와 timestamp 기록

## 근거
- 감지 횟수: 3회 (다중 세션 × "다른 세션 산출물" 명시)
- 패턴 키: hermes-crystallize-skill-via-skill-creator
- 근거 문서: CLAUDE.md 「Skill Development」 절 — "새 스킬/기존 스킬 개선 작업 시 **skill-creator 스킬을 반드시 invoke**"
