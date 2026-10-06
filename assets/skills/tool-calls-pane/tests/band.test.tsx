import { expect, test } from 'claude-code/testing'

const PLUGIN = 'tool-calls-pane'
const BAND = {
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 3, bodyColumns: 80 },
} as const

test('띠의 버튼을 누르면 도구 호출 패널을 연다', async ($, on) => {
  // Arrange
  const opened: string[] = []
  on('ui.open', async (_$, e) => {
    opened.push(e.id)

    return { value: { isPlaced: true } }
  })
  on('ui.render', async ($$, e) => {
    const { Button } = $$.ui.resolve(e)

    return <Button key="below" label="아래 모드 버튼" onPress={() => {}} />
  })
  const ui = await $.ui.mount({ plugin: PLUGIN, surface: 'terminal', ...BAND })

  // Act
  await ui.press({ key: 'open-tool-calls' })

  // Assert
  expect(await ui.find({ type: 'Button', text: '도구 호출' })).toBeDefined()
  expect(await ui.find({ type: 'Button', text: '아래 모드 버튼' })).toBeDefined()
  expect(opened).toContain('tool-calls-pane')
  await ui.unmount()
})

test('설문이 떠 있으면 띠를 그리지 않는다', async ($, on) => {
  // Arrange · Act
  on('ui.render', async ($$, e) => {
    const { Text } = $$.ui.resolve(e)

    return <Text>엔진이 그린 띠</Text>
  })
  const ui = await $.ui.mount({
    plugin: PLUGIN,
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { ...BAND.props, hasSurvey: true },
  })

  // Assert
  expect(await ui.find({ type: 'Button', text: '도구 호출' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: '엔진이 그린 띠' })).toBeDefined()
  await ui.unmount()
})
