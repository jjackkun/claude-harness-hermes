# post-propagate-artifact-cleanup

<!-- hermes:auto-generated version:1 created:2026-10-16 -->

## 문제 상황
전파(update-all propagate) 후 소우주별 커밋을 준비할 때, 공장 임시 파일(`.factory-new`로 끝나는 파일들)과 환경변수 더미값을 정리하지 않은 채 커밋하는 경우 반복 발생.

## 규칙
- [ ] 모든 `.factory-new` 파일 삭제했는가 (`.env.factory-new`, `pre-commit.factory-new` 등)
- [ ] 테스트/더미 환경변수값(OPENAI_API_KEY 등) 원본값으로 수정했는가
- [ ] 공장 매니페스트 추적: `.factory-manifest.json` 영수증만 커밋했는가
- [ ] 공장 설치의 `delete` 목록 파일들이 실제로 삭제되었는가

## 근거
- 감지 횟수: 2회 (terminal-shipping에서 `.factory-new` 남음, jj-agent-room에서 `.git/hooks/pre-commit.factory-new`와 OPENAI_API_KEY 더미값 남음)
- 패턴 키: factory-manifest
