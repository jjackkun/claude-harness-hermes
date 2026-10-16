/**
 * structure-output.mjs — 판정 결과를 사람이 읽을 글과 종료 코드로 바꾸기만 한다.
 *
 * 종료 코드 규약: 0 통과 · 1 차단 위반 · 3 경고만 · 2 내부 오류(엔진 고장 — 진입점이 낸다).
 * pre-commit 은 1 만 차단하고, 2 는 skipped 로 기록한다 (계획 §4, G7).
 */

export const EXIT = { PASS: 0, BLOCK: 1, ERROR: 2, WARN: 3 }

function block(v) {
  return `\n  [R-struct-${v.id}] ${v.msg.split('\n').join('\n  ')}\n`
}

export function printViolations(violations, write = (s) => process.stderr.write(s)) {
  const blocks = violations.filter((v) => v.level === 'block')
  const warns = violations.filter((v) => v.level !== 'block')
  if (blocks.length) {
    write('\n[BLOCKED] 구조 위반:\n')
    blocks.forEach((v) => write(block(v)))
  }
  if (warns.length) {
    write('\n[WARN] 구조 경고 (커밋은 진행):\n')
    warns.forEach((v) => write(block(v)))
  }
  if (blocks.length || warns.length) write('\n')
  if (blocks.length) return EXIT.BLOCK
  return warns.length ? EXIT.WARN : EXIT.PASS
}

// 보고 모드 — 규칙·언어별 건수. 설치 소우주 실측(G4)에 쓴다.
export function printSummary(violations, write = (s) => process.stdout.write(s)) {
  const counts = {}
  for (const v of violations) {
    const k = `R-struct-${v.id} ${v.level} ${v.lang || '-'}`
    counts[k] = (counts[k] || 0) + 1
  }
  write(`total ${violations.length}\n`)
  for (const k of Object.keys(counts).sort()) write(`${k} ${counts[k]}\n`)
}
