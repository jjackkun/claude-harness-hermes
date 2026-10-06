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
type Drawn = Awaited<ReturnType<Engine['ui']['mount']>>
const entry = (name: string, kind: 'file' | 'dir') => ({ name, kind, size: 0, mtimeMs: 0 })
const ROOT_ENTRIES = [entry('b.md', 'file'), entry('src', 'dir'), entry('a.md', 'file')]
const TWENTY_LINES = Array.from({ length: 20 }, (_, i) => `L${i + 1}`).join('\n') + '\n'
// 보기 폭: 패널 118 - 트리 32 - 간격 1 = 85칸. 줄 번호 6칸과 세로 막대 1칸을 빼면 글자 자리 78칸.
const VIEW_COLUMNS = 85
const LONG_LINE = Array.from({ length: 30 }, (_, i) => `w${String(i).padStart(2, '0')}`).join(' ')

// 엔진 자리: 패널 열기를 받아 주고, 띠 아래에는 아무 모드도 없다고 답한다.
const standIn = (on: On): void => {
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.render', async ($$, e) => {
    const { Text } = $$.ui.resolve(e)

    return <Text> </Text>
  })
}

// 사용자가 하듯 프롬프트 위 [ 파일 ] 버튼을 눌러 패널을 연다.
const openByButton = async ($: Engine): Promise<Drawn> => {
  const band = await $.ui.mount(BAND)
  await band.press({ key: 'open-files' })
  await band.unmount()

  return $.ui.mount(PANE)
}

// 트리의 보이는 줄 n 번째를 마우스로 누른다.
const clickRow = (ui: Drawn, n: number) => ui.pointer({ type: 'down', x: 2, y: n, in: 'tree' })
const treeTexts = async (ui: Drawn) => (await ui.findAll({ type: 'Text', in: 'tree' })).map(one => one.text)

test('처음에는 고르라는 안내를 보인다', async $ => {
  const ui = await $.ui.mount(PANE)

  expect(await ui.find({ type: 'Text', text: '왼쪽에서 파일을 누르십시오.' })).toBeDefined()
  await ui.unmount()
})

test('패널이 열리면 루트 목록을 폴더 먼저 이름순으로 보인다', async ($, on) => {
  on('fs.list', async () => ({ value: ROOT_ENTRIES }))
  standIn(on)

  const ui = await openByButton($)

  expect(await treeTexts(ui)).toEqual(['▸ src/', '  a.md', '  b.md'])
  await ui.unmount()
})

test('폴더 줄을 마우스로 누르면 펴지고 다시 누르면 접힌다', async ($, on) => {
  // Arrange
  const asked: (string | undefined)[] = []
  on('fs.list', async (_$, e) => {
    asked.push(e.path)

    return { value: e.path?.endsWith('/src') ? [entry('main.ts', 'file')] : ROOT_ENTRIES }
  })
  standIn(on)
  const ui = await openByButton($)

  // Act · Assert — 엔진이 상대 경로를 절대 경로로 바꿔 넘긴다: 루트 한 번, 그 아래 src 한 번
  await clickRow(ui, 0)
  expect(asked.length).toBe(2)
  expect(asked[1]).toBe(`${asked[0]}/src`)
  expect(await treeTexts(ui)).toEqual(['▾ src/', '    main.ts', '  a.md', '  b.md'])

  await clickRow(ui, 0)
  expect(await treeTexts(ui)).toEqual(['▸ src/', '  a.md', '  b.md'])
  await ui.unmount()
})

test('파일 줄을 누르면 화면 높이만큼 보이고, 다 보이지 않으면 세로 막대가 선다', async ($, on) => {
  // Arrange
  const read: string[] = []
  on('fs.list', async () => ({ value: ROOT_ENTRIES }))
  on('fs.read', async (_$, e) => {
    read.push(e.path)

    return { value: TWENTY_LINES }
  })
  standIn(on)
  const ui = await openByButton($)

  // Act
  await clickRow(ui, 1)

  // Assert — 몸통 13행 - 머리 3행 - 가로 막대 1행 = 9줄
  expect(read.length).toBe(1)
  expect(read[0]?.endsWith('/a.md')).toBe(true)
  expect(await ui.find({ type: 'Text', text: 'a.md 20줄' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^L9$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^L10$/ })).toBeUndefined()
  // 20줄 가운데 9줄이 보인다 → 9칸 막대에 손잡이 4칸(9×9÷20 을 반올림)
  expect((await ui.findAll({ type: 'Text', text: '█' })).length).toBe(4)
  expect((await ui.findAll({ type: 'Text', text: '│' })).length).toBe(5)
  await ui.unmount()
})

test('파일을 읽지 못하면 알림 줄에 이유를 보인다', async ($, on) => {
  on('fs.list', async () => ({ value: ROOT_ENTRIES }))
  on('fs.read', async () => {
    throw new Error('binary file')
  })
  standIn(on)
  const ui = await openByButton($)

  await clickRow(ui, 1)

  expect(await ui.find({ type: 'Text', text: '파일을 읽지 못했습니다' })).toBeDefined()
  await ui.unmount()
})

test('잘린 줄이 있으면 가로 막대가 생기고, 오른쪽 끝을 누르면 넘어가고 왼쪽 끝을 누르면 돌아온다', async ($, on) => {
  // Arrange — 119자 한 줄(글자 자리 78칸을 넘는다)과 짧은 줄
  on('fs.list', async () => ({ value: ROOT_ENTRIES }))
  on('fs.read', async () => ({ value: `${LONG_LINE}\nshort\n` }))
  standIn(on)
  const ui = await openByButton($)
  await clickRow(ui, 1)
  expect(await ui.find({ type: 'Client', key: 'hbar' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^w00 / })).toBeDefined()

  // Act — 막대의 오른쪽 끝 화살표
  await ui.pointer({ type: 'down', x: VIEW_COLUMNS - 1, y: 0, in: 'hbar' })

  // Assert — 글자 자리의 절반(39자)을 건너뛴 자리부터: 낱말 하나가 4자, w09 는 36~38번째, 39번째는 그 뒤 공백
  expect(await ui.find({ type: 'Text', text: /^w00 / })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^ w10 w11 / })).toBeDefined()

  await ui.pointer({ type: 'down', x: 0, y: 0, in: 'hbar' })
  expect(await ui.find({ type: 'Text', text: /^w00 / })).toBeDefined()
  await ui.unmount()
})

test('잘린 줄이 없으면 가로 막대가 없다', async ($, on) => {
  on('fs.list', async () => ({ value: ROOT_ENTRIES }))
  on('fs.read', async () => ({ value: 'short\n' }))
  standIn(on)
  const ui = await openByButton($)

  await clickRow(ui, 1)

  expect(await ui.find({ type: 'Client', key: 'hbar' })).toBeUndefined()
  await ui.unmount()
})

// 엔진 자리에서 받은 닫기 요청의 패널 이름을 모은다.
const closes = (on: On): string[] => {
  const ids: string[] = []
  on('ui.close', async (_$, e) => {
    ids.push(e.id)

    return { value: null }
  })

  return ids
}

test('닫기는 파일 패널만, 전체 닫기는 세 패널을 모두 닫으려 한다', async ($, on) => {
  const ids = closes(on)
  const ui = await $.ui.mount(PANE)

  await ui.press({ key: 'close' })
  expect(ids).toEqual(['file-explorer'])

  await ui.press({ key: 'close-all' })
  expect(ids.slice(1).sort()).toEqual(['file-explorer', 'hermes-roster-pane', 'tool-calls-pane'])
  await ui.unmount()
})
