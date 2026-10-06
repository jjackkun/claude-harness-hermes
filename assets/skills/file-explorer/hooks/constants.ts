export const PANE = 'file-explorer'
export const TITLE = '파일'
export const COMMAND = 'files'
export const OPEN_KEY = 'open-files'
export const ROOT = ''
// 트리 한 단계 들여쓰기(칸)
export const INDENT = 2
// 트리 칸의 처음 폭: 들여쓰기 4단계(8칸) + 이름 24자. 세로선을 끌어 바꿀 수 있다(상태의 treeColumns).
export const TREE_COLUMNS = 32
// 코드 한 줄 관례 폭 80칸 + 줄 번호 칸 6
export const CODE_COLUMNS = 86
// 탭 줄 1 + 도구 줄 1 + 알림 줄 1
export const HEADER_ROWS = 3
// 에디터 줄 번호 칸: 숫자 5자리 + 공백 1
export const GUTTER = 6
// 편집 가능한 최대 글자 수: 엔진이 화면 모듈에 넘기는 값의 한도 100000자에서 직렬화 여유 10%를 뺀 값.
// 색 입히기도 이 크기까지만 한다(편집 화면이 다루는 가장 큰 파일까지만 통째로 분석한다).
export const MAX_EDIT_CHARS = 90000
export const EDITOR_KEY = 'editor'
// 트리와 보기 사이의 세로선 폭(칸). 누른 채 끌면 트리 폭이 바뀐다.
export const DIVIDER_COLUMNS = 1
export const DIVIDER_KEY = 'divider'
// 트리가 줄어들 수 있는 가장 좁은 폭: 들여쓰기 2단계(4칸) + 이름 8자
export const MIN_TREE_COLUMNS = 12
// 보기 화면에 남겨 둘 글자 자리(줄 번호 칸과 세로 막대는 따로): 트리의 가장 좁은 폭과 같게
export const MIN_TEXT_COLUMNS = 12
export const TREE_KEY = 'tree'
export const HBAR_KEY = 'hbar'
// 세로 스크롤 막대의 폭(칸)과 가로 스크롤 막대의 높이(행)
export const BAR_COLUMNS = 1
export const HBAR_ROWS = 1
// 가로 막대 위에서 휠 한 칸에 넘기는 글자 수: 들여쓰기 한 단계(4칸)
export const WHEEL_COLUMNS = 4
// 전체 닫기가 닫는 패널들: 이 컴퓨터에 깔린 세 모드의 패널 이름. 모드를 더하면 세 모드의 이 목록을 함께 고친다.
export const ALL_PANES = ['file-explorer', 'hermes-roster-pane', 'tool-calls-pane'] as const
export const GIT_LIST_KEY = 'gitlist'
