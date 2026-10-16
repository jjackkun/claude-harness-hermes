/**
 * structure-rule-deep-import.mjs — 다른 기능의 배럴을 건너뛰고 내부 경로를 import 한 것만 판정한다.
 *
 * 대상이 설정표 deepImport.private 정규식에 맞으면 위반이다. 정규식의 (?<owner>…) 가
 * 가져가는 파일 경로에 들어 있으면 같은 기능 안의 import 라서 통과한다.
 * Vue 의 R-struct-3(.vue 직접 import 금지)도 owner 없는 private 정규식 하나로 같은 길을 탄다.
 */

import { basename } from 'path'
import { resolveTarget, sameOwner } from './structure-resolve.mjs'

export function checkDeepImport(ctx, file, lang) {
  const l = ctx.cfg.langs[lang]
  const spec = l.deepImport
  if (!spec || !l.imports) return []
  if (spec.skipInBarrel && (spec.barrelNames || []).includes(basename(file))) return []
  const src = ctx.read(file)
  if (src === null) return []

  const privates = spec.private.map((s) => new RegExp(s))
  const out = []
  for (const pattern of l.imports) {
    const re = new RegExp(pattern, 'gm')
    let m
    while ((m = re.exec(src)) !== null) {
      const target = m.groups?.target
      if (!target) continue
      const resolved = resolveTarget(file, target, l.resolve)
      const hit = privates.map((p) => resolved.match(p)).find(Boolean)
      if (!hit) continue
      // owner 그룹이 없는 정규식은 "누가 가져가든 위반"(Vue .vue 직접 import)이다
      const owner = hit.groups?.owner
      if (owner !== undefined && sameOwner(file, owner, l.resolve?.kind)) continue
      out.push({ id: spec.id, level: spec.level, path: file, target, msg:
        `${file} — 내부 경로 직접 import: '${target}'\n  → ${spec.hint}` })
    }
  }
  return out
}
