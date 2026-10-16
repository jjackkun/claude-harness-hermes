# Ask for the Bitwarden master password and open the vault, with a spinner while
# bw works (sourced; needs env-secrets-vault.sh and env-secrets-progress.sh).
# We read the password ourselves (hidden) instead of letting bw prompt, so the
# seconds after Enter show progress instead of looking like a hang. The password
# reaches bw only through its own environment (--passwordenv), never argv.

VAULT_UNLOCK_ATTEMPTS=3

# vault_unlock_interactive <locked|unauthenticated> — exports BW_SESSION on success.
vault_unlock_interactive() {
  local state="$1" email="" password session attempt
  printf '    Bitwarden 금고를 엽니다 (입력은 화면에 보이지 않습니다).\n' >&2
  if [[ "$state" != locked ]]; then
    vault_signup_hint
    IFS= read -r -p "    Bitwarden 이메일: " email </dev/tty
  fi
  for (( attempt = 1; attempt <= VAULT_UNLOCK_ATTEMPTS; attempt++ )); do
    IFS= read -rs -p "    마스터 비밀번호: " password </dev/tty
    printf '\n' >&2
    progress_start "금고 여는 중"
    if [[ "$state" == locked ]]; then
      session="$(ENV_SECRETS_BW_PASSWORD="$password" vault_bw unlock --passwordenv ENV_SECRETS_BW_PASSWORD --raw 2>/dev/null)"
    else
      session="$(ENV_SECRETS_BW_PASSWORD="$password" vault_bw login "$email" --passwordenv ENV_SECRETS_BW_PASSWORD --raw 2>/dev/null)"
    fi
    progress_stop
    password=""
    if [[ -n "$session" ]]; then
      export BW_SESSION="$session"
      return 0
    fi
    printf '    ✘ 열지 못했습니다 — 비밀번호를 확인하십시오 (%d/%d)\n' "$attempt" "$VAULT_UNLOCK_ATTEMPTS" >&2
  done
  ENV_SECRETS_VAULT_STATE="Bitwarden 열기 실패 (비밀번호 ${VAULT_UNLOCK_ATTEMPTS}회 틀림, 또는 2단계 인증이면 bw login 을 먼저 직접 실행)"
  [[ "$state" == locked ]] || vault_signup_hint
  return 1
}
