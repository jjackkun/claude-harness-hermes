# agent-status-display-commands

<!-- hermes:auto-generated version:1 created:2026-09-29 -->

## 문제 상황

hermes 에이전트 명부 조회와 세션 상태 표시 명령이 분리되지 않아, 사용자가 "현재 방의 에이전트 누구?" 와 "전체 명부" 를 구분하지 못함. hermes-chat 문서에서 "방 열기" 명령 안내도 누락되어 착수가 막혔음.

## 규칙

- [ ] `/hermes-roster` 호출: 전체 에이전트 명부 표 (이름·@호출명·상태·분야·최근 호출 시각)
- [ ] `/hermes-room` 호출: 현재 세션만 표시 (명부 에이전트는 이름·횟수·마지막 시각, 외부는 종류별 건수)
- [ ] 명부 에이전트 새로 고용: `hermes-agent` 스킬 (자연어 설명) 또는 `--agent <호출명> --name <방이름>` CLI
- [ ] hermes-chat 또는 hermes-roster 문서에 "방 열기 단일 명령" 한 줄 안내 필수: `claude --agent <호출명> --name <방>`

## 근거

- 감지 횟수: 1회
- 패턴 키: hermes-roster-room-skill-structure
