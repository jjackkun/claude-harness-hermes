#!/usr/bin/env node
/**
 * structure-gate-run.mjs — tests/fixtures/structure/cases.json 의 언어×규칙 사례를 임시 폴더에 펼쳐
 * check-structure.mjs 의 판정을 단언한다. 진입: tests/structure-gate-test.sh
 *
 * 단언:
 *   (a) bad → 기대 종료 코드(block 1 · warn 3)와 그 규칙 번호만, good(bad 를 고친 판) → 0
 *   (b) 설정표의 (언어, 규칙) 쌍 == 사례가 덮는 쌍, 그리고 모든 언어가 사례를 하나 이상 가진다
 */

import { spawnSync } from 'child_process'
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'fs'
import { tmpdir } from 'os'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const ENGINE = join(ROOT, 'assets/hooks/check-structure.mjs')
const CFG = JSON.parse(readFileSync(join(ROOT, 'assets/hooks/structure-langs.json'), 'utf8'))
const { cases } = JSON.parse(readFileSync(join(ROOT, 'tests/fixtures/structure/cases.json'), 'utf8'))
const EXIT = { block: 1, warn: 3, pass: 0 }
const COMMON_WORD = { files: '소스 파일', name: '포괄 이름', type: '파일 타입', depth: '폴더 깊이' }

let pass = 0, fail = 0
const ok = (m) => { pass++; console.log(`  ✓ ${m}`) }
const nope = (m) => { fail++; console.log(`  ✗ ${m}`) }

function run(c, files) {
  const dir = mkdtempSync(join(tmpdir(), 'struct-'))
  try {
    for (const [p, body] of Object.entries(files)) {
      mkdirSync(join(dir, dirname(p)), { recursive: true })
      writeFileSync(join(dir, p), body)
    }
    const args = [ENGINE, '--langs', c.langs || c.lang, '--no-baseline', ...(c.common ? [] : ['--no-common']), ...Object.keys(files)]
    const r = spawnSync(process.execPath, args, { cwd: dir, encoding: 'utf8' })
    return { code: r.status, out: r.stderr + r.stdout }
  } finally { rmSync(dir, { recursive: true, force: true }) }
}

function checkCase(c) {
  const label = `${c.lang} R-struct-${c.rule}${c.name ? ` (${c.name})` : ''}`
  const [id, sub] = c.rule.split(':')
  if (c.bad) {
    const r = run(c, c.bad)
    const ids = [...new Set([...r.out.matchAll(/\[R-struct-(\d+)\]/g)].map((m) => m[1]))]
    const subOk = id !== '7' || r.out.includes(COMMON_WORD[sub])
    if (r.code === EXIT[c.expect] && ids.length === 1 && ids[0] === id && subOk) ok(`${label} bad → ${c.expect}`)
    else nope(`${label} bad → 기대 ${c.expect}(${EXIT[c.expect]}) / 실제 ${r.code} ids=[${ids}]\n${r.out}`)
  }
  const g = run(c, c.good)
  if (g.code === 0) ok(`${label} good → 통과`)
  else nope(`${label} good → 기대 0 / 실제 ${g.code}\n${g.out}`)
}

function configPairs() {
  const pairs = new Set()
  for (const [lang, l] of Object.entries(CFG.langs)) {
    for (const b of l.barrel || []) {
      if (b.strategy === 'sfc-folder') { pairs.add(`${lang}/1:sfc-folder`); pairs.add(`${lang}/2:sfc-folder`) }
      else if (b.strategy !== 'none') pairs.add(`${lang}/${b.id}:${b.strategy}`)
    }
    if (l.deepImport) pairs.add(`${lang}/${l.deepImport.id}`)
    if (l.reexport) pairs.add(`${lang}/${l.reexport.id}`)
  }
  return pairs
}

function checkCoverage() {
  const want = configPairs()
  const have = new Set(cases.filter((c) => !c.rule.startsWith('7')).map((c) => `${c.lang}/${c.rule}`))
  const missing = [...want].filter((p) => !have.has(p))
  const extra = [...have].filter((p) => !want.has(p))
  if (!missing.length && !extra.length) ok(`커버리지: 설정표 쌍 ${want.size} == 사례 쌍 ${have.size}`)
  else nope(`커버리지: 빠짐 [${missing}] / 설정표에 없음 [${extra}]`)
  const commons = new Set(cases.filter((c) => c.rule.startsWith('7:')).map((c) => c.rule.slice(2)))
  const lacking = Object.keys(COMMON_WORD).filter((k) => !commons.has(k))
  if (!lacking.length) ok('커버리지: 언어 무관 규칙 4종')
  else nope(`커버리지: 언어 무관 빠짐 [${lacking}]`)
  const noCase = Object.keys(CFG.langs).filter((n) => !cases.some((c) => c.lang === n))
  if (!noCase.length) ok(`커버리지: 언어 ${Object.keys(CFG.langs).length}개 모두 사례 있음`)
  else nope(`커버리지: 사례 없는 언어 [${noCase}]`)
}

// G5 — 규칙 문서의 언어별 강제 범위표가 설정표와 같은가. 표는 이 함수가 만든 모양 그대로 문서에 둔다.
const DOC = join(ROOT, 'assets/rules/web/coding-style.md')
const LEVEL = { block: '차단', warn: '경고' }
export function scopeTable() {
  const rows = Object.entries(CFG.langs).map(([lang, l]) => {
    const barrel = (l.barrel || []).map((b) => b.strategy === 'sfc-folder'
      ? '1·2 차단' : `${b.id} ${LEVEL[b.level || 'block']}(${b.strategy})`).join(' · ') || '—'
    const deep = l.deepImport ? `${l.deepImport.id} ${LEVEL[l.deepImport.level]}` : '—'
    const re = l.reexport ? `${l.reexport.id} ${LEVEL[l.reexport.level]}` : '—'
    return `| ${lang} | ${l.tier} | ${l.exts.join(' ')} | ${barrel} | ${deep} | ${re} |`
  })
  return ['| 언어 | Tier | 확장자 | 배럴 존재 | 깊은 import | 전량 재노출 |', '|---|---|---|---|---|---|', ...rows].join('\n')
}

function checkDocTable() {
  const doc = readFileSync(DOC, 'utf8')
  const m = doc.match(/<!-- struct-scope:begin -->\n([\s\S]*?)\n<!-- struct-scope:end -->/)
  if (m && m[1].trim() === scopeTable()) ok('문서 범위표 == 설정표 (web/coding-style.md)')
  else nope(`문서 범위표가 설정표와 다르다 — 아래로 교체:\n${scopeTable()}`)
}

if (process.argv.includes('--print-scope')) { console.log(scopeTable()); process.exit(0) }
cases.forEach(checkCase)
checkCoverage()
checkDocTable()
console.log(`\nPASS=${pass} FAIL=${fail}`)
process.exit(fail ? 1 : 0)
