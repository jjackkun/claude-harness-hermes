import { expect, test } from 'claude-code/testing'

import { applied, sane, toggledEditing } from '../hooks/reducers'
import type { Model } from '../types'

// 편집 기능이 생기기 전 판이 세션에 남긴 모양: open 에 saved·isEditing·revision 이 없다.
const STALE = {
  listed: { '': [{ name: 'a.md', kind: 'file' }] },
  expanded: [],
  open: { path: 'a.md', source: 'ab\ncd\n', top: 0 },
  notice: null,
} as unknown as Model

test('옛 모양의 세션 상태를 지금 모양으로 채운다 — 빈 값(undefined)이 남지 않는다', () => {
  const { open } = sane(STALE)

  expect(open).toEqual({ path: 'a.md', source: 'ab\ncd\n', top: 0, left: 0, wheel: 0, saved: 'ab\ncd\n', isEditing: false, revision: 0 })
  expect(sane(STALE).treeTop).toBe(0)
})

test('옛 모양의 상태에서 편집을 켜도 판 번호가 숫자다', () => {
  const { open } = applied(toggledEditing(90000))(STALE)

  expect(open?.isEditing).toBe(true)
  expect(open?.revision).toBe(0)
  expect(open?.source === open?.saved).toBe(true)
})

test('지금 모양의 상태는 그대로 둔다', () => {
  const now: Model = {
    listed: {},
    expanded: [],
    treeTop: 2,
    treeColumns: 40,
    open: { path: 'a.md', source: 'x', saved: 'y', top: 3, left: 4, wheel: 5, isEditing: true, revision: 7 },
    notice: null,
    tab: 'git',
    project: 'p',
    git: null,
  }

  expect(sane(now)).toEqual(now)
})
