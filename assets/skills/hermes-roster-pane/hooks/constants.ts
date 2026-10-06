export const PANE = 'hermes-roster-pane'
export const TITLE = '에이전트 명부'
export const COMMAND = 'roster'
export const REFRESH_KEY = 'refresh'
export const OPEN_KEY = 'open-roster'
// /hermes-roster 스킬이 부르는 것과 같은 명령. 세션의 작업 폴더(프로젝트 루트)에서 돈다.
export const ROSTER_ARGV = ['python3', 'scripts/hermes-agent.py', '--project', '.', 'roster'] as const
// 한글 음절 범위(가-힣). 터미널에서 두 칸을 차지한다.
export const HANGUL_FIRST = 0xac00
export const HANGUL_LAST = 0xd7a3
// 전체 닫기가 닫는 패널들: 이 컴퓨터에 깔린 세 모드의 패널 이름. 모드를 더하면 세 모드의 이 목록을 함께 고친다.
export const ALL_PANES = ['file-explorer', 'hermes-roster-pane', 'tool-calls-pane'] as const
