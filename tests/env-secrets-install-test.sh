#!/usr/bin/env bash
# env-secrets 프리셋 — 선택 설치 · .gitignore · 커밋 게이트 R-env-secrets
# (계획 docs/exec-plans/active/2026-10-16-env-secrets-preset.md G1·G4·G5).
#
#   G1  presets.lock 에 env-secrets 가 있는 프로젝트에만 scripts/env-secrets/ 가 깔린다
#   G4  .env.keys 는 git 이 무시하고 .env.secrets 는 추적한다
#   G5  게이트: 바뀐 .env 를 다시 암호화해 그 커밋에 넣는다 / 그대로면 pass / 스크립트 없으면 skipped /
#       스크립트가 실패해도 커밋은 통과 / 터미널에서 금고가 잠겨 있어도 비밀번호를 기다리며 멈추지 않는다
#       (마지막 것은 회귀 시험이다 — git 2.43 은 훅 stdin 을 /dev/null 로 주고 게이트는 stderr 도 받아서, 하류 방식
#        `secrets.sh sync --stage || true` 도 pty 에서 멈추지 않았다(2026-10-16 실측). 그 성질이 깨지면 빨개진다.)
# 게이트는 pre-commit.sh 에서 `# GATE: R-env-secrets` ~ `# /R-env-secrets` 블록만 잘라 최소 훅으로 돈다
# (doc-counts-autofix-test.sh 와 같은 방식 — 다른 게이트와 섞이지 않게).
#
# 실행: bash tests/env-secrets-install-test.sh
set -uo pipefail
source "$(dirname "$0")/fixtures/env-secrets/helpers.sh"
require_assets
# 멈춤 판정 상한: 정상 경로는 dotenvx 캐시가 있으면 수 초다. 하류 bw 호출 상한(60초)보다 짧게 잡아
# "비밀번호 입력 대기" 와 "느린 bw 호출" 을 구분한다.
HANG_CAP_SECONDS=30
export HOME="$WORK/home"; mkdir -p "$HOME"
install_into() { HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0 HERMES_NO_REGISTER=1 \
  bash "$REPO_ROOT/project-claude.sh" "$1" "${@:2}" >"$WORK/install-$RANDOM.log" 2>&1; }

echo "== 선택 설치 (G1)"
P="$(new_repo with)"; Q="$(new_repo without)"
install_into "$P" adhd env-secrets; P_RC=$?
install_into "$Q" adhd
check "env-secrets 프리셋 설치 성공" [ "$P_RC" -eq 0 ]
check "lock 에 env-secrets 가 남는다" grep -qx env-secrets "$P/.claude/presets.lock"
check "고른 프로젝트에 secrets.sh 가 실행 가능하게 깔린다" [ -x "$P/scripts/env-secrets/secrets.sh" ]
check "lib 도 함께 깔린다" [ -f "$P/scripts/env-secrets/lib/env-secrets-config.sh" -a -f "$P/scripts/env-secrets/lib/env-file.mjs" ]
check "init 연동 파일은 깔리지 않는다 (하류 전용)" [ ! -e "$P/scripts/env-secrets/lib/env-secrets.sh" ]
check "고르지 않은 프로젝트에는 아무것도 생기지 않는다" [ ! -e "$Q/scripts/env-secrets" ]
check "공장은 package.json 을 만들지 않는다" [ ! -e "$P/package.json" ]

echo "== .gitignore (G4)"
check ".env.keys 는 git 이 무시한다" git -C "$P" check-ignore -q .env.keys
git -C "$P" check-ignore -q .env.secrets; IGN=$?
check ".env.secrets 는 git 이 추적한다" [ "$IGN" -eq 1 ]

echo "== 재설치 (G7 · 프리셋 빼기)"
R="$(new_repo reinstall)"; install_into "$R" adhd env-secrets
echo "# 하류 수정" >>"$R/scripts/env-secrets/lib/env-secrets-signup.sh"
install_into "$R" adhd env-secrets
check "하류가 고친 파일을 재설치가 덮지 않는다" grep -q '^# 하류 수정$' "$R/scripts/env-secrets/lib/env-secrets-signup.sh"
install_into "$R" adhd
check "프리셋을 lock 에서 빼고 재설치해도 .env.keys 는 계속 무시된다" git -C "$R" check-ignore -q .env.keys

