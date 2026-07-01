#!/usr/bin/env node
/**
 * check-component-structure.mjs
 * Staged 파일에 대해 컴포넌트 폴더·배럴 규칙을 정적 검사한다.
 *
 * Usage: node check-component-structure.mjs file1 file2 ...
 * Exit 0 = clean, Exit 1 = violations
 *
 * 규칙:
 *   R-struct-1: *.vue 는 동일 이름 폴더 안에 있어야 한다 (0뎁스 직접 배치 금지)
 *   R-struct-2: 컴포넌트 폴더에 index.js 또는 index.ts 배럴이 있어야 한다
 *   R-struct-3: 컴포넌트 소비자는 .vue 직접 경로 import 금지 (폴더명 import 강제)
 *
 * 예외(allowlist):
 *   - components/ui/ — shadcn 등 자동생성물
 *   - *.stories.*, *.story.*, *.test.*, *.spec.* — 스토리·테스트
 */

import { existsSync, readFileSync } from 'fs'
import { basename, dirname, extname, join } from 'path'

// 검사 대상 컴포넌트 경로 패턴
const COMPONENT_PATH_RE =
  /(?:^|\/)src\/(?:components|features\/[^/]+\/components|lib\/[^/]+\/components)\//

// allowlist — 이 패턴에 매칭되는 파일은 검사 제외
const ALLOWLIST_RE =
  /(?:\/ui\/|\.stories\.[jt]sx?$|\.story\.[jt]sx?$|\.test\.[jt]sx?$|\.spec\.[jt]sx?$)/

const CODE_EXTS = new Set(['.vue', '.js', '.jsx', '.ts', '.tsx'])
const BARREL_RE = /^index\.[jt]sx?$/

const files = process.argv.slice(2)
const violations = []

for (const file of files) {
  if (ALLOWLIST_RE.test(file)) continue

  const ext = extname(file)
  const name = basename(file)

  // ── R-struct-1 & R-struct-2: .vue 파일, 컴포넌트 경로 한정 ──────────────
  if (ext === '.vue' && COMPONENT_PATH_RE.test(file)) {
    const stem = basename(file, '.vue')
    const dir = dirname(file)
    const parentName = basename(dir)

    if (parentName !== stem) {
      // R-struct-1: 폴더명 ≠ 파일 stem
      violations.push(
        `[R-struct-1] ${file}\n` +
        `  → ${dir}/${stem}/${stem}.vue 로 이동 후 ${dir}/${stem}/index.js 배럴 추가\n` +
        `  → import 경로를 './${stem}.vue' 대신 './${stem}' (폴더명) 으로 변경\n` +
        `  근거: assets/rules/web/coding-style.md §File-Organization`
      )
    } else {
      // R-struct-2: 배럴 존재 확인
      const hasBarrel =
        existsSync(join(dir, 'index.js')) ||
        existsSync(join(dir, 'index.ts'))
      if (!hasBarrel) {
        violations.push(
          `[R-struct-2] ${file} — ${dir}/index.js 배럴 없음\n` +
          `  → ${dir}/index.js 에 \`export { default } from './${stem}.vue'\` 추가\n` +
          `  근거: assets/rules/web/coding-style.md §File-Organization`
        )
      }
    }
  }

  // ── R-struct-3: .vue 직접 import 금지 (배럴 파일 제외) ──────────────────
  if (CODE_EXTS.has(ext) && !BARREL_RE.test(name)) {
    let src
    try { src = readFileSync(file, 'utf8') } catch { continue }

    const re = /(?:from|import\s*\()\s*['"]([^'"]+\.vue)['"]/g
    let m
    while ((m = re.exec(src)) !== null) {
      const importPath = m[1]
      const folderImport = importPath.replace(/\/[^/]+\.vue$/, '')
      violations.push(
        `[R-struct-3] ${file} — .vue 직접 import 금지: '${importPath}'\n` +
        `  → '${folderImport}' (폴더명) 으로 변경\n` +
        `  근거: assets/rules/web/coding-style.md §File-Organization`
      )
    }
  }
}

if (violations.length > 0) {
  process.stderr.write('\n[BLOCKED] 컴포넌트 구조 위반:\n')
  for (const v of violations) {
    process.stderr.write('\n  ' + v.split('\n').join('\n  ') + '\n')
  }
  process.stderr.write('\n')
  process.exit(1)
}

process.exit(0)
