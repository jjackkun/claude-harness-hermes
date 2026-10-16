# Make dotenvx usable before `npm install` has run (sourced; needs env-secrets-config.sh).
source "${BASH_SOURCE[0]%/*}/env-secrets-progress.sh"
# A fresh clone has no node_modules, yet `secrets.sh open` must work right away — so when the
# project's own copy is missing, the pinned versions go into a per-user cache once
# (measured 2026-10-16: ~2s, 8.5MB) and env-file.mjs is pointed at it for `dotenv`.

ENV_SECRETS_CACHE="${ENV_SECRETS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/env-secrets/dotenvx-${ENV_SECRETS_DOTENVX_VERSION}}"

# env_secrets_ensure_dotenvx — sets ENV_SECRETS_DOTENVX (and ENV_SECRETS_DEPS for the
# cache); returns 1 with ENV_SECRETS_TOOLS_STATE when neither copy can be had.
env_secrets_ensure_dotenvx() {
  ENV_SECRETS_TOOLS_STATE=""
  if [[ -x "$ENV_SECRETS_LOCAL_DOTENVX" ]]; then
    ENV_SECRETS_DOTENVX="$ENV_SECRETS_LOCAL_DOTENVX"
    return 0
  fi
  export ENV_SECRETS_DEPS="$ENV_SECRETS_CACHE"
  ENV_SECRETS_DOTENVX="$ENV_SECRETS_CACHE/node_modules/.bin/dotenvx"
  [[ -x "$ENV_SECRETS_DOTENVX" && -d "$ENV_SECRETS_CACHE/node_modules/dotenv" ]] && return 0
  if ! command -v npm >/dev/null 2>&1; then
    ENV_SECRETS_TOOLS_STATE="dotenvx 없음 — npm 이 없어 받을 수 없습니다 (Node.js 설치 필요)"
    return 1
  fi
  mkdir -p "$ENV_SECRETS_CACHE"
  local ok=0
  progress_start "dotenvx $ENV_SECRETS_DOTENVX_VERSION 받는 중 (처음 한 번)"
  npm install --prefix "$ENV_SECRETS_CACHE" --no-save --no-audit --no-fund \
    "@dotenvx/dotenvx@$ENV_SECRETS_DOTENVX_VERSION" "dotenv@$ENV_SECRETS_DOTENV_VERSION" \
    >"$ENV_SECRETS_CACHE/install.log" 2>&1 && [[ -x "$ENV_SECRETS_DOTENVX" ]] || ok=1
  progress_stop
  (( ok == 0 )) && return 0
  ENV_SECRETS_TOOLS_STATE="dotenvx 받기 실패 — 로그: $ENV_SECRETS_CACHE/install.log"
  return 1
}
