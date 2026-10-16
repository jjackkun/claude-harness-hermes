/**
 * structure-rule-barrel.mjs — 기능·컴포넌트 폴더에 설정표의 배럴 파일이 있는지만 판정한다.
 *
 * strategy 별 "폴더" 의 뜻:
 *   sfc-folder    Vue 기존 규칙 — Foo.vue 는 Foo/ 안에(R-struct-1), Foo/ 에는 index.js|ts(R-struct-2)
 *   feature-root  featureRoots(features/ modules/ domains/) 바로 아래 폴더
 *   package-child 부모 폴더가 배럴을 가진 폴더 (파이썬 패키지 하위)
 *   component-dir componentPath 아래, 이름이 components 가 아닌 폴더 (Svelte)
 */

import { basename, dirname, extname, posix } from 'path'
import { featureRootsOf } from './structure-config.mjs'

const VUE_RULE_HINT = '근거: assets/rules/web/coding-style.md §File-Organization'

function hasAny(ctx, dir, names) {
  return names.some((n) => ctx.exists(posix.normalize(posix.join(dir, n.replaceAll('{dir}', basename(dir))))))
}

function sfcFolder(ctx, file, spec) {
  if (extname(file) !== '.vue' || !new RegExp(spec.componentPath).test(file)) return []
  const stem = basename(file, '.vue')
  const dir = dirname(file)
  if (basename(dir) !== stem) {
    return [{ id: 1, level: 'block', path: file, target: stem, msg:
      `${file}\n  → ${dir}/${stem}/${stem}.vue 로 이동 후 ${dir}/${stem}/index.js 배럴 추가\n` +
      `  → import 경로를 './${stem}.vue' 대신 './${stem}' (폴더명) 으로 변경\n  ${VUE_RULE_HINT}` }]
  }
  if (hasAny(ctx, dir, ['index.js', 'index.ts'])) return []
  return [{ id: 2, level: 'block', path: file, target: dir, msg:
    `${file} — ${dir}/index.js 배럴 없음\n` +
    `  → ${dir}/index.js 에 \`export { default } from './${stem}.vue'\` 추가\n  ${VUE_RULE_HINT}` }]
}

function featureFolder(ctx, file, lang) {
  const roots = featureRootsOf(ctx.cfg, lang)
  const segs = file.split('/')
  for (let i = 0; i + 2 < segs.length; i++) {
    if (roots.includes(segs[i])) return segs.slice(0, i + 2).join('/')
  }
  return null
}

function folderFor(ctx, file, lang, spec) {
  const dir = dirname(file)
  if (spec.strategy === 'feature-root') return featureFolder(ctx, file, lang)
  if (spec.strategy === 'package-child') {
    if (dir === '.') return null
    return hasAny(ctx, dirname(dir), spec.names) ? dir : null
  }
  if (spec.strategy === 'component-dir') {
    const under = new RegExp(spec.componentPath).test(dir + '/')
    return under && basename(dir) !== 'components' ? dir : null
  }
  throw new Error(`structure-langs.json: 모르는 barrel.strategy '${spec.strategy}'`)
}

export function checkBarrel(ctx, file, lang) {
  const out = []
  for (const spec of ctx.cfg.langs[lang].barrel || []) {
    if (spec.strategy === 'none') continue
    if (spec.strategy === 'sfc-folder') { out.push(...sfcFolder(ctx, file, spec)); continue }
    const folder = folderFor(ctx, file, lang, spec)
    if (!folder || hasAny(ctx, folder, spec.names)) continue
    out.push({ id: spec.id, level: 'block', path: folder, target: folder, msg:
      `${folder}/ — 배럴 없음 (${spec.names.join(' | ')} 중 하나)\n  → ${spec.hint}` })
  }
  return out
}
