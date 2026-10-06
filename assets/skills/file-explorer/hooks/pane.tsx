import { atom, read, update } from 'claude-code'
import type { EngineInterface, On } from 'claude-code'

import { ALL_PANES, MAX_EDIT_CHARS, PANE, ROOT, TREE_COLUMNS } from './constants'
import { STATUS_ARGV } from './git'
import { fromStatusRun, tabbed } from './gitstate'
import type { Actions } from './header'
import { layoutOf } from './layout'
import { frame } from './parts'
import { applied, failed, listedIn, opened, reverted, sane, savedNow, toggledEditing } from './reducers'
import type { Change } from './reducers'

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

// isQuiet: 트리 색을 위해 뒤에서 읽는 경우. 실패해도 알리지 않는다.
const loadStatus = ($: EngineInterface, isQuiet = false) =>
  $.process.run(STATUS_ARGV).then(
    ran => patch($, fromStatusRun(ran, isQuiet)),
    error => (isQuiet ? undefined : patch($, failed('git 을 실행하지 못했습니다', error))),
  )

const refresh = async ($: EngineInterface): Promise<void> => {
  const { expanded, open, tab } = sane(await read($, model))
  if (tab === 'git') {
    return loadStatus($)
  }
  await Promise.all([ROOT, ...expanded].map(dir => list($, dir)))
  if (open !== null) {
    await openFile($, open.path)
  }
  await loadStatus($, true)
}

const save = async ($: EngineInterface): Promise<void> => {
  const { open } = sane(await read($, model))
  if (open === null) {
    return
  }
  await $.fs.write(open.path, open.source).then(
    async () => {
      await patch($, savedNow())
      $.ui.toast(`저장했습니다: ${open.path}`)
      // 방금 저장한 파일의 트리 색이 바뀌도록
      await loadStatus($, true)
    },
    error => patch($, failed('저장하지 못했습니다', error)),
  )
}

// 패널 그리기와 머리줄 버튼. 마우스·휠·에디터 입력은 inputs.tsx 가 받는다.
export const registerPane = (on: On): void => {
  on('ui.render', { component: 'Pane', requestId: 'file-explorer' }, async ($, e) => {
    const ui = $.ui.resolve(e)
    const state = sane(await read($, model))
    const { room, win, tree, side } = layoutOf(state, e.props.scroll.bodyRows, e.props.bodyColumns)
    const actions: Actions = {
      // git 탭으로 갈 때마다 상태를 새로 읽는다.
      onTab: tab => patch($, tabbed(tab)).then(() => (tab === 'git' ? loadStatus($) : undefined)),
      onRefresh: () => refresh($),
      onClose: () => $.ui.close({ id: PANE }),
      // 하나가 거절돼도 나머지는 닫는다.
      onCloseAll: () => Promise.allSettled(ALL_PANES.map(id => $.ui.close({ id }))),
      onToggle: () => patch($, toggledEditing(MAX_EDIT_CHARS)),
      onSave: () => save($),
      onRevert: () => patch($, reverted()),
    }

    return frame(ui, state, win, tree, room, side, actions)
  })
}
