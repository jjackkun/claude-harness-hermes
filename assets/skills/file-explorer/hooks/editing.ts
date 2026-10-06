import type { ClientKeyEvent } from 'claude-code'

// 에디터가 들고 있는 것: 줄들과 커서 자리.
export type Buffer = { lines: string[]; row: number; col: number }

const clamp = (value: number, low: number, high: number): number => Math.max(low, Math.min(value, high))
const lineAt = (b: Buffer, row: number): string => b.lines[row] ?? ''

// 커서를 (row, col) 로 옮긴다. 범위를 벗어나면 가장 가까운 자리로.
export const place = (b: Buffer, row: number, col: number): Buffer => {
  const kept = clamp(row, 0, b.lines.length - 1)

  return { ...b, row: kept, col: clamp(col, 0, lineAt(b, kept).length) }
}

const insert = (b: Buffer, text: string): Buffer => {
  const line = lineAt(b, b.row)

  return { ...b, lines: b.lines.toSpliced(b.row, 1, line.slice(0, b.col) + text + line.slice(b.col)), col: b.col + text.length }
}

const KEYS: Record<string, (b: Buffer) => Buffer> = {
  up: b => place(b, b.row - 1, b.col),
  down: b => place(b, b.row + 1, b.col),
  home: b => ({ ...b, col: 0 }),
  end: b => ({ ...b, col: lineAt(b, b.row).length }),
  left: b => (b.col > 0 ? { ...b, col: b.col - 1 } : b.row > 0 ? place(b, b.row - 1, Infinity) : b),
  right: b => (b.col < lineAt(b, b.row).length ? { ...b, col: b.col + 1 } : place(b, b.row + 1, 0)),
  tab: b => insert(b, '  '),
  return: b => {
    const line = lineAt(b, b.row)

    return { lines: b.lines.toSpliced(b.row, 1, line.slice(0, b.col), line.slice(b.col)), row: b.row + 1, col: 0 }
  },
  backspace: b => {
    const line = lineAt(b, b.row)
    if (b.col > 0) {
      return { ...b, lines: b.lines.toSpliced(b.row, 1, line.slice(0, b.col - 1) + line.slice(b.col)), col: b.col - 1 }
    }
    if (b.row === 0) {
      return b
    }
    const above = lineAt(b, b.row - 1)

    return { lines: b.lines.toSpliced(b.row - 1, 2, above + line), row: b.row - 1, col: above.length }
  },
  delete: b => {
    const line = lineAt(b, b.row)
    if (b.col < line.length) {
      return { ...b, lines: b.lines.toSpliced(b.row, 1, line.slice(0, b.col) + line.slice(b.col + 1)) }
    }

    return b.row === b.lines.length - 1 ? b : { ...b, lines: b.lines.toSpliced(b.row, 2, line + lineAt(b, b.row + 1)) }
  },
}

// 키 하나를 반영한 새 버퍼. 받지 않는 키면 null.
export const press = (b: Buffer, key: ClientKeyEvent): Buffer | null => {
  if (key.ctrl || key.meta) {
    return null
  }
  const named = KEYS[key.key]
  if (named !== undefined) {
    return named(b)
  }

  return [...key.key].length === 1 ? insert(b, key.key) : null
}

// 커서가 화면 밖으로 나가면 맨 윗줄을 따라 옮긴다.
export const follow = (top: number, row: number, rows: number): number =>
  row < top ? row : row >= top + rows ? row - rows + 1 : top
