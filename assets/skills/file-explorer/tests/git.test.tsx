import { expect, test } from 'claude-code/testing'

import { colorOf, diffArgv, labelOf, parseStatus, treeColorOf } from '../hooks/git'
import { fromDiffRun, fromStatusRun } from '../hooks/gitstate'
import { sane } from '../hooks/reducers'
import type { Model } from '../types'

const ran = (exitCode: number, stdout: string, stderr = '') => ({
  exitCode,
  stdout,
  stderr,
  isStdoutTruncated: false,
  isStderrTruncated: false,
})
const STATUS = '## main...origin/main [ahead 1]\n M docs/a.md\nA  src/new.ts\nR  old.md -> docs/moved.md\n?? 메모.txt\n'
const empty = (): Model =>
  sane({ listed: {}, expanded: [], treeTop: 0, open: null, notice: null, tab: 'git', project: 'p', git: null })

test('git status 출력에서 브랜치 줄과 파일 줄을 가른다 — 이름 바꾼 파일은 새 이름, 새 파일은 ??', () => {
  expect(parseStatus(STATUS)).toEqual({
    branch: 'main...origin/main [ahead 1]',
    files: [
      { code: ' M', path: 'docs/a.md' },
      { code: 'A ', path: 'src/new.ts' },
      { code: 'R ', path: 'docs/moved.md' },
      { code: '??', path: '메모.txt' },
    ],
  })
  expect(parseStatus('## main\n')).toEqual({ branch: 'main', files: [] })
})

test('변경 내용 명령: 추적 중인 파일은 마지막 커밋과, 새 파일은 빈 파일과 견준다', () => {
  expect(diffArgv({ code: ' M', path: 'a.md' }).slice(3)).toEqual(['diff', 'HEAD', '--', 'a.md'])
  expect(diffArgv({ code: '??', path: 'n.md' }).slice(3)).toEqual(['diff', '--no-index', '--', '/dev/null', 'n.md'])
})

test('목록 한 줄이 길면 파일 이름이 남도록 경로의 앞을 줄인다', () => {
  expect(labelOf({ code: ' M', path: 'a.md' }, 31)).toBe(' M a.md')
  const long = labelOf({ code: ' M', path: 'docs/audits/2026-07-08-hermes-skill-utilization-gap.md' }, 31)
  // 31칸 = 상태 2 + 공백 1 + 경로 28(… 1 + 끝 27자)
  expect(long).toBe(' M …es-skill-utilization-gap.md')
  expect(long.length).toBe(31)
})

test('상태를 읽으면 목록이 차고, 실패하면 이유를 알림 줄에 적는다', () => {
  const loaded = { ...empty(), ...fromStatusRun(ran(0, STATUS))(empty()) }

  expect(loaded.git?.branch).toBe('main...origin/main [ahead 1]')
  expect(loaded.git?.files.length).toBe(4)
  expect(loaded.git?.path).toBe(null)
  expect(fromStatusRun(ran(128, '', 'fatal: not a git repository\n'))(empty())).toEqual({
    git: null,
    notice: 'git 상태를 읽지 못했습니다: fatal: not a git repository',
  })
})

test('변경 내용: 새 파일의 종료 코드 1 은 정상이고, 2 이상은 실패다', () => {
  const loaded = { ...empty(), ...fromStatusRun(ran(0, STATUS))(empty()) }
  const file = { code: '??', path: '메모.txt' }

  expect({ ...loaded, ...fromDiffRun(file, ran(1, '+새 줄\n'))(loaded) }.git?.diff).toBe('+새 줄\n')
  expect({ ...loaded, ...fromDiffRun(file, ran(1, '+새 줄\n'))(loaded) }.git?.path).toBe('메모.txt')
  expect(fromDiffRun(file, ran(2, '', 'error: bad\n'))(loaded)).toEqual({ notice: '변경 내용을 읽지 못했습니다: error: bad' })
})

test('줄 색은 git status 와 같은 기준: 스테이징이 끝났으면 초록, 스테이징 안 한 변경이나 새 파일이면 빨강', () => {
  expect(colorOf({ code: 'M ', path: 'a' })).toBe('success')
  expect(colorOf({ code: 'A ', path: 'a' })).toBe('success')
  expect(colorOf({ code: 'R ', path: 'a' })).toBe('success')
  expect(colorOf({ code: ' M', path: 'a' })).toBe('error')
  expect(colorOf({ code: ' D', path: 'a' })).toBe('error')
  expect(colorOf({ code: '??', path: 'a' })).toBe('error')
  // 일부만 스테이징한 파일은 아직 남은 변경이 있으므로 빨강
  expect(colorOf({ code: 'MM', path: 'a' })).toBe('error')
})

const CHANGED = [
  { code: ' M', path: 'docs/audits/a.md' },
  { code: '??', path: 'docs/videos/clip/note.md' },
  { code: '??', path: 'scratch.txt' },
  { code: 'A ', path: 'src/new.ts' },
  { code: ' D', path: 'old.md' },
]

test('트리의 파일 색: 고친 파일은 노랑, 새 파일은 초록, 지운 파일은 빨강, 그대로인 파일은 색 없음', () => {
  expect(treeColorOf('docs/audits/a.md', 'file', CHANGED)).toBe('warning')
  expect(treeColorOf('scratch.txt', 'file', CHANGED)).toBe('success')
  expect(treeColorOf('src/new.ts', 'file', CHANGED)).toBe('success')
  expect(treeColorOf('old.md', 'file', CHANGED)).toBe('error')
  expect(treeColorOf('README.md', 'file', CHANGED)).toBe(null)
})

test('트리의 폴더 색은 파일 색과 다르다: 안에 고친 파일이 있으면 주황, 새 파일만 있으면 청록, 바뀐 것이 없으면 색 없음', () => {
  // docs 안에는 고친 파일과 새 파일이 함께 있다 → 고친 쪽이 이긴다
  expect(treeColorOf('docs', 'dir', CHANGED)).toBe('claude')
  expect(treeColorOf('docs/audits', 'dir', CHANGED)).toBe('claude')
  expect(treeColorOf('docs/videos', 'dir', CHANGED)).toBe('cyan')
  expect(treeColorOf('src', 'dir', CHANGED)).toBe('cyan')
  // 폴더에 쓰는 색은 파일에 쓰는 색(노랑·초록·빨강)과 겹치지 않는다
  const fileColors = ['warning', 'success', 'error']
  expect(fileColors.includes(treeColorOf('docs', 'dir', CHANGED) ?? '')).toBe(false)
  expect(fileColors.includes(treeColorOf('src', 'dir', CHANGED) ?? '')).toBe(false)
  expect(treeColorOf('lib', 'dir', CHANGED)).toBe(null)
})

test('폴더 색은 이름이 앞부분만 같은 다른 폴더에 번지지 않는다', () => {
  // docs-old 는 docs 로 시작하지만 docs 안이 아니다
  expect(treeColorOf('doc', 'dir', CHANGED)).toBe(null)
  expect(treeColorOf('docs', 'dir', [{ code: ' M', path: 'docs-old/a.md' }])).toBe(null)
})
