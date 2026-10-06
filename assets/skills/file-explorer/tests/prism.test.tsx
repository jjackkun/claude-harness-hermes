import { expect, test } from 'claude-code/testing'

import Prism from '../hooks/vendor/prism.js'

test('묶은 Prism 이 모드 환경에서 로드되고 파이썬 줄을 조각으로 나눈다', () => {
  const tokens = Prism.tokenize('def f(): return 1', Prism.languages['python'])
  const types = tokens.filter(token => typeof token !== 'string').map(token => (typeof token === 'string' ? '' : token.type))

  expect(Object.keys(Prism.languages).includes('markdown')).toBe(true)
  expect(types).toContain('keyword')
  expect(types).toContain('number')
})
