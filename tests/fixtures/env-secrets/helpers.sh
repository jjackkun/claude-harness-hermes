# env-secrets 시험 공용 도우미 (source 전용). 하류 jj-agent-room tests/fork-env-secrets.test.ts 의
# newRepo · fakeVault · run · originalPc · otherPc 를 bash 로 옮겼다.
# 값은 모두 실행 때 만든다 — 이 파일에 비밀처럼 보이는 문자열이 없어야 "출력에 값 없음" 단언이 뜻을 가진다.
# 계획: docs/exec-plans/active/2026-10-16-env-secrets-preset.md

FIX_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
REPO_ROOT="$(cd "$FIX_DIR/../../.." && pwd)"
# 다른 구현으로 시험 자체를 검증할 때만 바꾼다 (예: 하류 원본을 꽂아 무엇이 갈리는지 보기)
ASSET_DIR="${ENV_SECRETS_ASSET_DIR:-$REPO_ROOT/assets/env-secrets}"
SECRETS_SH="$ASSET_DIR/secrets.sh"
VAULT_ITEM="test-project dotenvx"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
NO_BW="$WORK/no-bw"
NO_LOCAL="$WORK/no-node-modules/dotenvx"   # 공장 판은 프로젝트 node_modules 를 기대하지 않는다 (G3)

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
check() { local desc="$1"; shift; if "$@"; then ok "$desc"; else nope "$desc"; fi; }
has()     { grep -qE -- "$2" <<<"$1"; }
lacks()   { ! grep -qF -- "$2" <<<"$1"; }
no_values() { local out="$1" v; shift; for v in "$@"; do lacks "$out" "$v" || return 1; done; }
mode_of() { stat -c %a "$1"; }
finish() { echo; echo "결과: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]; }

# 고정 판 dotenvx 캐시 — 도구가 쓰는 사용자 캐시와 같은 자리. 없으면 도구와 같은 명령으로 받는다.
require_assets() {
  [[ -f "$SECRETS_SH" ]] || { nope "자산 없음: assets/env-secrets/secrets.sh"; finish; exit 1; }
  local ver
  ver="$(sed -n 's/^ENV_SECRETS_DOTENVX_VERSION="\(.*\)"/\1/p' "$ASSET_DIR/lib/env-secrets-config.sh")"
  CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/env-secrets/dotenvx-$ver"
  if [[ ! -x "$CACHE/node_modules/.bin/dotenvx" ]]; then
    local dotenv_ver
    dotenv_ver="$(sed -n 's/^ENV_SECRETS_DOTENV_VERSION="\(.*\)"/\1/p' "$ASSET_DIR/lib/env-secrets-config.sh")"
    mkdir -p "$CACHE"
    npm install --prefix "$CACHE" --no-save --no-audit --no-fund \
      "@dotenvx/dotenvx@$ver" "dotenv@$dotenv_ver" >"$WORK/cache-install.log" 2>&1 \
      || { nope "dotenvx $ver 캐시 받기 실패 — $WORK/cache-install.log"; finish; exit 1; }
  fi
  export ENV_SECRETS_DEPS="$CACHE"
}

envcheck() { node "$FIX_DIR/env-check.mjs" "$@"; }
rand() { cat /proc/sys/kernel/random/uuid; }

new_repo() { local d; d="$(mktemp -d "$WORK/$1-XXXX")"; git init -q "$d"; echo "$d"; }
git_t() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# fake_vault [state] → 금고 폴더 (bw 는 그 안의 $dir/bw)
fake_vault() {
  local d; d="$(mktemp -d "$WORK/bw-XXXX")"
  cp "$FIX_DIR/fake-bw.js" "$d/bw"; chmod 755 "$d/bw"
  echo "${1:-unlocked}" >"$d/state"; echo "$d"
}
vault_lock() { echo locked >"$1/state"; }
vault_entry() { envcheck vault "$1/items.json" "$VAULT_ITEM"; }   # → "<개수> <비밀번호>"

# run_in <cwd> [VAR=값 …] <secrets.sh 인자…> — OUT·RC 를 채운다. 터미널 없음(stdin=/dev/null).
run_in() {
  local cwd="$1"; shift
  local extra=()
  while [[ $# -gt 0 && "$1" == [A-Z]*=* ]]; do extra+=("$1"); shift; done
  OUT="$(cd "$cwd" && env -i PATH="$PATH" HOME="$cwd" BW_BIN="$NO_BW" ENV_SECRETS_VAULT_ITEM="$VAULT_ITEM" \
    ENV_SECRETS_CACHE="$CACHE" ENV_SECRETS_LOCAL_DOTENVX="$NO_LOCAL" "${extra[@]}" \
    bash "$SECRETS_SH" "$@" </dev/null 2>&1)"
  RC=$?
}

# 첫 PC — 주석·빈 줄·빈 값·따옴표 안의 '#' 이 든 실제 같은 .env 를 import 한다.
# 채우는 것: SRC SRC_TEXT(기대 원문 파일) SRC_VALUES SRC_KEY SRC_VAULT SRC_OUT
original_pc() {
  SRC="$(new_repo src)"; SRC_VAULT="$(fake_vault)"
  local db="postgres://db-$(rand)" ai="openai-$(rand)" google="google-$(rand)" note="two words # $(rand)"
  SRC_VALUES=("$db" "$ai" "$google" "$note")
  printf '%s\n' '# server' 'PORT=5181' "DATABASE_URL=$db" '' '# login' "OPENAI_API_KEY=$ai" \
    "GOOGLE_CLIENT_SECRET=$google" "NOTE_TEXT=\"$note\"" 'EMPTY_FOR_NOW=' >"$SRC/.env"
  SRC_TEXT="$WORK/$(basename "$SRC").expected"; cp "$SRC/.env" "$SRC_TEXT"
  run_in "$SRC" BW_BIN="$SRC_VAULT/bw" import --yes
  SRC_OUT="$OUT"
  [[ $RC -eq 0 ]] || { nope "original_pc import 실패: $OUT"; return 1; }
  SRC_KEY="$(envcheck get "$SRC/.env.keys" DOTENV_PRIVATE_KEY_SECRETS)"
}

# other_pc [own-env-text] [with-keys] → 다른 PC 폴더 (git 이 나르는 .env.secrets 만, 선택으로 자기 .env·.env.keys)
other_pc() {
  local d; d="$(new_repo dst)"
  cp "$SRC/.env.secrets" "$d/.env.secrets"
  [[ -n "${1:-}" ]] && printf '%s' "$1" >"$d/.env"
  [[ "${2:-}" == with-keys ]] && cp "$SRC/.env.keys" "$d/.env.keys"
  echo "$d"
}
