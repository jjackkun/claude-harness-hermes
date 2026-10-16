#!/usr/bin/env bash
# The whole .env travels between PCs as .env.secrets (encrypted, in git); the key
# that opens it lives in Bitwarden. Plan: docs/exec-plans/active/2026-10-16-env-secrets-preset.md (공장 claude-harness-hermes)
#   import [--yes]   first PC: encrypt this .env into .env.secrets, key → Bitwarden (never shown)
#   sync [--stage]   .env changed since .env.secrets? re-encrypt with the same key
#                    (the commit gate runs it with --stage; it never blocks a commit)
#   open             another PC: .env.secrets → .env (asks only the Bitwarden master password)
set -euo pipefail
ENV_SECRETS_HERE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$ENV_SECRETS_HERE/lib/env-secrets-config.sh"
source "$ENV_SECRETS_HERE/lib/env-secrets-tools.sh"
source "$ENV_SECRETS_HERE/lib/env-secrets-vault.sh"
source "$ENV_SECRETS_HERE/lib/env-secrets-key.sh"
source "$ENV_SECRETS_HERE/lib/env-secrets-open.sh"
cd "$(git rev-parse --show-toplevel)"

die() { progress_stop; printf '✘ %s\n' "$1" >&2; exit 1; }

new_tmp_dir() {
  ENV_SECRETS_TMP="$(mktemp -d)"
  chmod 700 "$ENV_SECRETS_TMP"
  # Expanded now, so the trap still knows the path after the caller returns.
  trap "rm -rf -- '$ENV_SECRETS_TMP'" EXIT
}

# encrypt_into <plain file> <keys file> — in place. </dev/null: at a terminal dotenvx
# asks "Choose private key custody"; the answer is always the -fk file here.
encrypt_into() {
  "$ENV_SECRETS_DOTENVX" encrypt -f "$1" -fk "$2" "${ENV_SECRETS_DOTENVX_FLAGS[@]}" >/dev/null 2>&1 </dev/null
}

confirm() {
  [[ "${1:-}" == --yes ]] && return 0
  [[ -t 0 ]] || die "터미널이 아니면 확인할 수 없습니다 — 목록을 확인했다면 --yes 를 붙이십시오"
  local answer
  read -r -p "이 .env 전체를 암호화해 $ENV_SECRETS_FILE 로 만들까요? [y/N] " answer
  [[ "$answer" == [yY] ]] || die "취소했습니다"
}

# An item whose .env.secrets never reached git opens nothing (a run cut short after
# the vault took the key); one that git has seen may be the live key, so keep it.
replace_orphan_item() {
  local old_item
  old_item="$(vault_item_id)" || return 0
  [[ -z "$(git log --all --oneline -- "$ENV_SECRETS_FILE" 2>/dev/null)" ]] \
    || die "Bitwarden 에 '$ENV_SECRETS_VAULT_ITEM' 가 있고 git 에도 $ENV_SECRETS_FILE 기록이 있습니다 — git pull 후 $ENV_SECRETS_CMD open 으로 여십시오"
  vault_trash_item "$old_item" || die "짝 없는 이전 항목 '$ENV_SECRETS_VAULT_ITEM' 을 휴지통으로 보내지 못했습니다"
  printf '짝 없는 이전 항목 "%s" 을 Bitwarden 휴지통으로 보냈습니다 (30일 안에 되살릴 수 있음).\n' "$ENV_SECRETS_VAULT_ITEM"
}

