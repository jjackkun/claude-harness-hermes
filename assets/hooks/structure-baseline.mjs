/**
 * structure-baseline.mjs — `.structbaseline` 읽기·쓰기와 "새 위반만 남기기"만 한다.
 *
 * 위반 키 = `R-struct-N|경로|대상`. 같은 파일이라도 대상이 다르면 새 키다.
 * 라쳇: 커밋 때는 기준선을 고치지 않는다. 키를 늘리는 갱신은 `--update-baseline` 을 사람이
 * 돌릴 때만 일어난다 (.cxbaseline 과 같은 원칙).
 * 이름 바꾸기: 스테이지된 `git mv`(R 줄)를 읽어 옛 경로 키를 새 경로로 옮겨 본다.
 */

import { execFileSync } from 'child_process'
import { existsSync, readFileSync, writeFileSync } from 'fs'
import { dirname, join } from 'path'

export const BASELINE_FILE = '.structbaseline'

export function keyOf(v) {
  return `R-struct-${v.id}|${v.path}|${v.target}`
}

export function readBaseline(root) {
  const p = join(root, BASELINE_FILE)
  if (!existsSync(p)) return new Set()
  return new Set(readFileSync(p, 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#')))
}

export function stagedRenames(root) {
  try {
    const out = execFileSync('git', ['diff', '--cached', '-M', '--name-status'], { cwd: root, encoding: 'utf8' })
    return out.split('\n').filter((l) => /^R\d*\t/.test(l)).map((l) => l.split('\t').slice(1, 3))
  } catch {
    return [] // git 밖(시험용 임시 폴더)이면 이름 바꾸기가 없다
  }
}

function remap(part, renames) {
  for (const [from, to] of renames) {
    if (part === from) return to
    if (part === dirname(from) && dirname(from) !== dirname(to)) return dirname(to)
  }
  return part
}

export function remapKeys(keys, renames) {
  if (!renames.length) return keys
  return new Set([...keys].map((k) => {
    const [rule, path, ...rest] = k.split('|')
    return [rule, remap(path, renames), remap(rest.join('|'), renames)].join('|')
  }))
}

export function onlyNew(violations, keys) {
  return violations.filter((v) => !keys.has(keyOf(v)))
}

export function writeBaseline(root, violations) {
  const keys = [...new Set(violations.map(keyOf))].sort()
  const head = [
    '# .structbaseline — R-struct 기준선. 여기 있는 위반은 기존 코드라 커밋을 막지 않는다.',
    '# 갱신은 사람이: node .git/hooks/check-structure.mjs --update-baseline (줄이 늘면 커밋 메시지에 사유)',
  ]
  writeFileSync(join(root, BASELINE_FILE), [...head, ...keys, ''].join('\n'))
  return keys.length
}
