#!/usr/bin/env node
// Bitwarden CLI 대역 — 하류 jj-agent-room tests/fork-env-secrets.test.ts 의 FAKE_BW 를 옮겼다.
// 같은 폴더의 `state` 가 unauthenticated / locked / unlocked, `items.json` 이 금고다.
// 시험마다 이 파일을 금고 폴더에 `bw` 로 복사해 쓴다 (__dirname 이 금고 위치).
const fs = require('fs'), path = require('path')
const state = fs.readFileSync(path.join(__dirname, 'state'), 'utf8').trim()
const store = path.join(__dirname, 'items.json')
const items = fs.existsSync(store) ? JSON.parse(fs.readFileSync(store, 'utf8')) : []
const [cmd, sub, arg] = process.argv.slice(2)
const out = (s) => { process.stdout.write(s); process.exit(0) }
if (cmd === 'status') out(JSON.stringify({ status: state }))
if (state !== 'unlocked') process.exit(1)
if (cmd === 'sync') out('Syncing complete.')
if (cmd === 'encode') out(Buffer.from(fs.readFileSync(0, 'utf8')).toString('base64'))
const save = (list) => fs.writeFileSync(store, JSON.stringify(list))
if (cmd === 'create' && sub === 'item') {
  const item = JSON.parse(Buffer.from(fs.readFileSync(0, 'utf8').trim(), 'base64').toString())
  save([...items, { ...item, id: String(items.length + 1) + '-' + Date.now() }]); out('{}')
}
if (cmd === 'delete' && sub === 'item') { save(items.filter((i) => i.id !== arg)); out('') }
if (cmd === 'list' && sub === 'items') out(JSON.stringify(items.filter((i) => i.name.includes(process.argv[5]))))
if (cmd === 'get' && sub === 'password') { const i = items.find((x) => x.name === arg); if (i) out(i.login.password) }
process.exit(1)
