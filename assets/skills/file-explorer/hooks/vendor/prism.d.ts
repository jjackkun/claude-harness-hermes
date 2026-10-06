// 묶음 파일(prism.js)에서 이 모드가 쓰는 부분만 적은 선언.
export type PrismToken = { type: string; content: string | PrismToken | (string | PrismToken)[]; alias?: string | string[] }
export type Grammar = { [name: string]: unknown }
declare const Prism: {
  languages: { [name: string]: Grammar | undefined } & {
    // inside 문법의 before 항목 앞에 insert 를 끼운 새 문법을 돌려준다.
    insertBefore: (inside: string, before: string, insert: Grammar) => Grammar
  }
  util: { clone: <T>(value: T) => T }
  tokenize: (text: string, grammar: Grammar) => (string | PrismToken)[]
}
export default Prism
