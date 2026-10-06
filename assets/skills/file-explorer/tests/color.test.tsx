import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

const PLUGIN = 'file-explorer'
const PANE = {
  plugin: PLUGIN,
  surface: 'terminal',
  component: 'Pane',
  requestId: PLUGIN,
  props: {
    title: '파일',
    isFocused: false,
    bodyColumns: 118,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 13 },
    view: {},
  },
} as const
const BAND = {
  plugin: PLUGIN,
  surface: 'terminal',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 3, bodyColumns: 80 },
} as const
const SOURCE = 'def f():  # 주석\n    return "x" + 1\n'

// 엔진 자리: 파이썬 파일 하나(run.py)가 있는 폴더.
const standIn = (on: On): void => {
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.render', async ($$, e) => {
    const { Text } = $$.ui.resolve(e)

    return <Text> </Text>
  })
  on('fs.list', async () => ({ value: [{ name: 'run.py', kind: 'file', size: 0, mtimeMs: 0 }] }))
  on('fs.read', async () => ({ value: SOURCE }))
}

const openFile = async ($: Engine) => {
  const band = await $.ui.mount(BAND)
  await band.press({ key: 'open-files' })
  await band.unmount()
  const ui = await $.ui.mount(PANE)
  await ui.pointer({ type: 'down', x: 2, y: 0, in: 'tree' })

  return ui
}

// 글자 조각 → 그 조각에 붙은 색·굵기·흐림 속성.
const styles = (found: readonly { text?: string; props?: Record<string, unknown> }[]) =>
  Object.fromEntries(found.map(one => [one.text ?? '', one.props ?? {}]))

test('읽기 화면: 파이썬 파일의 예약어·함수 이름·문자열·숫자·주석에 서로 다른 색이 붙는다', async ($, on) => {
  // Arrange · Act
  standIn(on)
  const ui = await openFile($)

  // Assert
  const by = styles(await ui.findAll({ type: 'Text' }))
  expect(by['def']).toEqual({ color: 'suggestion' })
  expect(by['f']).toEqual({ color: 'remember' })
  expect(by['return']).toEqual({ color: 'suggestion' })
  expect(by['"x"']).toEqual({ color: 'success' })
  expect(by['1']).toEqual({ color: 'warning' })
  expect(by['# 주석']).toEqual({ dimColor: true })
  // 연산자는 색 없이 기본색
  expect(by['+']).toEqual({})
  await ui.unmount()
})

test('편집 화면: 같은 색이 붙고, 커서가 놓인 글자는 색을 유지한 채 반전된다', async ($, on) => {
  // Arrange
  standIn(on)
  const ui = await openFile($)

  // Act
  await ui.press({ key: 'mode' })

  // Assert — 커서는 첫 줄 첫 글자(def 의 d)
  const by = styles(await ui.findAll({ type: 'Text', in: 'editor' }))
  expect(by['d']).toEqual({ color: 'suggestion', inverse: true })
  expect(by['ef']).toEqual({ color: 'suggestion' })
  expect(by['return']).toEqual({ color: 'suggestion' })
  expect(by['"x"']).toEqual({ color: 'success' })
  expect(by['# 주석']).toEqual({ dimColor: true })
  await ui.unmount()
})
