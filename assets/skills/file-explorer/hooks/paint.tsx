import type { Elements } from 'claude-code'

import { BAR_COLUMNS, GUTTER } from './constants'
import type { Token } from './highlight'
import { visibleOf, withCursor } from './tokens'
import type { Segment } from './tokens'

type Ui = Pick<Elements['terminal'], 'Box' | 'Text'>
type Style = { color?: string; bold?: boolean; italic?: boolean; dimColor?: boolean }

const share = (style: Style, kinds: string): Record<string, Style> =>
  Object.fromEntries(kinds.split(' ').map(kind => [kind, style]))

// Prism 종류 → 색. 색은 테마 키로 줘서 사용자가 고른 테마를 따라간다.
// 문장부호·연산자는 빈 스타일로 적어, 바깥 조각의 색을 물려받지 않고 기본색으로 그린다.
const STYLE: Record<string, Style> = {
  ...share({}, 'punctuation operator entity'),
  ...share({ dimColor: true }, 'comment prolog doctype cdata blockquote hr'),
  ...share({ color: 'success' }, 'string char attr-value inserted regex url template-string'),
  ...share({ color: 'warning' }, 'number boolean constant symbol'),
  ...share({ color: 'suggestion' }, 'keyword atrule important null list'),
  ...share({ color: 'remember' }, 'function class-name builtin code code-snippet'),
  ...share({ color: 'claude' }, 'tag property key selector coord'),
  ...share({ color: 'permission' }, 'attr-name variable parameter'),
  deleted: { color: 'error' },
  title: { color: 'claude', bold: true },
  bold: { bold: true },
  italic: { italic: true },
}

// 가장 안쪽부터 거슬러 올라가 처음 만나는 아는 종류의 색. 값이 undefined 인 속성은 만들지 않는다.
// 다른 언어 구역(language-*)을 만나면 거기서 멈춘다: 속성 값 안의 JS 가 문자열 색을 물려받지 않게.
const styleOf = (segment: Segment): Style & { inverse?: true } => {
  const known = segment.kinds.findLast(kind => STYLE[kind] !== undefined || kind.startsWith('language-'))
  const style = known === undefined ? {} : (STYLE[known] ?? {})

  return segment.isCursor ? { ...style, inverse: true } : style
}

const paintLine = ({ Box, Text }: Ui, segments: readonly Segment[], number: number) => (
  <Box>
    <Text dimColor>{`${String(number).padStart(GUTTER - 1)} `}</Text>
    {segments.map(segment => (
      <Text {...styleOf(segment)}>{segment.text}</Text>
    ))}
  </Box>
)

// 줄 번호와 색 조각으로 lines[from .. from+count) 를 그린다. cursor 가 있으면 그 자리 글자를 반전한다.
export const paintLines = (
  ui: Ui,
  lines: readonly Token[][],
  view: { from: number; count: number; left: number; room: number },
  cursor: { row: number; col: number } | null,
) => (
  <ui.Box flexDirection="column">
    {lines.slice(view.from, view.from + view.count).map((line, i) => {
      const shown = visibleOf(line, view.left, view.room)
      const isCursorLine = cursor !== null && cursor.row === view.from + i

      return paintLine(ui, isCursorLine ? withCursor(shown, cursor.col - view.left) : shown, view.from + i + 1)
    })}
  </ui.Box>
)

// 세로 스크롤 막대(한 칸 폭). flags: 칸마다 손잡이인지. null 이면(전부 보임) 그리지 않는다.
export const paintBar = ({ Box, Text }: Ui, flags: readonly boolean[] | null) =>
  flags === null ? null : (
    <Box flexDirection="column" width={BAR_COLUMNS} flexShrink={0}>
      {flags.map(isThumb => (
        <Text dimColor={!isThumb}>{isThumb ? '█' : '│'}</Text>
      ))}
    </Box>
  )
