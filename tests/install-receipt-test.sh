#!/usr/bin/env bash
# 설치 영수증 검증 (계획 docs/exec-plans/active/2026-09-16-install-receipt.md 목표 1~4).
#
#   - 설치가 쓴 파일만 .claude/.last-install.txt 에 오른다 (건드리지 않은 파일은 없다)
#   - cp -p 로 mtime 이 보존된 파일도 잡힌다 (ctime 기준)
#   - 영수증 자체는 git 무시
#   - 세션 시작 훅: 미커밋이면 경고, 커밋 뒤 조용
#
# 격리: 저장소를 임시 사본에 복사하고 HOME 을 바꿔 실행한다.
# 실행: bash tests/install-receipt-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0   # 설치기의 외부 도구 다운로드는 테스트에서 끈다(네트워크 0) — tests/tool-installers-test.sh 가 따로 실측

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
export HOME="$TMP/fakehome"
mkdir -p "$HOME"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

SANDBOX="$TMP/harness"
mkdir -p "$SANDBOX"
tar -c --exclude=.git -C "$REPO_ROOT" . | tar -x -C "$SANDBOX"
rm -f "$SANDBOX/.installed-projects" "$SANDBOX/.installed-projects.codex"
git -C "$SANDBOX" init -q && git -C "$SANDBOX" add -A >/dev/null 2>&1 \
  && git -C "$SANDBOX" -c user.name=t -c user.email=t@t commit -qm init >/dev/null 2>&1
git -C "$SANDBOX" remote add origin git@example.invalid:factory.git

