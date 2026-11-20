# agent-workspace-isolation-enforce
<!-- hermes:auto-generated version:1 created:2026-11-19 -->

## 문제 상황
PC 에이전트는 자신의 폴더(`.../agents/<id>/`)에서만 Code 실행 가능한데, 콘텐츠를 에이전트 간 이전할 때 소유권 경계가 명시되지 않으면 "어느 에이전트 책임인가"가 모호해진다. game-dev 폴더(30개 파일, 3.5MB)를 공장(claude-harness-hermes)에서 jj-agent-room으로 옮길 때 이 경계를 준수했으나, 세션 시작 훅에서 별도 장부를 확인하는 프로세스가 아직 선택사항인 상태다.

## 규칙
- [ ] 에이전트는 자신의 폴더(`.../agents/<id>/`)에서만 Code 실행하고 write/glob/edit를 호출한다
- [ ] 콘텐츠를 에이전트 간 이전할 때, 옮긴 파일마다 프로비넌스 한 줄을 추가한다  
  예: "원출처: claude-harness-hermes/docs/game-dev (c2a0d85f 로 이전)"
- [ ] 세션 시작 시 별도 장부(업스트림 체크, --ledger)를 확인해 "이 콘텐츠는 이 에이전트 책임"을 명시한다
- [ ] Code 실행 경로가 agent 폴더 밖으로 나가는 명령(다른 프로젝트 Code 호출, 공장 파일 edit)은 먼저 보고하고 에이전트 소유 여부를 확인한다

## 근거
- 감지 횟수: 2회 (D7·D14)
- 패턴 키: agent-folder-access-isolation-pattern
