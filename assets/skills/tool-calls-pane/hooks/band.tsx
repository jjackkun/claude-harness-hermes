import type { EngineInterface, On, RenderInput } from 'claude-code'

import { BAND_HOST, PANE, TITLE } from './constants'

const OPEN_KEY = 'open-tool-calls'
const PLUGIN = 'tool-calls-pane'

// 띠 한 줄: 아래 모드가 그린 것(below) 오른쪽에 패널을 여는 버튼 하나를 가로로 붙인다.
async function drawBand($: EngineInterface, e: RenderInput<'AbovePrompt'>, below: unknown) {
  if (e.props.hasSurvey) {
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
          await $.ui.open({ id: PANE, title: TITLE })
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