PROJ="$TMP/proj"; mkdir -p "$PROJ/src"; git -C "$PROJ" init -q
echo keep > "$PROJ/src/keep.txt"
git -C "$PROJ" add -A && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -qm base >/dev/null
RECEIPT="$PROJ/.claude/.last-install.txt"
HOOK="$PROJ/scripts/hooks/claude-sessionstart-install-uncommitted-warn.sh"
run_hook() { CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK" 2>&1; }

echo "== 1. 영수증 내용 (목표 1) =="
bash "$SANDBOX/project-claude.sh" "$PROJ" harness hermes >"$TMP/install.log" 2>&1
assert "설치 종료 코드 0" "0" "$?"
assert "영수증 파일 존재" "1" "$([[ -f "$RECEIPT" ]] && echo 1 || echo 0)"
assert "설치 로그에 '이번 설치가 쓴 파일 N건'" "1" "$(grep -c '이번 설치가 쓴 파일 [0-9]*건' "$TMP/install.log")"
assert "스킬 SKILL.md 가 영수증에 있음" "1" "$(grep -c '^\.claude/skills/run-to-the-end/SKILL\.md$' "$RECEIPT")"
assert "훅 사본이 영수증에 있음" "1" "$(grep -c '^scripts/hooks/claude-sessionstart-install-uncommitted-warn\.sh$' "$RECEIPT")"
assert "CLAUDE.md 가 영수증에 있음" "1" "$(grep -cx 'CLAUDE\.md' "$RECEIPT")"
assert "hermes 스크립트 사본이 영수증에 있음 (사고 원인 파일)" "1" "$(grep -c '^scripts/hermes-loop\.py$' "$RECEIPT")"
assert "건드리지 않은 src/keep.txt 는 없음" "0" "$(grep -c 'src/keep.txt' "$RECEIPT")"
assert "영수증 자신은 목록에 없음" "0" "$(grep -c 'last-install' "$RECEIPT")"
assert "영수증은 git 무시 (목표 3)" "0" "$(git -C "$PROJ" check-ignore -q .claude/.last-install.txt; echo $?)"

echo ""
echo "== 2. cp -p 도 잡힌다 — ctime 기준 (목표 2) =="
# 설치기와 같은 경로로 재현: 표식을 잡고 cp -p 한 뒤 receipt_end
(
  cd "$SANDBOX" && DEV_SETTING_DIR="$SANDBOX" ASSETS_DIR="$SANDBOX/assets" \
  && source lib/logging.sh && source lib/install_receipt.sh \
  && receipt_begin && mkdir -p "$PROJ/x" && cp -p "$SANDBOX/README.md" "$PROJ/x/old-mtime.md" \
  && receipt_end "$PROJ" >/dev/null
)
assert "cp -p 한 파일이 영수증에 있음" "1" "$(grep -cx 'x/old-mtime\.md' "$RECEIPT")"
assert "표식 이전 파일(CLAUDE.md)은 이번 영수증에 없음" "0" "$(grep -cx 'CLAUDE\.md' "$RECEIPT")"
rm -rf "$PROJ/x"

echo ""
echo "== 3. 세션 시작 훅 (목표 4) =="
bash "$SANDBOX/project-claude.sh" "$PROJ" harness hermes >/dev/null 2>&1
out="$(run_hook)"
assert "미커밋 상태에서 WARN" "1" "$(grep -c '^\[install-uncommitted WARN\] 설치물 [0-9]*건' <<<"$out")"
assert "WARN 에 커밋 명령 안내" "1" "$(grep -c 'git add' <<<"$out")"
n_hook=$(grep -oE '설치물 [0-9]+건' <<<"$out" | grep -oE '[0-9]+')
n_git=$(cd "$PROJ" && git status --porcelain --untracked-files=all -- $(git ls-files -co --exclude-standard -- $(cat "$RECEIPT")) | wc -l)
assert "WARN 건수 = git status 실측" "$n_git" "$n_hook"
(cd "$PROJ" && git add $(git ls-files -co --exclude-standard -- $(cat "$RECEIPT")) && git -c user.name=t -c user.email=t@t commit -qm install >/dev/null)
assert "커밋 뒤 훅 출력 없음" "" "$(run_hook)"
assert "커밋 뒤 영수증 경로 중 미커밋 0" "0" "$(cd "$PROJ" && git status --porcelain --untracked-files=all -- $(git ls-files -co --exclude-standard -- $(cat "$RECEIPT")) | wc -l)"
rm -f "$RECEIPT"
assert "영수증 없으면 훅 조용" "" "$(run_hook)"


# ── 스캔 경합 (2026-09-21 zeroday-frontend 전파 실패) ────────────────────────
# 영수증 스캔 도중 파일이 사라지면 find 가 rc 1 을 낸다. 호출부는 `set -euo pipefail` 이라
# 그대로 두면 **설치 전체가 죽는다**. 영수증은 보고물이므로 설치를 뒤집어서는 안 된다.
echo "[경합] 스캔 중 파일이 사라져도 설치를 죽이지 않는다"
RACE="$TMP/race"; mkdir -p "$RACE/.claude/sub"
# shellcheck disable=SC1090
log_info() { echo "INFO $*"; }; log_warn() { echo "WARN $*"; }
source "$REPO_ROOT/lib/install_receipt.sh"

receipt_begin
python3 -c "
import sys
for i in range(4000): open('$RACE/sub/f%04d.tmp'%i,'w').close()
" 2>/dev/null || { mkdir -p "$RACE/sub"; python3 -c "
for i in range(4000): open('$RACE/sub/f%04d.tmp'%i,'w').close()
"; }
( for i in $(seq 0 3999); do rm -f "$RACE/sub/f$(printf %04d "$i").tmp"; done ) &
race_out=$( set -euo pipefail; receipt_end "$RACE" 2>&1 ); race_rc=$?
wait
assert "사라지는 파일이 있어도 rc 0" "0" "$race_rc"
# 경합이 실제로 걸렸을 때만 경고가 나온다(타이밍). 걸렸으면 조용히 지나가지 않는지 본다.
if grep -q "find rc=" <<<"$race_out"; then
  assert "경합이 걸렸으면 경고로 알린다" "1" "$(grep -c '영수증이 불완전할 수 있습니다' <<<"$race_out")"
else
  assert "경합 미발생 — 경고 없음이 정상" "0" "$(grep -c '영수증이 불완전할 수 있습니다' <<<"$race_out")"
fi

echo "[사이드카] SQLite -wal/-shm 은 영수증에 오르지 않는다"
SIDE="$TMP/side"; mkdir -p "$SIDE/.claude" "$SIDE/.hermes"
receipt_begin
touch "$SIDE/.hermes/state.db" "$SIDE/.hermes/state.db-wal" "$SIDE/.hermes/state.db-shm" "$SIDE/real.txt"
receipt_end "$SIDE" >/dev/null 2>&1
assert "state.db 는 오른다"   "1" "$(grep -c '^.hermes/state.db$' "$SIDE/.claude/.last-install.txt")"
assert "-wal 은 안 오른다"     "0" "$(grep -c 'db-wal' "$SIDE/.claude/.last-install.txt")"
assert "-shm 은 안 오른다"     "0" "$(grep -c 'db-shm' "$SIDE/.claude/.last-install.txt")"

echo "[빈 영수증] 쓴 파일이 없어도 죽지 않는다"
EMPTY="$TMP/empty"; mkdir -p "$EMPTY/.claude"
receipt_begin
empty_out=$( set -euo pipefail; receipt_end "$EMPTY" 2>&1 ); empty_rc=$?
assert "빈 결과에서도 rc 0" "0" "$empty_rc"
assert "영수증 0줄" "0" "$(wc -l < "$EMPTY/.claude/.last-install.txt")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
