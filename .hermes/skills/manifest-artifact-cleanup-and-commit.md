# manifest-artifact-cleanup-and-commit
<!-- hermes:auto-generated version:1 created:2026-10-16 -->

## 문제 상황
전파(update-all) 후 소우주별 커밋 시 어떤 파일을 포함할지 일관성이 없고, `.factory-new` · `pre-commit.factory-new` 같은 임시 파일이 남는 문제 발생. jj-agent-room에서 `.git/hooks/pre-commit.factory-new` 미정리, terminal-shipping에서 `.factory-new` 정리 누락.

## 규칙
- [ ] `.factory-manifest.json` 반드시 포함 (설치물 추적·버전 기록)
- [ ] `.structbaseline` 포함 (구조 검사 기준선)
- [ ] 영수증·로그 파일 포함 (설치 후 산출물)
- [ ] 삭제된 공장 파일만 포함 (생성·수정된 파일 제외)
- [ ] `.factory-new`, `.factory-old` 임시 파일 제거
- [ ] `pre-commit.factory-new` 등 훅 임시 파일 제거
- [ ] `git status` 로 정리 완료 확인 후 커밋

## 근거
- 감지 횟수: 4회
- 패턴 키: factory-manifest.json
