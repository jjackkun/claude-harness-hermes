import { atom, read, update } from 'claude-code'
import type { EngineInterface, On, RenderInput } from 'claude-code'

import { BAND_HOST, OPEN_KEY, PANE, ROSTER_ARGV, TITLE } from './constants'
import { paneColumns, toFailedView, toView } from './roster'

const PLUGIN = 'hermes-roster-pane'

// 패널이 그리는 명부. 상태 참조는 엔진 규칙상 쓰는 파일 안에 직접 적는다.
const view = atom({ plugin: 'hermes-roster-pane', key: 'view' } as const, null)

// 띠 한 줄: 아래 모드가 그린 것(below) 오른쪽에 명부를 여는 버튼을 가로로 붙인다.
// 명부가 읽힌 프로젝트에서만 그린다: 전역에 깔리면 헤르메스가 없는 프로젝트에서도 로드되는데,
// 눌러도 오류만 나는 버튼은 두지 않는다. 명부는 세션이 열릴 때 register.tsx 가 한 번 읽는다.
async function drawBand($: EngineInterface, e: RenderInput<'AbovePrompt'>, below: unknown) {
  const loaded = await read($, view)
  if (e.props.hasSurvey || loaded === null || !loaded.isOk) {
    return below
  }

  const { Box, Button } = $.ui.resolve(e)
  const hasBelow = typeof below === 'object' && below !== null && 'type' in below

  return (
    <Box flexDirection="row" gap={1}>
      {hasBelow && below}
      <Button
        key={OPEN_KEY}
        label={TITLE}
        onPress={async () => {
          // $ 는 파일을 넘지 못해 register.tsx 의 refresh 를 여기서 다시 쓴다.
          const loaded = await $.process.run(ROSTER_ARGV).then(toView, toFailedView)
          await update($, view, () => loaded)
          await $.ui.open({ id: PANE, title: TITLE, columns: paneColumns(loaded.lines) })
        }}
      />
    </Box>
  )
}

// 엔진(2.1.325~)은 띠를 모드마다 한 줄로 세로로 쌓는다. 버튼을 가로로 두려고
// 주인 모드(파일)의 줄 오른쪽에 버튼을 붙이고, 주인 줄이 있으면 이 모드의 줄은 띠에서 뺀다.
// 주인 모드가 깔려 있지 않으면 이 모드의 줄에 버튼 하나만 그린다.
export const registerBand = (on: On): void => {
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => drawBand($, e, await next(e)))
  on('ui.render', { component: 'AbovePrompt', plugin: BAND_HOST }, async ($, e, next) => drawBand($, e, await next(e)))
  on('ui.render', { component: 'AbovePromptList' }, async (_$, e, next) => {
    const hasHost = e.props.rows.some(row => row.plugin === BAND_HOST)
    if (!hasHost) return next(e)

    return next({ ...e, props: { ...e.props, rows: e.props.rows.filter(row => row.plugin !== PLUGIN) } })
  })
}
