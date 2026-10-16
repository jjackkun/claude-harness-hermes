/**
 * structure-rule-reexport.mjs — 배럴(또는 언어에 따라 모든 파일)의 전량 재노출만 판정한다.
 *
 * 배럴은 은닉 장치가 아니라 재노출 장치다. 전부 내보내면 호출자가 알아야 할 심볼 수가
 * 그대로여서 인터페이스가 하나도 좁아지지 않는다 (R-struct-4, docs/design-docs/core-beliefs.md#r-iface).
 * 정규식은 줄 머리에 고정한다 — 문자열·주석 안의 같은 글자를 위반으로 잡으면 오탐이 나고,
 * 오탐이 나는 차단은 우회를 학습시킨다.
 */

import { basename } from 'path'

export function checkReexport(ctx, file, lang) {
  const spec = ctx.cfg.langs[lang].reexport
  if (!spec) return []
  if (spec.barrelOnly && !(spec.barrelNames || []).includes(basename(file))) return []
  const src = ctx.read(file)
  if (src === null) return []

  const allow = spec.allow ? new RegExp(spec.allow) : null
  const out = []
  for (const pattern of spec.patterns) {
    const re = new RegExp(pattern, 'gm')
    let m
    while ((m = re.exec(src)) !== null) {
      const line = m[0].trim()
      if (allow && allow.test(m[0])) continue
      out.push({ id: spec.id, level: spec.level, path: file, target: line, msg:
        `${file} — ${spec.label || '전량 재노출'}: '${line}'\n  → ${spec.hint}` })
    }
  }
  return out
}
