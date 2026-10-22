# preserve-untracked-backup-folders
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
설치기나 도구가 생성한 파일을 갱신할 때 이전 버전의 백업을 보관하지만, git 추적 여부와 백업 정책(보관 기간, 삭제 시기)이 명시되지 않아 저장소 상태가 모호해짐.

## 규칙
- [ ] 이전 버전은 `<original-name>.backup-YYYYMMDD-HHMMSS/` 형식 폴더에 보관 (설치기 보존용)
- [ ] 백업 폴더를 `.gitignore` 에 추가: `**/*.backup-*/`, `**/.*backup-*/`
- [ ] `git status` 로 `??` (untracked) 확인 — 리포지터리 버전 관리 대상 아님
- [ ] 백업 보관 정책을 프로젝트 문서(`CLAUDE.md` 또는 관련 exec-plan)에 기록: 보관 기간, 자동 삭제 규칙, 사용자 판단 필요 여부

## 근거
- 감지 횟수: 2회
- 패턴: `ts-backup/` (설치기 산출물), `.claude/skills/skill-creator.backup-*` (보존 사본)
- 패턴 키: backup-folder-untracked-retention