cmd_import() {
  [[ -f .env ]] || die ".env 가 없습니다 — 값이 들어 있는 PC 에서 실행하십시오"
  [[ ! -e "$ENV_SECRETS_FILE" ]] || die "$ENV_SECRETS_FILE 가 이미 있습니다 — .env 를 고치면 커밋할 때 자동으로 다시 암호화됩니다"
  ! grep -q "^$ENV_SECRETS_KEY_NAME=" "$ENV_SECRETS_KEYS_FILE" 2>/dev/null \
    || die "$ENV_SECRETS_KEYS_FILE 에 이전 열쇠가 남아 있습니다 — 그 열쇠가 Bitwarden 에 없다면 $ENV_SECRETS_KEYS_FILE 를 지우고 다시 실행하십시오"
  printf '.env 전체를 암호화합니다 (키 %d개, 값은 보이지 않음):\n' "$(grep -cE '^\s*[A-Za-z_][A-Za-z0-9_.-]*\s*=' .env)"
  grep -oE '^\s*[A-Za-z_][A-Za-z0-9_.-]*' .env | sed 's/^\s*/  - /'
  confirm "${1:-}"
  env_secrets_ensure_dotenvx || die "$ENV_SECRETS_TOOLS_STATE"
  vault_open || die "Bitwarden 을 열 수 없습니다 ($ENV_SECRETS_VAULT_STATE) — $ENV_SECRETS_FILE 는 만들지 않았습니다"
  replace_orphan_item
  new_tmp_dir
  local plain="$ENV_SECRETS_TMP/$ENV_SECRETS_FILE" keys="$ENV_SECRETS_TMP/$ENV_SECRETS_KEYS_FILE"
  cp .env "$plain"
  progress_start "암호화하고 열쇠를 Bitwarden 에 저장하는 중"
  encrypt_into "$plain" "$keys"
  # The vault must take the key before .env.secrets exists: a file nobody can open is worse than none.
  local stored=0
  sed -n "s/^$ENV_SECRETS_KEY_NAME=//p" "$keys" | tr -d '"' | head -n 1 | vault_store_key || stored=1
  progress_stop
  (( stored == 0 )) || die "열쇠를 Bitwarden 에 저장하지 못했습니다 — $ENV_SECRETS_FILE 는 만들지 않았습니다"
  mv "$plain" "$ENV_SECRETS_FILE"
  chmod 644 "$ENV_SECRETS_FILE"
  cat "$keys" >>"$ENV_SECRETS_KEYS_FILE"
  chmod 600 "$ENV_SECRETS_KEYS_FILE"
  printf '\n✔ %s 를 만들었습니다 (커밋 대상). 열쇠는 Bitwarden "%s" 와 이 PC 의 %s 에 있습니다 (git 밖).\n' \
    "$ENV_SECRETS_FILE" "$ENV_SECRETS_VAULT_ITEM" "$ENV_SECRETS_KEYS_FILE"
  printf '다음: git add %s && git commit && git push — 다른 PC 에서는 %s open (마스터 비밀번호만 물음)\n' \
    "$ENV_SECRETS_FILE" "$ENV_SECRETS_CMD"
}

# Never fails the caller: a commit must not stop because the vault is locked.
cmd_sync() {
  [[ -f .env && -f "$ENV_SECRETS_FILE" ]] || return 0
  env_secrets_ensure_dotenvx || { printf '[secrets] %s — .env.secrets 확인 건너뜀\n' "$ENV_SECRETS_TOOLS_STATE" >&2; return 0; }
  if ! env_secrets_find_key; then
    printf '[secrets] .env.secrets 를 확인하지 못했습니다 (열쇠 없음: %s) — .env 를 바꿨다면 bw unlock 후 다시 커밋\n' \
      "${ENV_SECRETS_VAULT_STATE:-Bitwarden}" >&2
    return 0
  fi
  new_tmp_dir
  local current="$ENV_SECRETS_TMP/current" plain="$ENV_SECRETS_TMP/$ENV_SECRETS_FILE"
  env_secrets_plaintext >"$current" || { printf '[secrets] 열쇠(%s)로 .env.secrets 가 풀리지 않습니다\n' "$ENV_SECRETS_KEY_SOURCE" >&2; return 0; }
  node "$ENV_SECRETS_ENV_FILE_JS" unwrap <.env | cmp -s - "$current" && return 0
  # Same public key on top → dotenvx reuses the key pair, so Bitwarden stays valid.
  { grep -E '^DOTENV_PUBLIC_KEY_SECRETS=' "$ENV_SECRETS_FILE"; cat .env; } >"$plain"
  encrypt_into "$plain" "$ENV_SECRETS_TMP/unused.keys"
  # Only replace what git carries if the same key opens the new file to exactly this .env.
  env_secrets_plaintext "$plain" | cmp -s - <(node "$ENV_SECRETS_ENV_FILE_JS" unwrap <.env) \
    || { printf '[secrets] 다시 암호화한 파일이 같은 열쇠로 풀리지 않아 그대로 둡니다\n' >&2; return 0; }
  mv "$plain" "$ENV_SECRETS_FILE"
  chmod 644 "$ENV_SECRETS_FILE"
  [[ "${1:-}" == --stage ]] && git add "$ENV_SECRETS_FILE"
  printf '[secrets] .env 가 바뀌어 %s 를 같은 열쇠로 다시 암호화했습니다%s\n' "$ENV_SECRETS_FILE" \
    "$([[ "${1:-}" == --stage ]] && echo ' (이번 커밋에 포함)')" >&2
}

cmd_open() {
  local status=0
  env_secrets_open || status=$?
  case "$status" in
    "$ENV_SECRETS_OPENED") printf '✔ %s\n' "$ENV_SECRETS_RESULT" ;;
    "$ENV_SECRETS_NO_FILE") printf '– %s\n' "$ENV_SECRETS_RESULT" ;;
    *) die "$ENV_SECRETS_RESULT" ;;
  esac
}

ENV_SECRETS_SUBCOMMAND="${1:-}"   # the signup hint names the command to run again
case "${1:-}" in
  import) shift; cmd_import "$@" ;;
  sync) shift; cmd_sync "$@" ;;
  open) shift; cmd_open ;;
  *) die "사용법: secrets.sh import [--yes] | sync [--stage] | open" ;;
esac
