import type { Events } from 'claude-code'

import type { ToolCall } from '../types'

// 한 세션에서 보관할 호출 수 상한. 패널은 화면 높이만큼만 그리므로 그보다 넉넉하면 된다.
export const MAX_KEPT_CALLS = 200

// 엔진이 session.append 에 넘기는 입력(대화 줄 하나)
export type AppendedRow = Parameters<Events['session.append']>[1]

type Block = { type?: string; id?: string; name?: string; tool_use_id?: string }

const blocksOf = (e: AppendedRow): Block[] =>
  Array.isArray(e.message.content) ? (e.message.content as Block[]) : []

// 대화에 쌓이는 줄 하나를 목록에 반영한다 — 모델 응답의 tool_use 는 "실행", 도구 결과는 "완료".
// tool.call 대신 이 줄을 보는 까닭: tool.call 훅이 있으면 Code Mode 가 꺼진다(2026-11-16 실측).
export const applyRow = (list: readonly ToolCall[], e: AppendedRow): ToolCall[] => {
  const blocks = blocksOf(e)
  if (e.door === 'response') {
    const started = blocks
      .filter(b => b.type === 'tool_use' && b.id && b.name)
      .map(b => ({ id: b.id as string, tool: b.name as string, isDone: false }))

    return started.length ? [...list, ...started].slice(-MAX_KEPT_CALLS) : [...list]
  }
  if (e.door === 'tool-result') {
    const done = new Set(blocks.filter(b => b.type === 'tool_result').map(b => b.tool_use_id))

    return list.map(one => (done.has(one.id) ? { ...one, isDone: true } : one))
  }

  return [...list]
}
