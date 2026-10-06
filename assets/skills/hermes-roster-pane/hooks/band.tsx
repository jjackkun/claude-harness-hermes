import { atom, read, update } from 'claude-code'
import type { On } from 'claude-code'

import { OPEN_KEY, PANE, ROSTER_ARGV, TITLE } from './constants'
import { paneColumns, toFailedView, toView } from './roster'

// 패널이 그리는 명부. 상태 참조는 엔진 규칙상 쓰는 파일 안에 직접 적는다.
const view = atom({ plugin: 'hermes-roster-pane', key: 'view' } as const, null)

// 프롬프트 위 띠에 여는 버튼을 둔다. 아래 모드가 그린 것이 있으면 그 옆에 붙인다.
// 명부가 읽힌 프로젝트에서만 그린다: 전역에 깔리면 헤르메스가 없는 프로젝트에서도 로드되는데,
// 눌러도 오류만 나는 버튼은 두지 않는다. 명부는 세션이 열릴 때 register.tsx 가 한 번 읽는다.
export const registerBand = (on: On): void => {
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const below = await next(e)

    const loaded = await read($, view)
    if (e.props.hasSurvey || loaded === null || !loaded.isOk) {
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
            // $ 는 파일을 넘지 못해 register.tsx 의 refresh 를 여기서 다시 쓴다.
            const loaded = await $.process.run(ROSTER_ARGV).then(toView, toFailedView)
            await update($, view, () => loaded)
            await $.ui.open({ id: PANE, title: TITLE, columns: paneColumns(loaded.lines) })
          }}
        />
      </Box>
    )
  })
}
