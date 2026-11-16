import type { Events } from 'claude-code'

// 엔진이 session.append 에 넘기는 입력(대화 줄 하나)
export type AppendedRow = Parameters<Events['session.append']>[1]

type Block = { type?: string; id?: string; name?: string; tool_use_id?: string }

const blocksOf = (e: AppendedRow): Block[] =>
  Array.isArray(e.message.content) ? (e.message.content as Block[]) : []

// 모델 응답 줄에서 Agent 도구를 부른 id 들 — 결과가 오면 명부를 다시 읽기 위해 기억한다.
// tool.call 대신 대화 줄을 보는 까닭: tool.call 훅이 있으면 Code Mode 가 꺼진다(2026-11-16 실측).
export const agentUseIds = (e: AppendedRow): string[] =>
  e.door === 'response'
    ? blocksOf(e).filter(b => b.type === 'tool_use' && b.name === 'Agent' && b.id).map(b => b.id as string)
    : []

// 도구 결과 줄이 기억해 둔 Agent 호출 중 하나의 결과인지
export const finishesAgent = (e: AppendedRow, pending: ReadonlySet<string>): string[] =>
  e.door === 'tool-result'
    ? blocksOf(e)
        .filter(b => b.type === 'tool_result' && b.tool_use_id && pending.has(b.tool_use_id))
        .map(b => b.tool_use_id as string)
    : []
