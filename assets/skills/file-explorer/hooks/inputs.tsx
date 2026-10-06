import { atom, read, update } from 'claude-code'
import type { EngineInterface, On } from 'claude-code'

import { DIVIDER_KEY, EDITOR_KEY, GIT_LIST_KEY, HBAR_KEY, HEADER_ROWS, ROOT, TREE_COLUMNS, TREE_KEY } from './constants'
import { diffArgv } from './git'
import type { GitFile } from './git'
import { fromDiffRun } from './gitstate'
import { isSource, numberIn } from './messages'
import { applied, collapsed, edited, expandedWith, failed, listedIn, opened, sane } from './reducers'
import type { Change } from './reducers'
import { regionOf, resizedTree, shiftedTo, wheeled } from './scrolling'
import { visibleRows } from './tree'
import type { Row } from './tree'

// 상태 참조는 엔진 규칙상 쓰는 파일 안에 직접 적는다.
const model = atom({ plugin: 'file-explorer', key: 'model' } as const, {
  listed: {},
  expanded: [],
  treeTop: 0,
  treeColumns: TREE_COLUMNS,
  open: null,
  notice: null,
  tab: 'editor',
  project: '',
  git: null,
})

const patch = ($: EngineInterface, change: Change) => update($, model, applied(change))

const list = ($: EngineInterface, dir: string) =>
  $.fs.list(dir === ROOT ? undefined : dir).then(
    entries => patch($, listedIn(dir, entries)),
    error => patch($, failed('목록을 읽지 못했습니다', error)),
  )

const openFile = ($: EngineInterface, path: string) =>
  $.fs.read(path).then(
    source => patch($, opened(path, source)),
    error => patch($, failed('파일을 읽지 못했습니다', error)),
  )

const pressRow = async ($: EngineInterface, row: Row): Promise<void> => {
  if (row.kind !== 'dir') {
    await openFile($, row.path)
  } else if (row.isExpanded) {
    await patch($, collapsed(row.path))
  } else {
    await list($, row.path)
    await patch($, expandedWith(row.path))
  }
}

const loadDiff = ($: EngineInterface, file: GitFile) =>
  $.process.run(diffArgv(file)).then(
    ran => patch($, fromDiffRun(file, ran)),
    error => patch($, failed('git 을 실행하지 못했습니다', error)),
  )

// 화면 모듈(에디터·트리·git 목록·가로 막대)이 보낸 값과 휠을 받는다.
export const registerInputs = (on: On): void => {
  on('ui.message', async ($, e) => {
    const row = numberIn(e.data, 'row')
    const left = numberIn(e.data, 'left')
    const width = numberIn(e.data, 'width')
    if (e.element === EDITOR_KEY && isSource(e.data)) {
      // 에디터가 보낸 전체 내용을 화면의 내용으로 삼는다.
      await patch($, edited(e.data.source))
    } else if (e.element === TREE_KEY && row !== null) {
      const target = visibleRows(sane(await read($, model)))[row]
      if (target !== undefined) {
        await pressRow($, target)
      }
    } else if (e.element === GIT_LIST_KEY && row !== null) {
      const file = sane(await read($, model)).git?.files[row]
      if (file !== undefined) {
        await loadDiff($, file)
      }
    } else if (e.element === DIVIDER_KEY && width !== null) {
      await patch($, resizedTree(width))
    } else if (e.element === HBAR_KEY && left !== null) {
      await patch($, shiftedTo(left))
    }

    return {}
  })

  // 휠·스크롤 키: 엔진이 패널을 통째로 옮기는 대신, 마우스가 있던 곳(트리, 파일, 가로 막대)에 맞춰 옮긴다.
  on('ui.scroll', { requestId: 'file-explorer' }, async ($, e) => {
    const region = regionOf(e.pointer, e.bodyRows, sane(await read($, model)).treeColumns)
    await patch($, wheeled(e.by, Math.max(1, e.bodyRows - HEADER_ROWS), region))

    return {}
  })
}
