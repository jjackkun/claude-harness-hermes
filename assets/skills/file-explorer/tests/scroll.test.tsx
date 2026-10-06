import { expect, test } from 'claude-code/testing'

import { sane } from '../hooks/reducers'
import { regionOf, shiftedTo, wheeled } from '../hooks/scrolling'
import { barOf } from '../hooks/view'
import type { Model } from '../types'

const TEN_LINES = Array.from({ length: 10 }, (_, i) => `L${i + 1}`).join('\n') + '\n'
const model = (over: Partial<Model> = {}): Model =>
  sane({
    listed: { '': Array.from({ length: 8 }, (_, i) => ({ name: `f${i}`, kind: 'file' as const })) },
    expanded: [],
    treeTop: 0,
    open: { path: 'a.md', source: TEN_LINES, saved: TEN_LINES, top: 0, left: 0, wheel: 0, isEditing: false, revision: 1 },
    notice: null,
    ...over,
  })
const bar = (flags: readonly boolean[] | null) => flags?.map(flag => (flag ? '#' : '.')).join('') ?? null

test('스크롤 막대: 전부 보이면 없고, 아니면 보이는 비율만큼의 손잡이가 건너뛴 비율 자리에 놓인다', () => {
  expect(bar(barOf(0, 10, 10, 10))).toBe(null)
  expect(bar(barOf(0, 5, 10, 10))).toBe('#####.....')
  expect(bar(barOf(5, 5, 10, 10))).toBe('.....#####')
  expect(bar(barOf(2, 5, 20, 8))).toBe('.##.....')
})

test('스크롤 막대: 손잡이는 아무리 작아도 한 칸이고 끝을 넘지 않는다', () => {
  expect(bar(barOf(0, 1, 1000, 4))).toBe('#...')
  expect(bar(barOf(999, 1, 1000, 4))).toBe('...#')
})

test('읽기 화면의 휠: 파일의 맨 윗줄을 옮기고, 처음과 끝에서 멈춘다', () => {
  // 몸통 5행 가운데 가로 막대 1행을 빼면 4줄이 보인다 → 10줄 파일의 마지막 맨 윗줄은 6
  const down = { ...model(), ...wheeled(3, 5, 'file')(model()) }

  expect(down.open?.top).toBe(3)
  expect({ ...down, ...wheeled(99, 5, 'file')(down) }.open?.top).toBe(6)
  expect({ ...down, ...wheeled(-99, 5, 'file')(down) }.open?.top).toBe(0)
})

test('트리 위의 휠: 파일은 그대로 두고 트리만 넘기며, 끝에서 멈춘다', () => {
  // 트리 8줄, 몸통 5행 → 마지막 맨 윗줄은 3
  const moved = { ...model(), ...wheeled(99, 5, 'tree')(model()) }

  expect(moved.treeTop).toBe(3)
  expect(moved.open?.top).toBe(0)
})

test('편집 화면의 휠: 맨 윗줄은 건드리지 않고 누적값만 더한다', () => {
  const editing = model({ open: { ...model().open!, isEditing: true } })
  const moved = { ...editing, ...wheeled(2, 5, 'file')(editing) }

  expect(moved.open?.wheel).toBe(2)
  expect(moved.open?.top).toBe(0)
})

test('좌우 이동: 왼쪽으로 건너뛴 글자 수를 그대로 놓되 0 아래로는 가지 않는다', () => {
  expect({ ...model(), ...shiftedTo(39)(model()) }.open?.left).toBe(39)
  expect({ ...model(), ...shiftedTo(-5)(model()) }.open?.left).toBe(0)
})

test('가로 막대 위의 휠: 읽기 화면을 좌우로 옮긴다 — 한 칸에 4자, 가장 긴 줄의 마지막 글자에서 멈춘다', () => {
  const wide = model({ open: { ...model().open!, source: `${'x'.repeat(30)}\nshort\n` } })
  const right = { ...wide, ...wheeled(2, 5, 'hbar')(wide) }

  expect(right.open?.left).toBe(8)
  expect(right.open?.top).toBe(0)
  expect({ ...right, ...wheeled(99, 5, 'hbar')(right) }.open?.left).toBe(29)
  expect({ ...right, ...wheeled(-99, 5, 'hbar')(right) }.open?.left).toBe(0)
})

test('편집 화면에서는 가로 막대 자리의 휠도 위아래로 넘긴다(가로 막대가 없다)', () => {
  const editing = model({ open: { ...model().open!, isEditing: true } })
  const moved = { ...editing, ...wheeled(2, 5, 'hbar')(editing) }

  expect(moved.open?.wheel).toBe(2)
  expect(moved.open?.left).toBe(0)
})

test('휠이 있던 곳: 트리 폭 안이면 트리, 몸통 맨 아래 행이면 가로 막대, 칸을 모르면 파일', () => {
  expect(regionOf({ column: 5, row: 11 }, 12, 32)).toBe('tree')
  expect(regionOf({ column: 40, row: 11 }, 12, 32)).toBe('hbar')
  expect(regionOf({ column: 40, row: 10 }, 12, 32)).toBe('file')
  expect(regionOf(undefined, 12, 32)).toBe('file')
})
