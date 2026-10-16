#!/usr/bin/env node
/**
 * check-structure.mjs — 폴더·배럴 구조 검사(R-struct)의 진입점.
 *
 * Usage: node check-structure.mjs [옵션] file1 file2 ...
 *   --langs <auto|"" |"vue js ..">  켤 언어 (기본 auto = 설정표 Tier A)
 *   --extra "<go rust ..>"          더 켤 언어 (.harnessrc STRUCT_LANGS_EXTRA)
 *   --exempt "<경로 접두어 ..>"     예외 경로 (.harnessrc STRUCT_EXEMPT)
 *   --all                           파일 대신 `git ls-files` 전부
 *   --report [--list]               건수만 표준출력, 종료 0 (설치 소우주 실측용)
 *   --update-baseline               전부 검사해 .structbaseline 을 다시 쓴다 (사람이 실행)
 *   --no-baseline · --no-common · --blocks-only
 * 종료 코드: structure-output.mjs EXIT (0 통과 · 1 차단 · 3 경고만 · 2 내부 오류)
 *
 * 모듈은 동적 import 한다 — 정적 import 는 파일이 하나 빠지면 try 밖에서 죽어 종료 코드 1(차단)이
 * 되고, 그러면 고장이 모든 커밋을 막는다(계획 G7). 언어 지식은 전부 structure-langs.json 에 있다.
 */

import { execFileSync } from 'child_process'
import { existsSync, lstatSync, readFileSync, readdirSync } from 'fs'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'

const MODULES = ['config', 'rule-barrel', 'rule-deep-import', 'rule-reexport', 'rules-common', 'baseline', 'output']

function parseArgs(argv) {
  const o = { langs: 'auto', extra: '', exempt: '', files: [], flags: new Set() }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (['--langs', '--extra', '--exempt'].includes(a)) o[a.slice(2)] = argv[++i] ?? ''
    else if (a.startsWith('--')) o.flags.add(a.slice(2))
    else o.files.push(a.replaceAll('\\', '/').replace(/^\.\//, ''))
  }
  return o
}

function makeCtx(cfg, root, exempt, enabledExts) {
  const src = new Map(), dirs = new Map()
  return {
    cfg, root, enabledExts, isExempt: (f) => exempt(f),
    exists: (p) => existsSync(join(root, p)),
    read(f) {
      if (!src.has(f)) { try { src.set(f, readFileSync(join(root, f), 'utf8')) } catch { src.set(f, null) } }
      return src.get(f)
    },
    listDir(d) {
      if (!dirs.has(d)) {
        try {
          dirs.set(d, readdirSync(join(root, d), { withFileTypes: true })
            .map((e) => ({ name: e.name, isFile: e.isFile(), isDir: e.isDirectory() })))
        } catch { dirs.set(d, []) }
      }
      return dirs.get(d)
    },
  }
}

function isSymlink(root, f) {
  try { return lstatSync(join(root, f)).isSymbolicLink() } catch { return false }
}

function collect(m, ctx, langNames, files, o, exempt) {
  const seen = new Map()
  const add = (v, lang) => { const k = m.baseline.keyOf(v); if (!seen.has(k)) seen.set(k, { ...v, lang }) }
  for (const file of files) {
    if (isSymlink(ctx.root, file) || exempt(file)) continue
    const langs = m.config.langsForFile(ctx.cfg, langNames, file).filter((l) => !exempt(file, l))
    for (const lang of langs) {
      for (const check of [m['rule-barrel'].checkBarrel, m['rule-deep-import'].checkDeepImport, m['rule-reexport'].checkReexport]) {
        check(ctx, file, lang).forEach((v) => add(v, lang))
      }
    }
    if (langs.length && !o.flags.has('no-common')) m['rules-common'].checkCommon(ctx, file).forEach((v) => add(v, ''))
  }
  return [...seen.values()]
}

async function main() {
  const here = dirname(fileURLToPath(import.meta.url))
  const loaded = await Promise.all(MODULES.map((n) => import(join(here, `structure-${n}.mjs`))))
  const m = Object.fromEntries(MODULES.map((n, i) => [n, loaded[i]]))
  const o = parseArgs(process.argv.slice(2))
  const root = process.cwd()
  const cfg = m.config.loadConfig(here)
  const langNames = m.config.selectLangs(cfg, o.langs, o.extra)
  const exempt = m.config.makeExempt(cfg, root, o.exempt)
  const enabledExts = new Set(langNames.flatMap((n) => cfg.langs[n].exts))
  const full = o.flags.has('all') || o.flags.has('update-baseline') || o.flags.has('report')
  const files = full
    ? execFileSync('git', ['ls-files'], { cwd: root, encoding: 'utf8' }).split('\n').filter(Boolean)
    : o.files
  let found = collect(m, makeCtx(cfg, root, exempt, enabledExts), langNames, files, o, exempt)

  if (o.flags.has('update-baseline')) {
    process.stdout.write(`.structbaseline ${m.baseline.writeBaseline(root, found)}건\n`)
    return m.output.EXIT.PASS
  }
  if (!o.flags.has('no-baseline')) {
    const keys = m.baseline.remapKeys(m.baseline.readBaseline(root), m.baseline.stagedRenames(root))
    found = m.baseline.onlyNew(found, keys)
  }
  if (o.flags.has('report')) {
    m.output.printSummary(found)
    if (o.flags.has('list')) found.forEach((v) => process.stdout.write(`${m.baseline.keyOf(v)}\n`))
    return m.output.EXIT.PASS
  }
  if (o.flags.has('blocks-only')) found = found.filter((v) => v.level === 'block')
  return m.output.printViolations(found)
}

main().then((code) => process.exit(code)).catch((e) => {
  process.stderr.write(`[R-struct] 검사기 내부 오류 — ${e && e.message}\n`)
  process.exit(2)
})