echo "== 커밋 게이트 R-env-secrets (G5)"
PC="$REPO_ROOT/assets/hooks/pre-commit.sh"
SNIP="$(awk '/^# GATE: R-env-secrets /{p=1} p{print} /^# \/R-env-secrets$/{if(p) exit}' "$PC")"
check "pre-commit.sh 에 R-env-secrets 블록이 있다" [ -n "$SNIP" ]
# hook_into <repo> — 그 블록만 도는 최소 pre-commit. 판정은 .git/gate.log, 경고는 .git/warn.log 에.
hook_into() {
  { echo '#!/usr/bin/env bash'; echo 'set -uo pipefail; WARNINGS=(); FAIL=0'
    echo 'gate_add() { printf "%s %s\n" "$1" "$2" >> .git/gate.log; }'
    printf '%s\n' "$SNIP"
    echo 'printf "%s\n" "${WARNINGS[@]}" >> .git/warn.log; exit $FAIL'; } >"$1/.git/hooks/pre-commit"
  chmod 755 "$1/.git/hooks/pre-commit"; : >"$1/.git/gate.log"; : >"$1/.git/warn.log"
}
# commit_in <repo> <vault-dir> <메시지> — 커밋하는 사람의 환경 (시험 금고·캐시). CRC 를 채운다.
commit_in() {
  echo "$RANDOM" >>"$1/note.txt"; git -C "$1" add note.txt
  (cd "$1" && env -i PATH="$PATH" HOME="$HOME" BW_BIN="$2/bw" ENV_SECRETS_VAULT_ITEM="$VAULT_ITEM" \
    ENV_SECRETS_CACHE="$CACHE" git -c user.name=t -c user.email=t@t commit -qm "$3" </dev/null >"$1/.git/commit.out" 2>&1)
  CRC=$?
}
gate_kind() { awk '$1=="R-env-secrets"{k=$2} END{print k}' "$1/.git/gate.log"; }

V="$(fake_vault)"; printf 'PORT=5181\nAPI_TOKEN=token-%s\n' "$(rand)" >"$P/.env"
run_in "$P" BW_BIN="$V/bw" import --yes
rm -f "$P/.git/hooks/pre-commit"   # 바닥 커밋은 훅 없이 — 게이트 블록은 hook_into 뒤에만 돈다
git_t "$P" add .gitignore .env.secrets; git_t "$P" commit -qm first >/dev/null 2>&1
hook_into "$P"
commit_in "$P" "$V" unchanged
check ".env 그대로 → 커밋 통과" [ "$CRC" -eq 0 ]
check ".env 그대로 → pass 기록" [ "$(gate_kind "$P")" = pass ]

printf 'LATER_KEY=later-%s\n' "$(rand)" >>"$P/.env"; hook_into "$P"
commit_in "$P" "$V" changed
check "바뀐 .env → 커밋 통과" [ "$CRC" -eq 0 ]
check "바뀐 .env → 다시 암호화한 .env.secrets 가 그 커밋에 들어간다" \
  grep -qx .env.secrets <(git -C "$P" show --name-only --format= HEAD)
check "바뀐 .env → warn 으로 사람에게 알린다" [ "$(gate_kind "$P")" = warn ]
check "평문 .env 는 커밋에 들어가지 않는다" [ -z "$(git -C "$P" ls-files .env)" ]

hook_into "$Q"; commit_in "$Q" "$V" none
check "스크립트 없는 프로젝트 → 커밋 통과" [ "$CRC" -eq 0 ]
check "스크립트 없는 프로젝트 → skipped 기록" [ "$(gate_kind "$Q")" = skipped ]

B="$(new_repo broken)"; mkdir -p "$B/scripts/env-secrets"
printf '#!/usr/bin/env bash\necho boom >&2\nexit 1\n' >"$B/scripts/env-secrets/secrets.sh"
hook_into "$B"; commit_in "$B" "$V" broken
check "secrets.sh 가 실패해도 커밋은 막지 않는다" [ "$CRC" -eq 0 ]
check "그때 warn 으로 남긴다" [ "$(gate_kind "$B")" = warn ]

# 다른 PC: 열쇠 파일이 없고 금고는 잠김. 터미널(pty)에서 커밋해도 비밀번호를 묻지 않고 끝나야 한다.
L="$(new_repo locked-tty)"; mkdir -p "$L/scripts"; cp -r "$P/scripts/env-secrets" "$L/scripts/"
cp "$P/.env.secrets" "$L/"; printf 'PORT=7001\n' >"$L/.env"; vault_lock "$V"; hook_into "$L"
echo x >"$L/note.txt"; git -C "$L" add note.txt
(cd "$L" && env -i PATH="$PATH" HOME="$HOME" TERM=dumb BW_BIN="$V/bw" ENV_SECRETS_VAULT_ITEM="$VAULT_ITEM" \
  ENV_SECRETS_CACHE="$CACHE" timeout "$HANG_CAP_SECONDS" \
  script -qec "git -c user.name=t -c user.email=t@t commit -qm tty" /dev/null </dev/null >"$L/.git/commit.out" 2>&1)
TRC=$?
check "터미널 + 잠긴 금고 → ${HANG_CAP_SECONDS}초 안에 끝난다 (입력 대기 없음)" [ "$TRC" -ne 124 ]
check "터미널 + 잠긴 금고 → 커밋 통과" [ "$(git -C "$L" log --format=%s -1 2>/dev/null)" = tty ]
check "비밀번호를 묻지 않았다" lacks "$(cat "$L/.git/commit.out")" "마스터 비밀번호"

finish
