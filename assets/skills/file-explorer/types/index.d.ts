export type Entry = { name: string; kind: 'file' | 'dir' | 'other' }
export type OpenFile = {
  path: string
  // 지금 화면의 내용(고친 것 포함)
  source: string
  // 마지막으로 읽었거나 저장한 내용
  saved: string
  top: number
  // 읽기 화면에서 긴 줄을 볼 때 왼쪽에서 건너뛴 글자 수
  left: number
  // 편집 화면에서 휠이 움직인 줄 수의 누적
  wheel: number
  isEditing: boolean
  // 파일을 새로 읽거나 되돌릴 때마다 오른다. 에디터가 자기 내용을 버리고 다시 받는 신호.
  revision: number
}
// git 탭: 바뀐 파일 목록과 고른 파일의 변경 내용
export type GitView = {
  branch: string
  files: { code: string; path: string }[]
  // 목록에서 맨 위에 보이는 줄
  listTop: number
  // 고른 파일(없으면 null)과 그 변경 내용, 변경 내용에서 맨 위에 보이는 줄
  path: string | null
  diff: string
  top: number
}

export type Model = {
  // 폴더 경로('' 는 프로젝트 루트) → 그 안의 항목
  listed: Record<string, Entry[]>
  expanded: string[]
  // 트리에서 맨 위에 보이는 줄
  treeTop: number
  // 트리 칸의 폭(칸). 세로선을 끌어 바꾼다
  treeColumns: number
  open: OpenFile | null
  notice: string | null
  // 지금 보이는 탭
  tab: 'editor' | 'git'
  // 프로젝트(세션 작업 폴더)의 이름
  project: string
  git: GitView | null
}

declare module 'claude-code' {
  interface PluginState {
    'file-explorer': { model: Model }
  }
}
