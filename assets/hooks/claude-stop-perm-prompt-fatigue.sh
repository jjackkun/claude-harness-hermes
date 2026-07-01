#!/usr/bin/env bash
# Stop hook — 권한 프롬프트 피로도 감지.
#
# 동작: Stop 시점에 transcript 의 Bash tool_use 빈도를 보고, "auto-allow 도 아니고
# settings.local.json 의 permissions.allow 에도 없는" 명령이 임계값 이상 반복됐다면
# stderr 로 fewer-permission-prompts 스킬 사용을 권유.
#
# 비차단 — 항상 exit 0. 출력 없으면 무동작.
# 임계값 오버라이드: env CLAUDE_PERM_FATIGUE_THRESHOLD (기본 5).
#
# 실패 무시: jq 없거나 transcript 못 찾으면 조용히 종료. Stop 흐름을 절대 깨지 않음.

set -uo pipefail

THRESHOLD="${CLAUDE_PERM_FATIGUE_THRESHOLD:-5}"

input="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || exit 0

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
if [[ -z "$transcript" || ! -f "$transcript" ]]; then
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
settings="$project_dir/.claude/settings.local.json"

# permissions.allow 패턴 추출 (Bash(...) 만). 빈 문자열이면 매칭 0개.
allow_patterns=""
if [[ -f "$settings" ]]; then
  allow_patterns="$(jq -r '
    (.permissions.allow // []) | .[]
    | select(startswith("Bash(") and endswith(")"))
    | .[5:-1]
  ' "$settings" 2>/dev/null || true)"
fi

# Auto-allow 첫 토큰 셋 (fewer-permission-prompts 스킬 §4 발췌, 보수적으로 축약).
# 누락된 항목은 노이즈 카운트로 잡혀 살짝 과경고할 수 있으나 무해.
auto_allow_first_token='cal uptime cat head tail wc stat strings hexdump od nl id uname free df du locale groups nproc basename dirname realpath cut paste tr column tac rev fold expand unexpand fmt comm cmp numfmt readlink diff true false sleep which type expr test getconf seq tsort pr echo printf ls cd find pwd whoami alias xargs file sed sort man help netstat ps base64 grep egrep fgrep sha256sum sha1sum md5sum tree date hostname info lsof pgrep tput ss fd fdfind aki rg jq uniq history arch ifconfig pyright'
auto_allow_git='status log diff show blame branch tag remote ls-files ls-remote rev-parse describe stash reflog shortlog cat-file for-each-ref worktree'
auto_allow_gh='pr issue run workflow repo release api auth'
auto_allow_docker='ps images logs inspect'

# Bash command 추출 → 첫 2토큰 키 → 빈도.
# 첫 토큰이 sudo/timeout/env 면 다음 토큰부터 시작.
mapfile -t commands < <(
  jq -r '
    select(.type=="assistant")
    | .message.content[]?
    | select(.type=="tool_use" and .name=="Bash")
    | .input.command // empty
  ' "$transcript" 2>/dev/null
)

[[ ${#commands[@]} -eq 0 ]] && exit 0

declare -A counts

is_auto_allowed() {
  local first="$1" second="$2"
  case " $auto_allow_first_token " in *" $first "*) return 0 ;; esac
  if [[ "$first" == "git" ]]; then
    case " $auto_allow_git " in *" $second "*) return 0 ;; esac
  fi
  if [[ "$first" == "gh" ]]; then
    case " $auto_allow_gh " in *" $second "*) return 0 ;; esac
  fi
  if [[ "$first" == "docker" ]]; then
    case " $auto_allow_docker " in *" $second "*) return 0 ;; esac
  fi
  return 1
}

is_in_allowlist() {
  local cmd="$1"
  [[ -z "$allow_patterns" ]] && return 1
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    local prefix="${pat%\*}"
    prefix="${prefix%[[:space:]]}"
    if [[ "$cmd" == "$prefix" || "$cmd" == "$prefix"* ]]; then
      return 0
    fi
  done <<<"$allow_patterns"
  return 1
}

# Destructive — 빈도 높아도 allowlist 권유 부적절. 카운트 제외.
is_destructive() {
  case "$1" in
    rm|mv|dd|shred|kill) return 0 ;;
  esac
  return 1
}

for cmd in "${commands[@]}"; do
  # leading env-var prefix / sudo / timeout 제거
  while [[ "$cmd" =~ ^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|sudo[[:space:]]+|timeout[[:space:]]+[^[:space:]]+[[:space:]]+) ]]; do
    cmd="${cmd#${BASH_REMATCH[1]}}"
  done
  read -r first second _ <<<"$cmd"
  [[ -z "$first" ]] && continue
  is_destructive "$first" && continue
  is_auto_allowed "$first" "$second" && continue

  # 두번째 토큰이 서브커맨드처럼 보일 때만 키에 포함.
  # 경로(/ 포함), 플래그(-/--), 확장자(.), 값(= 포함) 은 인자로 판단 → 버림.
  if [[ -n "$second" && "$second" != */* && "$second" != -* && "$second" != *.* && "$second" != *=* ]]; then
    key="$first $second"
  else
    key="$first"
  fi

  is_in_allowlist "$key" && continue

  counts[$key]=$(( ${counts[$key]:-0} + 1 ))
done

# 임계값 통과 항목만 추출 (count desc).
hot=""
for key in "${!counts[@]}"; do
  c="${counts[$key]}"
  if (( c >= THRESHOLD )); then
    hot+="$c|$key"$'\n'
  fi
done

[[ -z "$hot" ]] && exit 0

top=$(printf '%s' "$hot" | sort -t'|' -k1 -n -r | head -5)

{
  echo "[harness] 권한 프롬프트 피로도 감지 — 다음 명령이 ≥${THRESHOLD}회 반복됐고 allowlist 에 없습니다:"
  printf '%s\n' "$top" | awk -F'|' '{ printf "  - %s (%d회)\n", $2, $1 }'
  echo "  → 다음 세션에서 /skill fewer-permission-prompts 실행을 검토하세요."
} >&2

exit 0
