# Where the shared secrets live and how dotenvx is called (sourced, not executed).
# Plan: docs/exec-plans/active/2026-10-16-env-secrets-preset.md (공장 claude-harness-hermes)

ENV_SECRETS_LIB="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
ENV_SECRETS_ROOT="$(cd "$ENV_SECRETS_LIB/../../.." && pwd)"
ENV_SECRETS_FILE=".env.secrets"
ENV_SECRETS_KEYS_FILE=".env.keys"
ENV_SECRETS_KEY_NAME="DOTENV_PRIVATE_KEY_SECRETS"
# How a person runs this tool in an installed project (the factory env-secrets preset puts it here).
ENV_SECRETS_CMD="bash scripts/env-secrets/secrets.sh"
# The Bitwarden item whose password field holds the private key — one per
# project, named after the project folder, so several projects share a vault.
ENV_SECRETS_VAULT_ITEM="${ENV_SECRETS_VAULT_ITEM:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)") dotenvx}"
# Installed on first use when missing. Pinned like dotenvx: a release at least two
# weeks old (2026.10.0 was one day old on 2026-10-16).
ENV_SECRETS_BW_PACKAGE="@bitwarden/cli@2026.9.1"
# The project's own copy, if it has dotenvx in node_modules; env-secrets-tools.sh falls back
# to a per-user cache of the same versions when node_modules is not there yet.
ENV_SECRETS_DOTENVX_VERSION="2.32.3"
ENV_SECRETS_DOTENV_VERSION="17.4.2"
ENV_SECRETS_LOCAL_DOTENVX="${ENV_SECRETS_LOCAL_DOTENVX:-$ENV_SECRETS_ROOT/node_modules/.bin/dotenvx}"
ENV_SECRETS_DOTENVX="$ENV_SECRETS_LOCAL_DOTENVX"
ENV_SECRETS_ENV_FILE_JS="$ENV_SECRETS_LIB/env-file.mjs"
# dotenvx would otherwise reach for the OS secret store, its paid Armor service
# or its own password-manager lookups depending on the machine; this script
# decides where the key comes from, so every PC behaves the same.
ENV_SECRETS_DOTENVX_FLAGS=(--no-armor --no-native --no-1password --no-bitwarden)
