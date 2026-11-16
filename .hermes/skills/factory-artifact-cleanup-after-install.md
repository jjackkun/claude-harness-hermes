# factory-artifact-cleanup-after-install
<!-- hermes:auto-generated version:1 created:2026-11-16 -->

## 문제 상황
공장(claude-harness-hermes) 설치 또는 버전 업데이트 후 `.factory-new` 임시 파일들이 git 상태에 남아있고, 버전 충돌 해결 시 새 파일이 누락되거나 더미값(예: OPENAI_API_KEY)이 갱신되지 않은 채 방치되는 경우 반복 발생.

## 규칙
- [ ] 설치 완료 또는 rebase 후 `git status` 에서 `.factory-new` 파일 확인
- [ ] `.factory-new` 가 있으면 원본 파일과 diff 로 비교해 충돌 해결 여부 확인
- [ ] 해결 완료된 `.factory-new` 는 `rm` 으로 제거
- [ ] 버전 충돌(factory.json, pre-commit 등)은 새 버전 파일을 채택하고 로컬만 유지
- [ ] 프로젝트별 설정값(API 키, 환경변수 더미값)이 원래 값으로 복원됐는지 확인
- [ ] 정리 후 `git status` 가 깨끗해질 때까지 반복

## 근거
- 감지 횟수: 2회
- 패턴 키: factory
- 사례: terminal-shipping `.factory-new` 제거, jj-agent-room pre-commit 파일 및 OPENAI_API_KEY 정리 필요
