// 화면 모듈(에디터, 트리, 가로 막대)이 post 로 보낸 값의 모양을 확인한다.

// { source: 글자 } 인가.
export const isSource = (data: unknown): data is { source: string } =>
  typeof data === 'object' && data !== null && typeof (data as { source?: unknown }).source === 'string'

// data[key] 가 유한한 숫자면 그 값, 아니면 null.
export const numberIn = (data: unknown, key: string): number | null => {
  const value = typeof data === 'object' && data !== null ? (data as Record<string, unknown>)[key] : undefined

  return typeof value === 'number' && Number.isFinite(value) ? value : null
}
