# Find the private key that opens .env.secrets (sourced; needs env-secrets-config.sh
# and env-secrets-vault.sh). Order: .env.keys (the PC that made it) → environment →
# Bitwarden, which asks the master password at a terminal when the vault is locked.

ENV_SECRETS_KEY=""
ENV_SECRETS_KEY_SOURCE=""

env_secrets_find_key() {
  ENV_SECRETS_KEY=""
  if [[ -f "$ENV_SECRETS_KEYS_FILE" ]]; then
    ENV_SECRETS_KEY="$(sed -n "s/^$ENV_SECRETS_KEY_NAME=//p" "$ENV_SECRETS_KEYS_FILE" | tr -d '"' | head -n 1)"
    ENV_SECRETS_KEY_SOURCE="$ENV_SECRETS_KEYS_FILE"
    [[ -n "$ENV_SECRETS_KEY" ]] && return 0
  fi
  ENV_SECRETS_KEY="${!ENV_SECRETS_KEY_NAME:-}"
  ENV_SECRETS_KEY_SOURCE="환경변수 $ENV_SECRETS_KEY_NAME"
  [[ -n "$ENV_SECRETS_KEY" ]] && return 0
  vault_private_key || return 1
  ENV_SECRETS_KEY="$ENV_SECRETS_VAULT_KEY"
  ENV_SECRETS_KEY_SOURCE="Bitwarden '$ENV_SECRETS_VAULT_ITEM'"
}

# env_secrets_plaintext [file] — prints the original .env text held in an encrypted
# file (default .env.secrets; dotenvx's header removed). Only ever piped or written
# to a 600 file; returns 1 on a wrong key.
env_secrets_plaintext() {
  local text
  text="$(DOTENV_PRIVATE_KEY_SECRETS="$ENV_SECRETS_KEY" "$ENV_SECRETS_DOTENVX" decrypt -f "${1:-$ENV_SECRETS_FILE}" \
    --stdout --no-armor --no-native 2>/dev/null)" || return 1
  [[ "$text" != *"encrypted:"* ]] || return 1
  printf '%s\n' "$text" | node "$ENV_SECRETS_ENV_FILE_JS" unwrap
}
