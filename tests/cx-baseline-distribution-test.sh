#!/usr/bin/env bash
# R-cx 기준선 배포 회귀 테스트
#
# 왜 이 테스트가 있는가 (2026-08-25 실측):
#   하네스는 복잡도 48짜리 `scripts/hermes-search.py` 를 11개 프로젝트에 배포한다.
#   그 상태로 R-cx 를 켜면 **사용자가 쓰지도 않은 코드 때문에** 하네스 갱신 커밋이 막힌다 —
#   자기 코드가 완전히 깨끗한 프로젝트 3개(zeroday-frontend·novel-ab·novel-bc)조차 막혔다.
#
#   면제가 아니라 **기록 이전**으로 푼다. 하네스가 자기 `.cxbaseline` 의 해당 항목을
#   프로젝트로 함께 보낸다. 값이 동결되므로 그 파일들은 계속 검사받고,
#   하네스가 나빠지면 하류에서도 잡힌다. 면제였다면 영원히 검사 밖이 된다.
#
# 실행: bash tests/cx-baseline-distribution-test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
export HOME="$TMP/fakehome"; mkdir -p "$HOME"
REGISTRY="$ROOT/.installed-projects"
cleanup() {
  # $TMP 만 지우면 안 된다 — 이 테스트는 $TMP/legacyproj 에도 설치한다.
  # 하위 경로까지 지우지 않으면 레지스트리에 죽은 경로가 쌓인다(2026-08-25 실측: 8건).
  if [[ -f "$REGISTRY" ]]; then
    grep -v "^${TMP}\(/\|$\)" "$REGISTRY" > "$REGISTRY.tmp$$" 2>/dev/null || true
    [[ -f "$REGISTRY.tmp$$" ]] && mv "$REGISTRY.tmp$$" "$REGISTRY"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

cd "$TMP"
git init -q
git config user.email "harness-test@example.com"
git config user.name "harness-test"
# hermes 프리셋이 scripts/hermes-*.py 를 배포한다. harness 만으로는 배포되지 않는다.
bash "$ROOT/project-claude.sh" . harness hermes >/dev/null 2>&1

[[ -f scripts/hermes-search.py ]] \
  || { echo "  ✗ 전제: hermes 스크립트가 배포되지 않음"; echo "PASS=0 FAIL=1"; exit 1; }
ok "전제: hermes 스크립트 배포됨"

echo "── 배포와 함께 기준선이 온다 ──"
[[ -f .cxbaseline ]] && ok "프로젝트에 .cxbaseline 생성됨" || nope "프로젝트에 .cxbaseline 생성됨"
SRC_VAL=$(awk '$1=="scripts/hermes-search.py" {print $2}' "$ROOT/.cxbaseline")
DST_VAL=$(awk '$1=="scripts/hermes-search.py" {print $2}' .cxbaseline 2>/dev/null)
[[ -n "$SRC_VAL" && "$DST_VAL" == "$SRC_VAL" ]] \
  && ok "배포 파일의 기준선 값이 하네스와 일치 ($SRC_VAL)" \
  || nope "기준선 값 불일치 (하네스=$SRC_VAL 프로젝트=$DST_VAL)"

echo "── 실제 수용 기준: 배포 파일을 커밋해도 막히지 않는다 ──"
git add -A
HOOK_OUT=$(.git/hooks/pre-commit 2>&1); HOOK_RC=$?
[[ "$HOOK_RC" -eq 0 ]] && ok "하네스 설치분 전체를 스테이징해도 차단되지 않음" \
  || nope "차단됨 (rc=$HOOK_RC) — 사용자가 쓰지 않은 코드로 커밋이 막힌다"
echo "$HOOK_OUT" | grep -q 'hermes-search.py.*순환 복잡도' \
  && nope "배포 파일에 R-cx 위반이 보고됨" || ok "배포 파일에 R-cx 위반 없음"

echo "── 검사 자체는 살아 있다 (면제가 아니다) ──"
# 기준선을 넘어서면 그 파일도 그대로 차단돼야 한다. 면제였다면 무슨 짓을 해도 통과한다.
python3 - <<'PY'
src = "scripts/hermes-search.py"
with open(src, encoding="utf-8") as handle:
    body = handle.read()
# 기준선보다 확실히 큰 복잡도의 함수를 덧붙인다.
body += "\n\ndef _probe(n):\n"
body += "".join("    if n == %d:\n        return %d\n" % (i, i) for i in range(80))
body += "    return -1\n"
with open(src, "w", encoding="utf-8") as handle:
    handle.write(body)
PY
git add scripts/hermes-search.py
.git/hooks/pre-commit >/dev/null 2>&1
[[ $? -ne 0 ]] && ok "기준선을 넘으면 배포 파일도 차단된다" \
  || nope "배포 파일이 사실상 면제 상태다 — 후퇴를 잡지 못한다"
git checkout -- scripts/hermes-search.py 2>/dev/null || true

echo "── 병합 규칙 ──"
printf 'my/own.py 30\nscripts/hermes-search.py 5\n' > .cxbaseline
bash "$ROOT/project-claude.sh" . harness hermes >/dev/null 2>&1
grep -qx 'my/own.py 30' .cxbaseline && ok "사용자 항목 보존" || nope "사용자 항목 보존"
MERGED=$(awk '$1=="scripts/hermes-search.py" {print $2}' .cxbaseline)
[[ "$MERGED" == "5" ]] && ok "이미 더 낮은 값이면 올리지 않는다 (라쳇)" \
  || nope "라쳇이 느슨해졌다 (기대=5 실제=$MERGED)"

echo "── 프로젝트 자기 코드도 동결한다 (설치 첫날 차단 방지) ──"
# 하네스 기준선은 하네스 파일만 덮는다. 프로젝트가 원래 갖고 있던 복잡한 함수는
# 아무도 동결해 주지 않아, R-cx 를 켜는 순간 그 파일을 건드리는 커밋이 전부 막힌다.
# 실측(2026-08-25): rim-office 45개 · kis-trading 36개 · upbit-ai-trading 29개.
# R-cx 스펙이 경고한 실패 모드 그대로다 —
# "그 상태로 켜면 게이트를 끄는 것이 정상 작업 흐름이 된다".
#
# 설치 **전부터** 있던 코드라야 의미가 있으므로 별도 프로젝트를 쓴다.
# 설치 후에 만들어 커밋하려면 --no-verify 가 필요한데 그것은 R5 위반이다.
LEGACY_PROJ="$TMP/legacyproj"; mkdir -p "$LEGACY_PROJ/legacy"; cd "$LEGACY_PROJ"
git init -q
git config user.email "harness-test@example.com"
git config user.name "harness-test"
python3 - <<'LEGEOF'
# 복잡도 20짜리 기존 코드. 설치 전부터 있던 것이라는 설정이다.
body = "def legacy(n):\n"
body += "".join("    if n == %d:\n        return %d\n" % (i, i) for i in range(20))
body += "    return -1\n"
open("legacy/old.py", "w", encoding="utf-8").write(body)
LEGEOF
git add legacy/old.py && git commit -q -m "설치 이전부터 있던 코드"

INSTALL_OUT=$(bash "$ROOT/project-claude.sh" . harness 2>&1)
grep -q '^legacy/old.py ' .cxbaseline 2>/dev/null \
  && ok "설치 시 프로젝트 기존 위반을 기준선에 동결" || nope "프로젝트 기존 위반이 동결되지 않음"
# if 20개 → McCabe 는 분기 20 + 1 = 21.
FROZEN=$(awk '$1=="legacy/old.py" {print $2}' .cxbaseline 2>/dev/null)
[[ "$FROZEN" == "21" ]] && ok "동결값이 실측과 일치 (21)" || nope "동결값 불일치 (실제 '$FROZEN')"

echo "── 조용히 동결하지 않는다 ──"
# 부채를 얼리는 것 자체는 맞지만 조용히는 안 된다 — 오늘 내내 고친 것이
# "게이트가 조용히 아무것도 안 하는 상태" 다.
echo "$INSTALL_OUT" | grep -q '기존 위반' \
  && ok "설치 로그가 동결 사실을 알린다" || nope "동결이 조용히 일어난다"

echo "── 동결 후에는 막지 않는다 ──"
printf '\n# touch\n' >> legacy/old.py
# 한 번에 add 하면 .cxbaseline 부재 시 pathspec 오류로 **아무것도 스테이징되지 않아**
# 이 단언이 공허하게 통과한다.
git add legacy/old.py
git add .cxbaseline 2>/dev/null || true
.git/hooks/pre-commit >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "기존 위반 파일을 커밋해도 차단되지 않음" || nope "동결했는데도 차단된다"

echo "── 그래도 후퇴는 잡는다 ──"
python3 - <<'WORSEEOF'
body = open("legacy/old.py", encoding="utf-8").read()
body += "\n\ndef worse(n):\n"
body += "".join("    if n == %d:\n        return %d\n" % (i, i) for i in range(30))
body += "    return -1\n"
open("legacy/old.py", "w", encoding="utf-8").write(body)
WORSEEOF
git add legacy/old.py
.git/hooks/pre-commit >/dev/null 2>&1
[[ $? -ne 0 ]] && ok "동결값을 넘으면 차단된다" || nope "동결이 곧 면제가 됐다"
cd "$TMP"

echo "── 배포되지 않은 경로는 넘기지 않는다 ──"
grep -q '^assets/hooks/' .cxbaseline \
  && nope "프로젝트에 없는 경로가 기준선에 들어갔다" || ok "배포 안 된 경로는 넣지 않는다"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
