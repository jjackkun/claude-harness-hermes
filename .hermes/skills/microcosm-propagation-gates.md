# microcosm-propagation-gates
<!-- hermes:auto-generated version:1 created:2026-11-16 -->

## 문제 상황
공장(claude-harness-hermes)의 변경을 소우주(12개 서브프로젝트)에 전파할 때 제외 대상과 프로젝트별 커밋 규칙을 빠뜨려 불완전한 동기화 또는 역 전파를 초래함.

## 규칙
- [ ] 공장 커밋·푸시 완료 확인
- [ ] 소우주 제외 대상 리스트 전부 읽기: `~/.claude/memory/project-*-excluded.md`
  - 제외 프로젝트: zeroday-frontend, rim-kanban, jj-agent-room, ai-create, rim-office, teulankkae, wonil
  - 설치만: jj-agent-room, ai-create, rim-office, teulankkae, wonil
- [ ] 소우주 10곳 각각의 커밋·푸시 규칙 확인 — 메모리 항목 따라 실행
  - 예: terminal-shipping은 Node 22 PATH 앞 필요
- [ ] common 규칙: `~/.claude/rules/common/` 한 벌만 설치, 소우주 사본 금지
- [ ] 역 전파 방지: 소우주→공장 merge/push 금지
- [ ] 전파 완료 판정: 공장 커밋 + 소우주 커밋·푸시 양쪽 모두 확인

## 근거
- 감지 횟수: 4회 (첫 전파, 재전파, 미커밋분, 공장 단독 변경)
- 패턴 키: 소우주
