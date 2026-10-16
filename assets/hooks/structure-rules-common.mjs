/**
 * structure-rules-common.mjs — 언어 무관 규칙(R-struct-7)만 판정한다. 전부 경고.
 *
 * 기준 출처: assets/skills/structured-file-layout/SKILL.md
 *   - "같은 폴더 내 파일이 5개를 넘으면 하위 폴더를 검토한다"
 *   - "흔한 실수": utils/helpers 같은 포괄 이름, 파일 타입 기준 폴더(services/ schemas/)
 *   - 깊이 임계 8 은 설치 소우주 11곳 실측(p90 최대 7)으로 정했다 — 계획 §6·§7
 */

import { basename, dirname, extname } from 'path'

function warn(rules, path, target, msg) {
  return { id: rules.id, level: rules.level, path, target, msg: `${path} — ${msg}` }
}

function tooManyFiles(ctx, rules, file) {
  const dir = dirname(file)
  const n = ctx.listDir(dir).filter((e) =>
    e.isFile && ctx.enabledExts.has(extname(e.name)) && !ctx.isExempt(join(dir, e.name))).length
  if (n <= rules.maxFilesPerFolder) return []
  return [warn(rules, dir, 'files', `소스 파일 ${n}개 (기준 ${rules.maxFilesPerFolder}개 초과)\n  → 책임별 하위 폴더로 나눌지 검토`)]
}

function catchAllNames(rules, file) {
  const segs = file.split('/')
  const stem = basename(file, extname(file))
  const out = []
  segs.slice(0, -1).forEach((s, i) => {
    if (rules.catchAllNames.includes(s)) {
      out.push(warn(rules, segs.slice(0, i + 1).join('/'), `name:${s}`, `포괄 이름 폴더 '${s}'\n  → 담는 책임이 드러나는 이름으로 (예: date/, formatting/)`))
    }
  })
  if (rules.catchAllNames.includes(stem)) {
    out.push(warn(rules, file, `name:${stem}`, `포괄 이름 파일 '${stem}'\n  → 책임별로 나눈 이름으로 (예: date_utils → date_format)`))
  }
  return out
}

function typeFolders(ctx, rules, file) {
  for (let a = dirname(dirname(file)); ; a = dirname(a)) {
    const subs = ctx.listDir(a).filter((e) => e.isDir && !e.name.startsWith('.') && e.name !== '__pycache__')
    const names = subs.map((e) => e.name)
    if (names.length >= 2 && names.every((n) => rules.typeFolders.includes(n))) {
      return [warn(rules, a, 'type-folders', `파일 타입 기준 폴더만 있음 (${names.join(' ')})\n  → 도메인 기준 폴더로 (features/<기능>/)`)]
    }
    if (a === '.' || a === '/' || a === '') return []
  }
}

function tooDeep(rules, file) {
  const depth = file.split('/').length - 1
  if (depth <= rules.maxDepth) return []
  return [warn(rules, file, 'depth', `폴더 깊이 ${depth} (기준 ${rules.maxDepth} 초과)\n  → 상위 폴더를 합치거나 기능을 떼어 낼지 검토`)]
}

function join(dir, name) {
  return dir === '.' ? name : `${dir}/${name}`
}

export function checkCommon(ctx, file) {
  const rules = ctx.cfg.commonRules
  return [
    ...tooManyFiles(ctx, rules, file),
    ...catchAllNames(rules, file),
    ...typeFolders(ctx, rules, file),
    ...tooDeep(rules, file),
  ]
}
