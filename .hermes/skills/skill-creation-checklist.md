# skill-creation-checklist
<!-- hermes:auto-generated version:1 created:2026-10-13 -->

## 문제 상황
skill-creator 호출 후 `.backup-*` 폴더가 남아 매번 사용자 정책 판단 대기; "실제 스킬 생성·개선"의 경계 불명확 (백로그, 문서 케이스와 혼동); 공장과 로컬 저장소 간 버전 불일치.

## 규칙
- [ ] skill-creator 호출: **신규 스킬 작성** 또는 **기존 스킬 본문 수정**일 때만
- [ ] 백로그·계획서·감사 기록·다큐먼트 개선 → skill-creator 대상 아님 (해당 도메인 에이전트 사용)
- [ ] `.backup-*` 폴더 → `.gitignore` 추가, 미추적 유지 (설치기 보존본, 매번 사용자 판단 불필요)
- [ ] 스킬 파일명 규칙: 패턴 키 아닌 규칙 내용 요약 영문 kebab-case (예: `skill-creator` → `skill-creation-checklist`)
- [ ] 크로스 머신 동기화: `bash public-claude.sh --skills-only` 로 명시적 반영 (자동 아님)

## 근거
- 감지 횟수: 5회 (백업 정책 2회, 경계 모호 1회, 버전 동기화 1회, 파일명 규칙 1회)
- 패턴 키: skill-creator
