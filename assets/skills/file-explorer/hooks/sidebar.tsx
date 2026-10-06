import type { Elements } from 'claude-code'

import { DIVIDER_COLUMNS, DIVIDER_KEY } from './constants'

type Ui = Elements['terminal']
// 왼쪽 칸(트리 또는 git 목록)의 폭과, 세로선을 끌어 갈 수 있는 한계
export type Side = { width: number; min: number; max: number }

// 왼쪽 칸과 보기 화면 사이의 세로선. editor 탭과 git 탭이 같은 것을 쓴다.
export const divider = ({ Client }: Ui, side: Side, rows: number) => (
  <Client key={DIVIDER_KEY} module="./divider.tsx" props={{ ...side, rows }} width={DIVIDER_COLUMNS} height={rows} />
)
