// env-secrets 시험의 단언용 .env 읽기. 값은 화면에 내지 않고 키 이름·종료 코드로만 답한다.
// 파서는 도구와 같은 dotenv (ENV_SECRETS_DEPS = dotenvx 캐시 폴더).
//   keys <file>               공개키 줄을 뺀 키 이름 (정렬, 줄마다 하나)
//   sealed <file>             공개키 줄을 뺀 모든 값이 encrypted: 로 시작하면 0
//   get <file> <key>          그 키의 값 (열쇠 파일에서 열쇠를 꺼낼 때만 쓴다)
//   covers <expected> <actual> expected 의 모든 키가 actual 에서 같은 값이면 0, 아니면 다른 키 이름
//   vault <items.json> <name> 그 이름의 항목 수와 첫 항목 비밀번호 (열쇠 비교용)
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'

const { parse } = createRequire(`${process.env.ENV_SECRETS_DEPS}/`)('dotenv')
const read = (file) => parse(readFileSync(file))
const entries = (file) => Object.entries(read(file)).filter(([k]) => !k.startsWith('DOTENV_PUBLIC_KEY'))
const [cmd, a, b] = process.argv.slice(2)

if (cmd === 'keys') {
  process.stdout.write(entries(a).map(([k]) => k).sort().join('\n') + '\n')
} else if (cmd === 'sealed') {
  const plain = entries(a).filter(([, v]) => !v.startsWith('encrypted:')).map(([k]) => k)
  if (plain.length) { process.stdout.write(plain.join(' ') + '\n'); process.exit(1) }
} else if (cmd === 'get') {
  process.stdout.write(read(a)[b] ?? '')
} else if (cmd === 'covers') {
  const actual = read(b)
  const diff = Object.entries(read(a)).filter(([k, v]) => actual[k] !== v).map(([k]) => k)
  if (diff.length) { process.stdout.write(diff.join(' ') + '\n'); process.exit(1) }
} else if (cmd === 'vault') {
  const items = JSON.parse(readFileSync(a, 'utf8')).filter((i) => i.name === b)
  process.stdout.write(`${items.length} ${items[0]?.login.password ?? ''}`)
} else {
  process.stderr.write(`env-check.mjs: 모르는 명령 ${cmd}\n`)
  process.exit(2)
}
