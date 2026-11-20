# code-mode-settings-global-only
<!-- hermes:auto-generated version:1 created:2026-11-18 -->

## 문제 상황
Code Mode 활성화 설정(CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1)을 프로젝트 .claude.json이나 공장 설치 스크립트에서 강제하려고 하면 작동하지 않습니다. Code Mode 설정은 사용자 전역(~/.claude/settings.json)에서만 인식되며, 프로젝트별 공장 전파 불가능합니다. 새 컴퓨터는 처음엔 Code Mode가 꺼져 있어 사용자가 직접 활성화 방법을 알아야 합니다.

## 규칙
- [ ] Code Mode 설정은 ~/.claude/settings.json 의 env 섹션에서만 작동한다 — 프로젝트 .claude.json 에 넣지 않는다
- [ ] 공장 설치 스크립트(setup.sh, update-all.sh)에서 Code Mode를 강제하지 않는다
- [ ] setup/update 완료 시 Code Mode 활성화 안내 메시지를 출력한다 — "~/.claude/settings.json 에 CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1 추가 필요"
- [ ] 다른 프로젝트 공장에 Code Mode 활성화를 전파하지 않는다 — 사용자 전역 설정이라 중복 안내 금지

## 근거
- 감지 횟수: 1회 (2026-11-16~11-17 Code Mode 훅 실측)
- 패턴 키: code-mode-global-settings-only
- 근거 문서: docs/audits/2026-11-16-code-mode-hooks.md
- 구현 커밋: 9684d18
