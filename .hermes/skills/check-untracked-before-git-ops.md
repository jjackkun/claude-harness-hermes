# check-untracked-before-git-ops
<!-- hermes:auto-generated version:2 created:2026-09-27 -->

## 문제 상황
git 저장소에서 pull/merge 또는 새로운 폴더·파일을 추가할 때, .gitignore 제외 규칙과 미추적 파일 상태를 먼저 확인하지 않아 충돌이나 혼동 발생. 예: `.hermes/*` 가 제외돼 있는데 로컬 미추적 파일이 새 커밋과 충돌하거나, 옛 위치와 새 위치의 산출물이 동시에 존재.

## 규칙
- [ ] git 작업 전(pull/merge/새 폴더 생성) 먼저 `git status` 로 미추적 파일 확인
- [ ] `.gitignore` 에서 새 작업과 관련된 디렉토리 제외 규칙 검토
- [ ] 미추적 파일이 들어올 커밋과 경로 충돌할 경우 `git stash -u` 또는 삭제로 정리
- [ ] `.gitignore` 변경 시 기존 로컬 파일(옛 위치)이 방치되지 않는지 확인

## 근거
- 감지 횟수: 4회 (ai-create pull 전 미추적 파일 4개, .hermes 옛 위치 파일 혼동, settings.local.json 누락, git 초기화 선택지 일관성)
- git 버전 호환성: git 2.25 이상에서 `init -b` 플래그와 `check-ignore` 명령 동작 차이로 인한 로컬 산출물 관리 오류
- 패턴 키: git-2-25-init-b-check-ignore-compatibility
