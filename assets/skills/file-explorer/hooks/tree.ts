import type { Entry, Model } from '../types'
import { ROOT } from './constants'

export type Row = { path: string; name: string; kind: Entry['kind']; depth: number; isExpanded: boolean }

export const joinPath = (dir: string, name: string): string => (dir === ROOT ? name : `${dir}/${name}`)

// 폴더 먼저, 그다음 이름순.
export const sortEntries = (entries: readonly Entry[]): Entry[] =>
  [...entries].sort((a, b) => {
    if ((a.kind === 'dir') !== (b.kind === 'dir')) {
      return a.kind === 'dir' ? -1 : 1
    }

    return a.name < b.name ? -1 : a.name > b.name ? 1 : 0
  })

// 펴진 폴더만 따라 내려가며 화면에 보일 줄을 위에서 아래 순서로 만든다.
export const visibleRows = (model: Model, dir: string = ROOT, depth = 0): Row[] =>
  (model.listed[dir] ?? []).flatMap(entry => {
    const path = joinPath(dir, entry.name)
    const isExpanded = entry.kind === 'dir' && model.expanded.includes(path)
    const row: Row = { path, name: entry.name, kind: entry.kind, depth, isExpanded }

    return isExpanded ? [row, ...visibleRows(model, path, depth + 1)] : [row]
  })

export const labelOf = (row: Row): string => {
  if (row.kind !== 'dir') {
    return `  ${row.name}`
  }

  return `${row.isExpanded ? '▾' : '▸'} ${row.name}/`
}
