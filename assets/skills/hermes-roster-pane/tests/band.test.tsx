import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

const BAND = {
  plugin: 'hermes-roster-pane',
  surface: 'terminal',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 3, bodyColumns: 80 },
} as const
const ran = (exitCode: number, stdout: string, stderr: string) => ({
  value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false },
})
type Seen = { runs: number; opened: string[] }

// 엔진 자리: 띠 아래에는 다른 모드의 버튼이 하나 있고, 명부 명령은 exitCode 로 답한다.
const standIn = (on: On, exitCode: number): Seen => {
  const seen: Seen = { runs: 0, opened: [] }
  on('ui.render', async ($$, e) => {
    const { Button } = $$.ui.resolve(e)

    return <Button key="below" label="아래 모드 버튼" onPress={() => {}} />
  })
  on('command.register', async () => ({ value: null }))
  on('process.run', async () => {
    seen.runs += 1

    return exitCode === 0 ? ran(0, '이름  호출\n', '') : ran(exitCode, '', "python3: can't open file\n")
  })
  on('ui.open', async (_$, e) => {
    seen.opened.push(e.id)

    return { value: { isPlaced: true } }
  })
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))

  return seen
}
// 세션이 열릴 때 모드가 명부를 한 번 읽는다.
const startSession = ($: Engine) => $.session.start({ cwd: '/home/someone/project', source: 'startup' })

test('명부가 읽히는 프로젝트: 띠 버튼이 아래 모드의 버튼 옆에 서고, 누르면 명부를 다시 읽어 패널을 연다', async ($, on) => {
  // Arrange
  const seen = standIn(on, 0)
  await startSession($)
  const ui = await $.ui.mount(BAND)
  expect(await ui.find({ type: 'Button', text: '에이전트 명부' })).toBeDefined()
  expect(await ui.find({ type: 'Button', text: '아래 모드 버튼' })).toBeDefined()
  const runsBefore = seen.runs

  // Act
  await ui.press({ key: 'open-roster' })

  // Assert
  expect(seen.runs).toBe(runsBefore + 1)
  expect(seen.opened.at(-1)).toBe('hermes-roster-pane')
  await ui.unmount()
})

test('명부가 읽히지 않는 프로젝트(헤르메스 없음): 띠에 명부 버튼을 그리지 않고 아래 모드의 버튼만 둔다', async ($, on) => {
  // Arrange — 명부 명령이 종료 코드 2
  const seen = standIn(on, 2)

  // Act
  await startSession($)
  const ui = await $.ui.mount(BAND)

  // Assert — 패널도 혼자 열리지 않는다
  expect(await ui.find({ type: 'Button', text: '에이전트 명부' })).toBeUndefined()
  expect(await ui.find({ type: 'Button', text: '아래 모드 버튼' })).toBeDefined()
  expect(seen.opened).toEqual([])
  await ui.unmount()
})

test('세션이 열리기 전(명부를 아직 읽지 않음)에는 명부 버튼을 그리지 않는다', async ($, on) => {
  standIn(on, 0)

  const ui = await $.ui.mount(BAND)

  expect(await ui.find({ type: 'Button', text: '에이전트 명부' })).toBeUndefined()
  expect(await ui.find({ type: 'Button', text: '아래 모드 버튼' })).toBeDefined()
  await ui.unmount()
})
