# A spinner with elapsed seconds for the slow vault/crypto steps (sourced). Without
# it, the seconds after the master password look like a hang. Only on a terminal
# (stderr); otherwise silent, so logs and tests see no control characters.

PROGRESS_FRAMES='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
PROGRESS_TICK_SECONDS=0.1
PROGRESS_PID=""

# progress_start "금고 여는 중" — replaces any spinner already running.
progress_start() {
  progress_stop
  [[ -t 2 ]] || return 0
  local label="$1"
  (
    local i=0 start=$SECONDS
    # $$ is the script itself: if it dies without progress_stop, the spinner goes too.
    while kill -0 "$$" 2>/dev/null; do
      printf '\r\033[K    %s %s… %ss' "${PROGRESS_FRAMES:i++%${#PROGRESS_FRAMES}:1}" "$label" $((SECONDS - start)) >&2
      sleep "$PROGRESS_TICK_SECONDS"
    done
  ) &
  PROGRESS_PID=$!
  disown "$PROGRESS_PID" 2>/dev/null || true
}

progress_stop() {
  [[ -n "$PROGRESS_PID" ]] || return 0
  kill "$PROGRESS_PID" 2>/dev/null || true
  wait "$PROGRESS_PID" 2>/dev/null || true
  PROGRESS_PID=""
  printf '\r\033[K' >&2
}
