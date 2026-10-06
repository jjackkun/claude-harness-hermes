import type { On } from 'claude-code'

import { PANE, TITLE } from './constants'

const OPEN_KEY = 'open-tool-calls'

// 프롬프트 위 띠에 패널을 여는 버튼 하나를 둔다. 아래 모드가 그린 것이 있으면 그 옆에 붙인다.
export const registerBand = (on: On): void => {
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
        <Button
          key={OPEN_KEY}
          label={TITLE}
          onPress={async () => {
            await $.ui.open({ id: PANE, title: TITLE })
          }}
        />
      </Box>
    )
  })
}
