# The .env.secrets private key lives in Bitwarden (sourced). Read it, store it,
# and open the vault when it is locked. The key and the session only travel
# through shell variables, pipes and the environment of `bw` itself — never
# argv, stdout or a log. BW_BIN overrides the binary (tests use a fake one).

ENV_SECRETS_VAULT_KEY=""
ENV_SECRETS_VAULT_STATE=""
source "${BASH_SOURCE[0]%/*}/env-secrets-progress.sh"
source "${BASH_SOURCE[0]%/*}/env-secrets-signup.sh"
source "${BASH_SOURCE[0]%/*}/env-secrets-unlock.sh"

# bw is a Node program; where IPv6 has no route (measured 2026-10-16 on WSL: -6 fails,
# -4 answers in <1s) it can hang on the server call, so prefer IPv4 and cap each call.
# --foreground keeps the master-password prompt on the terminal.
VAULT_BW_TIMEOUT_SECONDS=60
vault_bw() {
  NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--dns-result-order=ipv4first" \
    timeout --foreground "$VAULT_BW_TIMEOUT_SECONDS" "${BW_BIN:-bw}" "$@"
}

# vault_status — prints unauthenticated / locked / unlocked, or "missing".
vault_status() {
  command -v "${BW_BIN:-bw}" >/dev/null 2>&1 || { echo missing; return; }
  vault_bw status 2>/dev/null | grep -oE '"status":"[a-z]+"' | cut -d'"' -f4
}

# vault_install — puts the pinned Bitwarden CLI on PATH with npm (no sudo under nvm).
# Only for the real binary: a BW_BIN override (tests) is never installed over.
vault_install() {
  [[ -z "${BW_BIN:-}" ]] || return 1
  command -v npm >/dev/null 2>&1 || return 1
  local log="${TMPDIR:-/tmp}/env-secrets-bw-install.log"
  local ok=0
  progress_start "Bitwarden CLI 설치 중 ($ENV_SECRETS_BW_PACKAGE)"
  npm install -g "$ENV_SECRETS_BW_PACKAGE" >"$log" 2>&1 && command -v bw >/dev/null 2>&1 || ok=1
  progress_stop
  (( ok == 0 )) || { printf '    설치 실패 — 로그: %s\n' "$log" >&2; return 1; }
}

# vault_open — make the vault usable for this run. At a terminal it asks for the
# master password (env-secrets-unlock.sh); the session is exported only to
# this process and its children. Returns 1 with ENV_SECRETS_VAULT_STATE set.
vault_open() {
  local state
  state="$(vault_status)"
  if [[ "$state" == missing ]] && vault_install; then state="$(vault_status)"; fi
  [[ "$state" == unlocked ]] && return 0
  case "$state" in
    missing) ENV_SECRETS_VAULT_STATE="bw 없음 — 자동 설치 실패, npm i -g $ENV_SECRETS_BW_PACKAGE"; return 1 ;;
    unauthenticated|locked) ;;
    *) ENV_SECRETS_VAULT_STATE="bw 상태 알 수 없음"; return 1 ;;
  esac
  if [[ ! -t 0 || ! -t 2 ]]; then
    ENV_SECRETS_VAULT_STATE="bw $([[ $state == locked ]] && echo 잠김 || echo 로그인 안 됨) — 터미널에서 다시 실행"
    [[ "$state" == locked ]] || vault_signup_hint
    return 1
  fi
  vault_unlock_interactive "$state"
}

# vault_private_key — sets ENV_SECRETS_VAULT_KEY from the item's password field.
vault_private_key() {
  ENV_SECRETS_VAULT_KEY=""
  vault_open || return 1
  progress_start "Bitwarden 에서 열쇠 가져오는 중"
  # The CLI reads a local copy of the vault; an item stored from another PC appears only after a sync.
  vault_bw sync --nointeraction >/dev/null 2>&1 || true
  ENV_SECRETS_VAULT_KEY="$(vault_bw get password "$ENV_SECRETS_VAULT_ITEM" --nointeraction 2>/dev/null)" || ENV_SECRETS_VAULT_KEY=""
  progress_stop
  if [[ -z "$ENV_SECRETS_VAULT_KEY" ]]; then
    ENV_SECRETS_VAULT_KEY=""
    ENV_SECRETS_VAULT_STATE="Bitwarden 에 '$ENV_SECRETS_VAULT_ITEM' 항목 없음"
    return 1
  fi
}

# vault_item_id — prints the id of the item with exactly this name; 1 when none.
vault_item_id() {
  vault_bw list items --search "$ENV_SECRETS_VAULT_ITEM" --nointeraction 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const i=JSON.parse(s||"[]").find(x=>x.name===process.argv[1]);if(!i)process.exit(1);process.stdout.write(i.id)})' \
      "$ENV_SECRETS_VAULT_ITEM"
}

# vault_trash_item <id> — Bitwarden keeps deleted items in its trash for 30 days.
vault_trash_item() { vault_bw delete item "$1" --nointeraction >/dev/null 2>&1; }

# vault_store_key — the key arrives on stdin and becomes a new login item.
vault_store_key() {
  node "$ENV_SECRETS_LIB/env-vault-item.mjs" "$ENV_SECRETS_VAULT_ITEM" | vault_bw encode \
    | vault_bw create item --nointeraction >/dev/null 2>&1
}
