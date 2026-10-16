/**
 * structure-resolve.mjs — import 문자열을 저장소 기준 `/` 경로로 풀고, 같은 기능인지 가른다.
 *
 * 컴파일러 없이 텍스트만 본다(계획 §6). path 계열에서 상대·별칭으로 풀리지 않는 대상(외부 패키지)은
 * null 을 돌려준다 — 'some-lib/features/x' 같은 원문이 비공개 경로 정규식에 걸리지 않게 한다.
 */

import { posix } from 'path'

const SCHEME_RE = /^[a-z][\w+.-]*:/i

function applyAliases(target, aliases) {
  for (const [re, rep] of Object.entries(aliases || {})) {
    const r = new RegExp(re)
    if (r.test(target)) return target.replace(r, rep)
  }
  return null
}

function resolvePath(file, target, rc) {
  const aliased = applyAliases(target, rc.aliases)
  if (aliased !== null) return posix.normalize(aliased)
  const relative =
    target.startsWith('./') || target.startsWith('../') ||
    (rc.bareIsRelative && !SCHEME_RE.test(target) && !target.startsWith('/'))
  if (!relative) return null // 외부 패키지 — 저장소 안 경로가 아니다
  return posix.normalize(posix.join(posix.dirname(file), target))
}

function resolveModule(file, target, rc) {
  if (rc.relativeDots && target.startsWith('.')) {
    const dots = target.match(/^\.+/)[0].length
    let base = posix.dirname(file)
    for (let i = 1; i < dots; i++) base = posix.dirname(base)
    const rest = target.slice(dots).split('.').filter(Boolean).join('/')
    return posix.normalize(rest ? posix.join(base, rest) : base)
  }
  const slashed = target.split(rc.sep).filter(Boolean).join('/')
  return applyAliases(slashed, rc.aliases) ?? slashed
}

export function resolveTarget(file, target, rc) {
  if (!rc || rc.kind === 'raw') return target
  if (rc.kind === 'path') return resolvePath(file, target, rc)
  if (rc.kind === 'module') return resolveModule(file, target, rc)
  throw new Error(`structure-langs.json: 모르는 resolve.kind '${rc.kind}'`)
}

// owner 가 가져가는 파일 경로에 들어 있으면 같은 기능 안의 import 다.
// module 계열은 네임스페이스와 폴더가 정확히 맞지 않아(PSR-4 의 App\ → src/ 등) 마지막 마디로도 본다.
export function sameOwner(file, owner, kind) {
  if (!owner) return true
  const f = '/' + file
  if (f.includes('/' + owner + '/')) return true
  const last = owner.split('/').pop()
  const stem = posix.basename(file).replace(/\.[^.]+$/, '')
  if (stem === last) return true // 기능의 진입 파일(lib/cart.rb, cart/cart.dart)
  return kind === 'module' && f.includes('/' + last + '/')
}
