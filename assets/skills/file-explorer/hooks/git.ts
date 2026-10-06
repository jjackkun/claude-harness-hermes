// git 명령과 그 출력 해석. 여기서는 명령을 실행하지 않는다(실행은 $ 를 쓰는 훅 파일에서).

// code: `git status --porcelain` 의 두 글자 상태(" M", "A ", "??" …)
export type GitFile = { code: string; path: string }
export type GitStatus = { branch: string; files: GitFile[] }

// 한글 등 비 ASCII 경로를 \355\225 식으로 바꾸지 않게 한다.
const GIT = ['git', '-c', 'core.quotepath=false'] as const
const UNTRACKED = '??'

export const STATUS_ARGV = [...GIT, 'status', '--porcelain=v1', '--branch', '--untracked-files=all'] as const

// 추적 중인 파일은 마지막 커밋과의 차이, 새 파일은 빈 파일과의 차이(전부 추가된 줄로 보인다).
export const diffArgv = (file: GitFile): string[] =>
  file.code === UNTRACKED
    ? [...GIT, 'diff', '--no-index', '--', '/dev/null', file.path]
    : [...GIT, 'diff', 'HEAD', '--', file.path]

// `--no-index` 는 차이가 있으면 종료 코드 1 을 낸다. 2 이상이 실패다.
export const isDiffFailure = (exitCode: number): boolean => exitCode > 1

// 첫 줄 `## 브랜치...원격 [ahead 1]`, 그다음 줄마다 `XY 경로`. 이름을 바꾼 파일은 `XY 옛이름 -> 새이름`.
export const parseStatus = (stdout: string): GitStatus => {
  const lines = stdout.split('\n').filter(line => line !== '')
  const head = lines.find(line => line.startsWith('## '))
  const files = lines
    .filter(line => !line.startsWith('## '))
    .map(line => ({ code: line.slice(0, 2), path: line.slice(3).split(' -> ').at(-1) ?? '' }))

  return { branch: head === undefined ? '' : head.slice(3), files }
}

// 줄 색(테마 색 이름). `git status` 와 같은 기준이다: 두 글자 중 오른쪽(작업 폴더 상태)이 비어 있으면
// 스테이징이 끝난 것이라 초록, 아니면(스테이징 안 한 변경, 새 파일) 빨강.
export const colorOf = (file: GitFile): 'success' | 'error' => (file.code[1] === ' ' ? 'success' : 'error')

const isNew = (file: GitFile): boolean => file.code === UNTRACKED || file.code[0] === 'A'

// 파일 트리의 줄 색(테마 색 이름). 편집기들이 쓰는 기준이다: 고친 것은 노랑, 새 것은 초록, 지운 것은 빨강.
// 폴더는 안에 든 파일을 따르되 파일과 다른 색을 쓴다(폴더와 파일이 한눈에 갈리게):
// 고친(또는 지운) 파일이 하나라도 있으면 주황, 새 파일만 있으면 청록.
export const treeColorOf = (path: string, kind: string, files: readonly GitFile[]): string | null => {
  if (kind !== 'dir') {
    const file = files.find(one => one.path === path)
    if (file === undefined) {
      return null
    }

    return isNew(file) ? 'success' : file.code.includes('D') ? 'error' : 'warning'
  }
  // `docs/` 로 견준다: `docs-old/…` 처럼 이름 앞부분만 같은 폴더에 번지지 않게.
  const inside = files.filter(one => one.path.startsWith(`${path}/`))
  if (inside.length === 0) {
    return null
  }

  return inside.every(isNew) ? 'cyan' : 'claude'
}

// 목록 한 줄. 길면 파일 이름이 보이도록 경로의 앞을 줄인다.
export const labelOf = (file: GitFile, room: number): string => {
  const space = Math.max(1, room - file.code.length - 1)
  const path = file.path.length > space ? `…${file.path.slice(-(space - 1))}` : file.path

  return `${file.code} ${path}`
}
