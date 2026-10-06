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
const STATUS = '## main...origin/main [ahead 1]\n M docs/a.md\n?? new.txt\n'
const DIFF = '@@ -1,2 +1,2 @@\n-old line\n+new line\n same\n'
const ran = (exitCode: number, stdout: string, stderr = '') => ({
  value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false },
})

// 엔진 자리: 작업 폴더, 파일 하나, 그리고 git 명령(status 와 diff)에 답한다. 실행된 명령은 argvs 에 모은다.
const standIn = (on: On, argvs: string[][], status = ran(0, STATUS)): void => {
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.render', async ($$, e) => {
    const { Text } = $$.ui.resolve(e)

    return <Text> </Text>
  })
  on('session.cwd', async () => ({ value: '/home/someone/work/my-project' }))
  on('fs.list', async () => ({ value: [{ name: 'a.md', kind: 'file', size: 0, mtimeMs: 0 }] }))
  on('process.run', async (_$, e) => {
    argvs.push([...e.argv])

    return e.argv.includes('status') ? status : ran(0, DIFF)
  })
}

const openPane = async ($: Engine) => {
  const band = await $.ui.mount(BAND)
  await band.press({ key: 'open-files' })
  await band.unmount()

  return $.ui.mount(PANE)
}
const styles = (found: readonly { text?: string; props?: Record<string, unknown> }[]) =>
  Object.fromEntries(found.map(one => [one.text ?? '', one.props ?? {}]))

test('탭 두 개와 프로젝트(폴더) 이름이 보이고, 처음에는 editor 탭이다', async ($, on) => {
  standIn(on, [])

  const ui = await openPane($)

  expect((await ui.find({ key: 'tab-editor' }))?.props?.variant).toBe('primary')
  expect((await ui.find({ key: 'tab-git' }))?.props?.variant).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^my-project$/ })).toBeDefined()
  expect((await ui.findAll({ type: 'Text', in: 'tree' })).map(one => one.text)).toEqual(['  a.md'])
  await ui.unmount()
})

test('git 탭을 누르면 상태를 읽어 브랜치와 바뀐 파일 목록을 보인다', async ($, on) => {
  const argvs: string[][] = []
  standIn(on, argvs)
  const ui = await openPane($)

  await ui.press({ key: 'tab-git' })

  // 열 때 한 번(트리 색), git 탭을 누를 때 한 번
  expect(argvs.length).toBe(2)
  expect(argvs[1]?.slice(3)).toEqual(['status', '--porcelain=v1', '--branch', '--untracked-files=all'])
  expect((await ui.find({ key: 'tab-git' }))?.props?.variant).toBe('primary')
  expect(await ui.find({ type: 'Text', text: 'main...origin/main [ahead 1] · 바뀐 파일 2개' })).toBeDefined()
  expect((await ui.findAll({ type: 'Text', in: 'gitlist' })).map(one => one.text)).toEqual([' M docs/a.md', '?? new.txt'])
  expect(await ui.find({ type: 'Text', text: '왼쪽에서 바뀐 파일을 누르십시오.' })).toBeDefined()
  await ui.unmount()
})

test('바뀐 파일을 누르면 변경 내용을 읽어, 지워진 줄과 추가된 줄에 서로 다른 색을 붙인다', async ($, on) => {
  const argvs: string[][] = []
  standIn(on, argvs)
  const ui = await openPane($)
  await ui.press({ key: 'tab-git' })

  await ui.pointer({ type: 'down', x: 2, y: 0, in: 'gitlist' })

  expect(argvs[2]?.slice(3)).toEqual(['diff', 'HEAD', '--', 'docs/a.md'])
  const by = styles(await ui.findAll({ type: 'Text' }))
  expect(by['old line']).toEqual({ color: 'error' })
  expect(by['new line']).toEqual({ color: 'success' })
  expect(by['@@ -1,2 +1,2 @@']).toEqual({ color: 'claude' })
  await ui.unmount()
})

test('새 파일(??)을 누르면 빈 파일과 견주는 명령을 쓴다', async ($, on) => {
  const argvs: string[][] = []
  standIn(on, argvs)
  const ui = await openPane($)
  await ui.press({ key: 'tab-git' })

  await ui.pointer({ type: 'down', x: 2, y: 1, in: 'gitlist' })

  expect(argvs[2]?.slice(3)).toEqual(['diff', '--no-index', '--', '/dev/null', 'new.txt'])
  await ui.unmount()
})

test('git 저장소가 아니면 이유를 알림 줄에 보이고, editor 탭으로 돌아가면 트리가 다시 보인다', async ($, on) => {
  standIn(on, [], ran(128, '', 'fatal: not a git repository\n'))
  const ui = await openPane($)

  await ui.press({ key: 'tab-git' })
  expect(await ui.find({ type: 'Text', text: 'git 상태를 읽지 못했습니다: fatal: not a git repository' })).toBeDefined()

  await ui.press({ key: 'tab-editor' })
  expect((await ui.findAll({ type: 'Text', in: 'tree' })).map(one => one.text)).toEqual(['  a.md'])
  await ui.unmount()
})

test('git 목록의 줄에 상태별 색이 붙는다 — 스테이징한 파일은 초록, 안 한 변경과 새 파일은 빨강', async ($, on) => {
  standIn(on, [], ran(0, '## main\nA  src/staged.ts\n M docs/a.md\n?? new.txt\n'))
  const ui = await openPane($)

  await ui.press({ key: 'tab-git' })

  const by = styles(await ui.findAll({ type: 'Text', in: 'gitlist' }))
  expect(by['A  src/staged.ts']).toEqual({ color: 'success', dimColor: false })
  expect(by[' M docs/a.md']).toEqual({ color: 'error', dimColor: false })
  expect(by['?? new.txt']).toEqual({ color: 'error', dimColor: false })
  await ui.unmount()
})

test('editor 탭의 파일 트리 줄에는 색을 붙이지 않는다', async ($, on) => {
  standIn(on, [])

  const ui = await openPane($)

  const by = styles(await ui.findAll({ type: 'Text', in: 'tree' }))
  expect(by['  a.md']).toEqual({ dimColor: true })
  await ui.unmount()
})

test('editor 탭의 트리: 바뀐 파일과 그 파일을 품은 폴더에 색이 붙고, 그대로인 줄은 색이 없다', async ($, on) => {
  // Arrange — 루트에 폴더 docs 와 파일 둘. docs 안의 파일 하나가 고쳐졌고 scratch.txt 는 새 파일이다.
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.render', async ($$, e) => {
    const { Text } = $$.ui.resolve(e)

    return <Text> </Text>
  })
  on('fs.list', async () => ({
    value: [
      { name: 'docs', kind: 'dir', size: 0, mtimeMs: 0 },
      { name: 'README.md', kind: 'file', size: 0, mtimeMs: 0 },
      { name: 'scratch.txt', kind: 'file', size: 0, mtimeMs: 0 },
    ],
  }))
  on('process.run', async () => ran(0, '## main\n M docs/a.md\n?? scratch.txt\n'))

  // Act
  const ui = await openPane($)

  // Assert — 색이 붙은 줄은 흐리게 하지 않는다
  const by = styles(await ui.findAll({ type: 'Text', in: 'tree' }))
  expect(by['▸ docs/']).toEqual({ color: 'claude', dimColor: false })
  expect(by['  scratch.txt']).toEqual({ color: 'success', dimColor: false })
  expect(by['  README.md']).toEqual({ dimColor: true })
  await ui.unmount()
})
