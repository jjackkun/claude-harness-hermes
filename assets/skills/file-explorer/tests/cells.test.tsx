import { expect, test } from 'claude-code/testing'

import { cellsOf, colAt, fit, followLeft } from '../hooks/cells'

test('한글은 두 칸, 영문·숫자·기호는 한 칸으로 센다', () => {
  expect(cellsOf('ab1-')).toBe(4)
  expect(cellsOf('가나')).toBe(4)
  expect(cellsOf('a가b')).toBe(4)
})

test('칸 수 안에 온전히 들어가는 글자 수만 센다 — 반쪽만 걸치는 글자는 뺀다', () => {
  expect(fit('가나다', 4)).toBe(2)
  expect(fit('가나다', 5)).toBe(2)
  expect(fit('가나다', 6)).toBe(3)
  expect(fit('abc', 10)).toBe(3)
})

test('화면 칸을 글자 자리로 옮긴다 — 두 칸짜리 글자의 어느 칸을 눌러도 그 글자 앞', () => {
  expect(colAt('가나다', 0)).toBe(0)
  expect(colAt('가나다', 1)).toBe(0)
  expect(colAt('가나다', 2)).toBe(1)
  expect(colAt('가나다', 3)).toBe(1)
  expect(colAt('가나다', 99)).toBe(3)
})

test('커서가 오른쪽 끝을 넘으면 넘친 만큼만 왼쪽을 건너뛰고, 왼쪽으로 나가면 커서 자리로 돌아온다', () => {
  expect(followLeft('가나다라마', 0, 2, 4)).toBe(0)
  expect(followLeft('가나다라마', 0, 5, 4)).toBe(3)
  expect(followLeft('가나다라마', 3, 1, 4)).toBe(1)
})
