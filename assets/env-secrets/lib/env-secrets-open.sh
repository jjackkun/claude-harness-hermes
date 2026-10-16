# Open .env.secrets into this PC's .env (sourced; needs env-secrets-config.sh,
# env-secrets-tools.sh, env-secrets-vault.sh, env-secrets-key.sh). No .env here → the other PC's whole
# file comes back exactly; a .env here → every value is brought up to date and keys
# only this PC has stay. Plaintext moves only through pipes and 600 files.
# Callers print ENV_SECRETS_RESULT; the status says how it went:
ENV_SECRETS_OPENED=0      # .env written or updated
ENV_SECRETS_NO_FILE=10    # nothing in git to open yet
ENV_SECRETS_NO_KEY=11     # no key found (vault locked, bw missing …) — nothing written
ENV_SECRETS_FAILED=12     # wrong key or write failure — .env left as it was
ENV_SECRETS_RESULT=""

env_secrets_restore() {
  local tmp=".env.tmp-$$"
  (umask 077 && env_secrets_plaintext >"$tmp") || { rm -f "$tmp"; return 1; }
  mv "$tmp" .env
  ENV_SECRETS_RESULT="열쇠: $ENV_SECRETS_KEY_SOURCE · .env 를 그대로 복원 ($(grep -cE '^\s*[A-Za-z_]' .env)개 키)"
}

env_secrets_update() {
  local json counts added updated same
  json="$(DOTENV_PRIVATE_KEY_SECRETS="$ENV_SECRETS_KEY" "$ENV_SECRETS_DOTENVX" get -f "$ENV_SECRETS_FILE" \
    --format json "${ENV_SECRETS_DOTENVX_FLAGS[@]}" 2>/dev/null)" || return 1
  counts="$(printf '%s' "$json" | node "$ENV_SECRETS_ENV_FILE_JS" merge .env)" || return 1
  read -r added updated same <<<"$counts"
  ENV_SECRETS_RESULT="열쇠: $ENV_SECRETS_KEY_SOURCE · 추가 $added · 갱신 $updated · 같음 $same"
}

env_secrets_open() {
  if [[ ! -f "$ENV_SECRETS_FILE" ]]; then
    ENV_SECRETS_RESULT="$ENV_SECRETS_FILE 없음 — 값이 든 PC 에서 $ENV_SECRETS_CMD import"
    return "$ENV_SECRETS_NO_FILE"
  fi
  if ! env_secrets_ensure_dotenvx; then
    ENV_SECRETS_RESULT="$ENV_SECRETS_TOOLS_STATE"
    return "$ENV_SECRETS_FAILED"
  fi
  if ! env_secrets_find_key; then
    ENV_SECRETS_RESULT="열쇠 없음 ($ENV_SECRETS_KEYS_FILE · $ENV_SECRETS_KEY_NAME · ${ENV_SECRETS_VAULT_STATE:-Bitwarden}) — 해결 후 다시 실행"
    return "$ENV_SECRETS_NO_KEY"
  fi
  if [[ -f .env ]]; then env_secrets_update; else env_secrets_restore; fi && return "$ENV_SECRETS_OPENED"
  ENV_SECRETS_RESULT="열쇠($ENV_SECRETS_KEY_SOURCE)로 풀리지 않음 — 다른 열쇠인지 확인. .env 는 그대로"
  return "$ENV_SECRETS_FAILED"
}
