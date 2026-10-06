// 터미널 화면 칸 계산. 한글·한자·전각 문자는 한 글자가 두 칸을 차지한다.
// 범위: 한글 자모, CJK(한자·가나 포함), 한글 음절, CJK 호환, 전각 기호, 그림 문자.
const WIDE: readonly (readonly [number, number])[] = [
  [0x1100, 0x115f],
  [0x2e80, 0xa4cf],
  [0xac00, 0xd7a3],
  [0xf900, 0xfaff],
  [0xfe30, 0xfe4f],
  [0xff00, 0xff60],
  [0xffe0, 0xffe6],
  [0x1f300, 0x1faff],
]

export const cellWidth = (char: string): number => {
  const code = char.codePointAt(0) ?? 0

  return WIDE.some(([first, last]) => code >= first && code <= last) ? 2 : 1
}

export const cellsOf = (text: string): number => [...text].reduce((sum, char) => sum + cellWidth(char), 0)

// room 칸 안에 온전히 들어가는 글자 수(앞에서부터).
export const fit = (line: string, room: number): number => {
  let used = 0
  for (let index = 0; index < line.length; index += 1) {
    used += cellWidth(line[index] ?? '')
    if (used > room) {
      return index
    }
  }

  return line.length
}

// 화면 칸 x(0부터)가 가리키는 글자 자리. 줄 끝을 넘으면 줄 끝.
export const colAt = (line: string, x: number): number => (x <= 0 ? 0 : fit(line, x))

// 커서(col)가 보이도록 왼쪽 시작 글자(left)를 옮긴다. 커서 앞 글자들이 room 칸에 들어가야 한다.
export const followLeft = (line: string, left: number, col: number, room: number): number => {
  if (col < left) {
    return col
  }
  let start = left
  while (cellsOf(line.slice(start, col)) > room) {
    start += 1
  }

  return start
}
