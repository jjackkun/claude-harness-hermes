# Summon Agent by Roster Slug

<!-- hermes:auto-generated version:1 created:2026-09-28 -->

## 문제 상황
에이전트를 소환할 때마다 명부(roster)를 먼저 조회하고, 각 에이전트의 영문 slug(호출명)를 확인하는 절차가 반복된다. slug 없이는 `@agent-<name>` 형식으로 정확히 부를 수 없다.

## 규칙
- [ ] 에이전트를 부르기 전에 현재 명부 확인 (`.claude/agents/` 파일 또는 `agents.json`)
- [ ] 각 에이전트의 영문 slug 확인 (예: `gate-qa`, `backlog-manager`, `code-reviewer`)
- [ ] 할 일과 함께 `@agent-<slug>` 또는 에이전트 이름을 명시하여 호출
- [ ] 명부 없는 에이전트는 호출 불가 상태를 먼저 보고
- [ ] hermes-agent 스킬 호출 시 명부 쿼리를 첫 단계로 수행

## 근거
- 감지 횟수: 3회
- 패턴 키: hermes-agent
- 증거: 명부 slug 추가 작업(90384ce, b9771b4), 목표 6 계획서(2026-09-28-agent-mention-bridge.md)
