// Builds the Bitwarden login item that holds the .env.secrets private key.
// The key comes in on stdin and leaves on stdout, straight into `bw encode`;
// it is never an argument. Shape: Bitwarden CLI `bw get template item`.
//   node env-vault-item.mjs <item name>  < key
import { readFileSync } from 'node:fs'

const LOGIN_ITEM_TYPE = 1
const name = process.argv[2]
const key = readFileSync(0, 'utf8').trim()
if (!name || !key) {
  process.stderr.write('env-vault-item.mjs: item name and key (stdin) are required\n')
  process.exit(1)
}
const item = {
  organizationId: null,
  collectionIds: null,
  folderId: null,
  type: LOGIN_ITEM_TYPE,
  name,
  notes: 'dotenvx private key (DOTENV_PRIVATE_KEY_SECRETS) that opens .env.secrets in git. Created by scripts/env-secrets/secrets.sh import.',
  favorite: false,
  fields: [],
  login: { uris: [], username: null, password: key, totp: null },
  secureNote: null,
  card: null,
  identity: null,
  reprompt: 0,
}
process.stdout.write(JSON.stringify(item))
