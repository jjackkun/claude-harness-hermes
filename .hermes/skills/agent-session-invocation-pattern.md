# agent-session-invocation-pattern
<!-- hermes:auto-generated version:1 created:2026-09-30 -->

## 문제 상황
Claude Code의 자동 저장(`~/.claude/projects`)과 공식 에이전트 기능(`--agent`, `memory: project`)을 동시에 사용할 때, 에이전트 세션 호출 방식이 표준화되지 않으면 SessionStart 훅이 agent_type을 제대로 받지 못한다. 상태줄 표기도 기존 설정을 덮으면 정보 손실이 생기고, 같은 에이전트로 돌아가는 경로가 불명확해진다.

## 규칙
- [ ] 모든 에이전트 세션은 `claude --agent <slug> --name <room-name>` 형식으로 시작 — agent_type을 명시하고 방(room) 이름 붙이기
- [ ] 기존 에이전트 세션으로 돌아올 때는 `claude --resume <slug>` 사용 — --name 생략 가능
- [ ] 상태줄 설정: 기존 ~/.claude/statusline.sh를 덮지 않고, hermes-statusline.sh로 전역 statusLine 명령 대체 (끝에 추가)
- [ ] SessionStart 훅이 자동으로 agent_type을 입력으로 받음 — 수동 config 불필요
- [ ] hermes-chat은 새 실행기 명령 없이 기본 `claude --agent <slug> --name <room>` 패턴만 사용

## 근거
- 감지 횟수: 1회
- 패턴 키: claude-code-local-autosave
