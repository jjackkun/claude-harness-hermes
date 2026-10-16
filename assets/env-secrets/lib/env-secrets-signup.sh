# What someone without a Bitwarden account needs to hear (sourced; needs env-secrets-config.sh).
# The key lives in Bitwarden, so an account is the one thing a person must make by hand —
# without this, a first-time user only saw "Bitwarden 열기 실패" and had no next step.
# Plan: docs/exec-plans/active/2026-10-16-env-secrets-preset.md G8 (공장 claude-harness-hermes)

ENV_SECRETS_SIGNUP_URL="https://vault.bitwarden.com"
ENV_SECRETS_SUBCOMMAND="${ENV_SECRETS_SUBCOMMAND:-open}"   # secrets.sh sets it before running a command

# vault_signup_hint — to stderr. After signing up, the person runs import (first PC) or open (any other).
vault_signup_hint() {
  local again=open
  [[ "$ENV_SECRETS_SUBCOMMAND" == import ]] && again=import
  printf '    Bitwarden 계정이 없으면 %s 에서 무료로 가입하십시오.\n' "$ENV_SECRETS_SIGNUP_URL" >&2
  printf '    마스터 비밀번호는 본인이 정합니다 — 잊으면 Bitwarden 도 되찾아 주지 못합니다.\n' >&2
  printf '    가입한 뒤 다시 실행: %s %s\n' "$ENV_SECRETS_CMD" "$again" >&2
}
