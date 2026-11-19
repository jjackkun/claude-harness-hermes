export const PANE = 'tool-calls-pane'
export const TITLE = '도구 호출'
// 전체 닫기가 닫는 패널들: 이 컴퓨터에 깔린 세 모드의 패널 이름. 모드를 더하면 세 모드의 이 목록을 함께 고친다.
export const ALL_PANES = ['file-explorer', 'hermes-roster-pane', 'tool-calls-pane'] as const
// 띠의 주인 줄: 엔진이 띠를 모드마다 한 줄로 세로로 쌓으므로(2.1.325~), 이 모드의 버튼은 이 모드의 줄 오른쪽에 붙는다.
export const BAND_HOST = 'file-explorer'
