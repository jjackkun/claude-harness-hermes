# skill-metadata-consistency

<!-- hermes:auto-generated version:1 created:2026-10-06 -->

## 문제 상황
스킬 색인, 설치 함수, 커밋 게이트에서 SKILL.md(frontmatter) 요구 여부가 불명확하고 불일치함. 공장 설치와 로컬 설치에서 다르게 처리되면서 중복 폴더 또는 frontmatter 누락 폴더가 섞임.

## 규칙
- [ ] 모든 스킬 폴더는 반드시 frontmatter를 포함해야 한다 (필수/선택을 먼저 명시)
- [ ] 색인 함수는 frontmatter 없는 폴더를 명확히 거부하거나 경고한다
- [ ] 설치 함수(공장·로컬)는 같은 규칙을 적용한다
- [ ] 커밋 게이트는 assets/skills/ 검사 시 frontmatter 요구 규칙을 일관되게 강제한다
- [ ] 불명확한 케이스는 에러 메시지로 규칙을 안내한다

## 근거
- 조사 대상 6가지: 전역 선택 설치, 함수 요구사항, 색인 처리, 게이트 검사, 공장 시험, 중복 설치
- 공통 원인: frontmatter 규칙 부재로 인한 처리 불일치
