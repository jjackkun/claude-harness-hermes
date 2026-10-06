import type { Entry, Model, OpenFile } from '../types'
import { TREE_COLUMNS } from './constants'
import { sortEntries } from './tree'

// 상태를 어떻게 바꿀지만 계산한다. 엔진($)을 만지지 않는다.
export type Change = (m: Model) => Partial<Model>

const reasonOf = (error: unknown): string => (error instanceof Error ? error.message : String(error))

export const listedIn =
  (dir: string, entries: readonly Entry[]): Change =>
  m => ({
    listed: { ...m.listed, [dir]: sortEntries(entries.map(({ name, kind }) => ({ name, kind }))) },
    notice: null,
  })

export const opened =
  (path: string, source: string): Change =>
  m => ({
    open: { path, source, saved: source, top: 0, left: 0, wheel: 0, isEditing: false, revision: (m.open?.revision ?? 0) + 1 },
    notice: null,
  })

const onOpen =
  (change: (open: OpenFile) => Partial<OpenFile>): Change =>
  m => (m.open === null ? {} : { open: { ...m.open, ...change(m.open) } })

export const edited = (source: string): Change => onOpen(() => ({ source }))
export const savedNow = (): Change => onOpen(open => ({ saved: open.source }))
export const reverted = (): Change => onOpen(open => ({ source: open.saved, wheel: 0, revision: open.revision + 1 }))

// 편집 상태를 켜고 끈다. 너무 큰 파일은 켜지 않고 이유를 알린다.
export const toggledEditing =
  (maxChars: number): Change =>
  m => {
    if (m.open === null) {
      return {}
    }
    if (!m.open.isEditing && m.open.source.length > maxChars) {
      return { notice: `파일이 커서 편집할 수 없습니다 (${m.open.source.length}자, 한도 ${maxChars}자)` }
    }

    // 에디터는 켜질 때마다 맨 위에서 새로 시작하므로 휠 누적도 0 에서 다시 센다.
    return { open: { ...m.open, isEditing: !m.open.isEditing, wheel: 0 }, notice: null }
  }

export const failed =
  (what: string, error: unknown): Change =>
  () => ({ notice: `${what}: ${reasonOf(error)}` })

export const collapsed =
  (path: string): Change =>
  m => ({ expanded: m.expanded.filter(one => one !== path) })

export const expandedWith =
  (path: string): Change =>
  m => ({ expanded: [...m.expanded, path] })

// 세션 작업 폴더의 경로에서 마지막 이름을 프로젝트 이름으로 삼는다.
export const projectAt =
  (cwd: string): Change =>
  () => ({ project: cwd.split('/').filter(part => part !== '').at(-1) ?? '' })

// 세션 상태는 모드를 다시 읽어도 남는다. 예전 판이 남긴 모양(open 에 빠진 값)을 지금 모양으로 채운다.
// 빠진 값이 undefined 로 화면 모듈에 넘어가면 엔진이 패널 전체를 그리지 못한다.
export const sane = (m: Model): Model => ({
  ...m,
  treeTop: m.treeTop ?? 0,
  treeColumns: m.treeColumns ?? TREE_COLUMNS,
  tab: m.tab ?? 'editor',
  project: m.project ?? '',
  git: m.git ?? null,
  open:
    m.open === null
      ? null
      : {
          ...m.open,
          saved: m.open.saved ?? m.open.source,
          top: m.open.top ?? 0,
          left: m.open.left ?? 0,
          wheel: m.open.wheel ?? 0,
          isEditing: m.open.isEditing ?? false,
          revision: m.open.revision ?? 0,
        },
})

// 채운 상태 위에 변경을 얹은 새 상태.
export const applied =
  (change: Change) =>
  (m: Model): Model => {
    const whole = sane(m)

    return { ...whole, ...change(whole) }
  }
