#!/usr/bin/env node
/**
 * check-component-structure.mjs — 호환 래퍼. 판정은 check-structure.mjs 가 한다.
 *
 * 왜 남기는가: 설치된 소우주의 옛 pre-commit 이 이 이름을 부르고, 종료 코드가 0 이 아니면
 * 무엇이든 "구조 위반 차단" 으로 읽는다. 그래서 여기서는 옛 범위(Vue 규칙 R-struct-1~4)만 켜고
 *   1(차단) → 1,  0·3(경고만) → 0,  그 밖(엔진 고장) → 0 + skipped 안내
 * 로 바꿔 돌려준다. 고장이 커밋을 막으면 안 된다(계획 G7).
 *
 * Usage: node check-component-structure.mjs file1 file2 ...
 * 근거: docs/exec-plans/active/2026-10-16-language-neutral-structure-gate.md §4
 */

import { spawnSync } from 'child_process'
import { existsSync } from 'fs'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'

const engine = join(dirname(fileURLToPath(import.meta.url)), 'check-structure.mjs')
if (!existsSync(engine)) {
  process.stderr.write('[R-struct] skipped — check-structure.mjs 없음 (재설치 필요)\n')
  process.exit(0)
}

const r = spawnSync(process.execPath,
  [engine, '--langs', 'vue', '--no-common', '--blocks-only', ...process.argv.slice(2)],
  { stdio: ['ignore', 'inherit', 'inherit'] })

if (r.status === 1) process.exit(1)
if (r.status === 0 || r.status === 3) process.exit(0)
process.stderr.write(`[R-struct] skipped — 검사기 내부 오류 (종료 ${r.status})\n`)
process.exit(0)
