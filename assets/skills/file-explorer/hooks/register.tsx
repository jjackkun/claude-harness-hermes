import { atom, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import { CODE_COLUMNS, COMMAND, OPEN_KEY, PANE, ROOT, TITLE, TREE_COLUMNS } from './constants'
import { STATUS_ARGV } from './git'
import { fromStatusRun } from './gitstate'
import { registerInputs } from './inputs'
import { registerPane } from './pane'
import { applied, failed, listedIn, opened, projectAt } from './reducers'
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

// 루트 목록을 읽고 패널을 연다. 모드가 스스로 부른 열기는 자기 ui.open 훅을 거치지 않으므로 여기서 읽는다.
const openPane = async ($: EngineInterface): Promise<void> => {
  // 작업 폴더를 못 읽어도 패널은 연다(이름만 비운다).
  await patch($, projectAt(await $.session.cwd().then(path => path, () => '')))
  await $.fs.list().then(
    entries => patch($, listedIn(ROOT, entries)),
    error => patch($, failed('목록을 읽지 못했습니다', error)),
  )
  // 트리 색을 위한 git 상태. git 저장소가 아니거나 git 이 없으면 색 없이 연다.
  await $.process.run(STATUS_ARGV).then(
    ran => patch($, fromStatusRun(ran, true)),
    () => undefined,
  )
  await $.ui.open({ id: PANE, title: TITLE, columns: TREE_COLUMNS + CODE_COLUMNS })
}

export const register: Register = on => {
  registerPane(on)
  registerInputs(on)

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: COMMAND,
      description: '파일 탐색기 패널을 연다 (/files <경로> 로 파일을 바로 연다)',
    })

    return next(e)
  })

  on('command.run', { command: 'files' }, async ($, e) => {
    const path = e.args.trim()
    if (path !== '') {
      await $.fs.read(path).then(
        source => patch($, opened(path, source)),
        error => patch($, failed('파일을 읽지 못했습니다', error)),
      )
    }
    await openPane($)

    return { text: '파일 탐색기를 열었습니다.' }
  })

  // 프롬프트 위 띠에 여는 버튼을 둔다. 아래 모드가 그린 것이 있으면 그 옆에 붙인다.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const below = await next(e)
    if (e.props.hasSurvey) {
      return below
    }

    const { Box, Button } = $.ui.resolve(e)
    const hasBelow = typeof below === 'object' && below !== null && 'type' in below

    return (
      <Box>
        {hasBelow && below}
        <Button key={OPEN_KEY} label={TITLE} onPress={() => openPane($)} />
      </Box>
    )
  })
}
