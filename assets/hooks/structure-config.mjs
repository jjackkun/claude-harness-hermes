/**
 * structure-config.mjs — 설정표를 읽고, 이번 실행에서 켤 언어와 예외 경로를 정한다.
 *
 * 언어 켜기: Tier A 는 확장자로 자동, Tier B 는 `.harnessrc` 의 STRUCT_LANGS_EXTRA 로만.
 * 근거: docs/exec-plans/active/2026-10-16-language-neutral-structure-gate.md §6
 */

import { existsSync, readFileSync } from 'fs'
import { extname, join } from 'path'

// 공장 설치 영수증 — 여기 적힌 파일은 공장 저장소가 원본을 검사한다.
const MANIFEST = '.claude/.factory-manifest.json'

export function loadConfig(hookDir) {
  const cfg = JSON.parse(readFileSync(join(hookDir, 'structure-langs.json'), 'utf8'))
  if (cfg.version !== 1 || typeof cfg.langs !== 'object') {
    throw new Error('structure-langs.json: version 1 형식이 아니다')
  }
  return cfg
}

// spec: "auto" | "" | "vue js ..." ; extra: "go rust ..."
// 모르는 이름(.harnessrc 오타)은 그 이름만 빼고 onUnknown 으로 알린다 — 오타 하나로 검사 전체가 꺼지지 않게.
export function selectLangs(cfg, spec, extra, onUnknown = () => {}) {
  const words = (s) => (s || '').split(/[\s,]+/).filter(Boolean)
  const names = spec === 'auto'
    ? Object.keys(cfg.langs).filter((n) => cfg.langs[n].tier === 'A')
    : words(spec)
  for (const n of words(extra)) if (!names.includes(n)) names.push(n)
  const unknown = names.filter((n) => !cfg.langs[n])
  if (unknown.length) onUnknown(unknown)
  return names.filter((n) => cfg.langs[n])
}

export function langsForFile(cfg, langNames, file) {
  const ext = extname(file)
  return langNames.filter((n) => cfg.langs[n].exts.includes(ext))
}

function manifestPaths(root) {
  const p = join(root, MANIFEST)
  if (!existsSync(p)) return new Set()
  try {
    const items = JSON.parse(readFileSync(p, 'utf8')).items || []
    return new Set(items.map((i) => i.name).filter(Boolean))
  } catch {
    return new Set() // 영수증이 깨졌다고 검사를 멈추지 않는다 — 예외가 줄어들 뿐이다
  }
}

// extraExempt: `.harnessrc` STRUCT_EXEMPT — 공백으로 나눈 경로 접두어
export function makeExempt(cfg, root, extraExempt) {
  const common = cfg.defaultExempt.map((s) => new RegExp(s))
  const perLang = Object.fromEntries(
    Object.entries(cfg.langs).map(([n, l]) => [n, (l.exempt || []).map((s) => new RegExp(s))]),
  )
  const prefixes = (extraExempt || '').split(/\s+/).filter(Boolean)
  const managed = manifestPaths(root)
  return (file, lang) =>
    managed.has(file) ||
    prefixes.some((p) => file.startsWith(p)) ||
    common.some((re) => re.test(file)) ||
    (lang ? perLang[lang].some((re) => re.test(file)) : false)
}

export function featureRootsOf(cfg, lang) {
  return cfg.langs[lang].featureRoots || cfg.featureRoots
}
