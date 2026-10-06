import { expect, test } from 'claude-code/testing'

const PLUGIN = 'hermes-roster-pane'
const PANE = {
  plugin: PLUGIN,
  surface: 'terminal',
  component: 'Pane',
  requestId: PLUGIN,
  props: {
    title: '에이전트 명부',
    isFocused: false,
    bodyColumns: 80,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const
const ran = (exitCode: number, stdout: string, stderr: string) => ({
  value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false },
})

test('불러오기 전에는 안내를 보인다', async $ => {
  // Arrange · Act
  const ui = await $.ui.mount(PANE)

  // Assert
  expect(await ui.find({ type: 'Text', text: '명부를 아직 불러오지 않았습니다.' })).toBeDefined()
  await ui.unmount()
})

test('새로고침을 누르면 명부 명령의 출력 줄을 그대로 보인다', async ($, on) => {
  // Arrange
  const argvs: string[][] = []
  on('process.run', async (_$, e) => {
    argvs.push([...e.argv])

    return ran(0, '이름  호출\n\n품질지기  @agent-quality\n', '')
  })
  const ui = await $.ui.mount(PANE)

  // Act
  await ui.press({ key: 'refresh' })

  // Assert
  expect(argvs).toEqual([['python3', 'scripts/hermes-agent.py', '--project', '.', 'roster']])
  expect(await ui.find({ type: 'Text', text: '품질지기  @agent-quality' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '명부를 읽지 못했습니다.' })).toBeUndefined()
  await ui.unmount()
})

test('명령이 실패하면 오류 머리말과 stderr 를 보인다', async ($, on) => {
  // Arrange
  on('process.run', async () => ran(2, '', "python3: can't open file\n"))
  const ui = await $.ui.mount(PANE)

  // Act
  await ui.press({ key: 'refresh' })

  // Assert
  expect(await ui.find({ type: 'Text', text: '명부를 읽지 못했습니다.' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: "python3: can't open file" })).toBeDefined()
  await ui.unmount()
})

test('명령을 시작조차 못 하면 그 이유를 보인다', async ($, on) => {
  // Arrange
  on('process.run', async () => {
    throw new Error('python3 not found')
  })
  const ui = await $.ui.mount(PANE)

  // Act
  await ui.press({ key: 'refresh' })

  // Assert
  expect(await ui.find({ type: 'Text', text: '명부를 읽지 못했습니다.' })).toBeDefined()
  await ui.unmount()
})

test('닫기는 명부 패널만, 전체 닫기는 세 패널을 모두 닫으려 한다', async ($, on) => {
  const ids: string[] = []
  on('ui.close', async (_$, e) => {
    ids.push(e.id)

    return { value: null }
  })
  const ui = await $.ui.mount(PANE)

  await ui.press({ key: 'close' })
  expect(ids).toEqual(['hermes-roster-pane'])

  await ui.press({ key: 'close-all' })
  expect(ids.slice(1).sort()).toEqual(['file-explorer', 'hermes-roster-pane', 'tool-calls-pane'])
  await ui.unmount()
})
