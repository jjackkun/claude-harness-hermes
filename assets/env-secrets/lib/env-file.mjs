// Reads and writes .env text for scripts/env-secrets/secrets.sh.
// Values only ever travel through files and pipes; stdout carries the .env text
// (into a file or a comparison) or counts, never a value on a terminal.
// Parsing uses `dotenv`, the parser the server loads .env with.
//   unwrap        decrypted .env.secrets text on stdin → the original .env text
//   merge <env>   JSON object on stdin → <env>, prints "added updated same"
import { existsSync, readFileSync, renameSync, statSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'

// The project's dotenv, or — before `npm install` — the copy env-secrets-tools.sh cached.
const deps = process.env.ENV_SECRETS_DEPS
const { parse } = createRequire(deps ? `${deps}/` : import.meta.url)('dotenv')

const isInternal = (key) => key.startsWith('DOTENV_')
const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
// What `dotenvx encrypt` adds on top of the file it was given.
const DOTENVX_BANNER = /^#\//
const PUBLIC_KEY_LINE = /^DOTENV_PUBLIC_KEY_[A-Z0-9_]*=/
const FILE_NAME_COMMENT = '# .env.secrets'

function formatValue(value) {
  if (/^[\w.:/@+=,~%-]*$/.test(value)) return value
  if (!value.includes("'") && !value.includes('\n')) return `'${value}'`
  // dotenv turns \n inside double quotes into a newline, so a literal backslash would not survive.
  if (!value.includes('"') && !value.includes('\\')) return `"${value.replaceAll('\n', '\\n')}"`
  throw new Error('a value cannot be written to .env so that it reads back unchanged')
}

// One trailing newline, so texts compare equal however the tools ended them.
const normalize =(text) => `${text.replace(/\n+$/, '')}\n`

function unwrap(text) {
  const lines = text.split('\n').filter((l) => !DOTENVX_BANNER.test(l) && !PUBLIC_KEY_LINE.test(l))
  while (lines.length && lines[0].trim() === '') lines.shift()
  if (lines[0] === FILE_NAME_COMMENT) lines.shift()
  return normalize(lines.join('\n'))
}

// Replace <path> in one step so an interrupted run never leaves a half-written
// .env; keep its mode, and create a new one readable by the owner only.
function writeAtomic(path, text) {
  const mode = existsSync(path) ? statSync(path).mode & 0o777 : 0o600
  const tmp = `${path}.tmp-${process.pid}`
  writeFileSync(tmp, text, { mode })
  renameSync(tmp, path)
}

function merge(envPath, incoming) {
  const entries = Object.entries(incoming).filter(([k]) => !isInternal(k))
  // A value still encrypted means decryption silently failed; never write ciphertext into .env.
  const sealed = entries.filter(([, v]) => v.startsWith('encrypted:')).map(([k]) => k)
  if (sealed.length) throw new Error(`still encrypted, .env left unchanged: ${sealed.join(', ')}`)
  const lines = existsSync(envPath) ? readFileSync(envPath, 'utf8').split('\n') : []
  if (lines.at(-1) === '') lines.pop()
  const counts = { added: 0, updated: 0, same: 0 }
  for (const [key, value] of entries) {
    const line = `${key}=${formatValue(value)}`
    const pattern = new RegExp(`^\\s*(?:export\\s+)?${escapeRegExp(key)}\\s*=`)
    const at = lines.findIndex((l) => pattern.test(l))
    if (at === -1) { lines.push(line); counts.added++ }
    else if (parse(lines[at])[key] === value) counts.same++
    else { lines[at] = line; counts.updated++ }
  }
  writeAtomic(envPath, `${lines.join('\n')}\n`)
  process.stdout.write(`${counts.added} ${counts.updated} ${counts.same}\n`)
}

const [command, ...args] = process.argv.slice(2)
try {
  if (command === 'unwrap') process.stdout.write(unwrap(readFileSync(0, 'utf8')))
  else if (command === 'merge') merge(args[0], JSON.parse(readFileSync(0, 'utf8')))
  else throw new Error(`unknown command ${command}`)
} catch (error) {
  process.stderr.write(`env-file.mjs: ${error instanceof Error ? error.message : String(error)}\n`)
  process.exit(1)
}
