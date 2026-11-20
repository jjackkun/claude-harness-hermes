# respect-user-setup-choices
<!-- hermes:auto-generated version:1 created:2026-11-18 -->

## 문제 상황
사용자가 명시적으로 제외하거나 직접 처리하기로 결정한 프로젝트·설정·파일을 무시하고 자동으로 설치·수정·처리하려는 경향. jj-agent-room·drh-cloth-shop 같은 특정 프로젝트, korean 프리셋, pre-commit 포크 판, Code Mode 설정 등이 대상.

## 규칙
- [ ] 사용자 제외 목록(jj-agent-room, drh-cloth-shop, teulankkae, wonil, zeroday-frontend, rim-kanban)은 설치·전파·커밋 제안 금지
- [ ] korean 프리셋은 설치 제안 금지 (사용자가 비활성화 결정)
- [ ] ~/.claude/settings.json의 Code Mode env 섹션은 사용자가 직접 추가하도록 안내 — 자동 수정 금지
- [ ] 프로젝트 포크 판(R-size 처리 포함 pre-commit)은 사용자 별도 병합·처리로 진행 — 자동 처리 금지
- [ ] mod 레이어는 세션 시작 시 숨김 — 사용자가 의도적으로 활성화할 때만 표시

## 근거
- 감지 횟수: 7회
- 패턴 키: 사용자가
