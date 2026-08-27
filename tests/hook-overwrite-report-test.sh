#!/usr/bin/env bash
# tests/hook-overwrite-report-test.sh
# 전파가 하류의 것을 덮을 때 **무엇을 덮었는지 말하는가** 를 검사한다.
#
# 왜 필요한가: 전파는 조건 없는 복사다. 2026-08-27 terminal-shipping 은 같은
# 훅 수정을 두 번 되살렸고, 되돌아간 것을 아무도 알려 주지 않았다.
#
# 이 테스트의 절반은 **말하지 않는 것** 을 검사한다. 매번 뜨는 경고는 읽히지 않고,
# 읽히지 않는 경고는 없는 경고다 — 조용해야 할 때 조용한지가 경고 자체만큼 중요하다.
#
# 격리: 저장소를 임시 사본에 복사해 거기서 돈다. 실 레지스트리를 건드리지 않기 위해서다
# (tests/update-all-roundtrip-test.sh 와 같은 이유).
#
# 실행: bash tests/hook-overwrite-report-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
export HOME="$TMP/fakehome"          # ~/.claude 오염 방지
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

PROJ="$TMP/proj"
mkdir -p "$PROJ"
git -C "$PROJ" init -q .
git -C "$PROJ" config user.email "harness-test@example.com"
git -C "$PROJ" config user.name "harness-test"

HOOK="claude-userpromptsubmit-reminders.sh"
INSTALLED="$PROJ/scripts/hooks/$HOOK"
MANIFEST="$PROJ/.claude/harness-hooks.lock"
PRE_COMMIT="$PROJ/.git/hooks/pre-commit"

install() { bash "$SANDBOX/project-claude.sh" "$PROJ" harness 2>&1; }

# said <출력> <문구> — 출력에 문구가 있으면 yes, 없으면 no
said() { if echo "$1" | grep -qF "$2"; then echo yes; else echo no; fi; }

echo "== 1. 신규 설치 =="
OUT=$(install)
[[ -f "$INSTALLED" ]]; assert "훅 배치됨" "0" "$?"
[[ -f "$MANIFEST" ]]; assert "매니페스트 생성됨" "0" "$?"
grep -q "  scripts/hooks/$HOOK\$" "$MANIFEST"; assert "매니페스트에 훅 기록됨" "0" "$?"
assert "신규 설치는 덮었다고 말하지 않는다" "no" "$(said "$OUT" "덮었습니다")"

echo ""
echo "== 2. 하류 무수정 재전파 → 조용 (G6) =="
OUT=$(install)
assert "덮은 것이 없으면 말하지 않는다" "no" "$(said "$OUT" "덮었습니다")"

echo ""
echo "== 3. 상류만 개정 + 하류 무수정 → 조용 (G6 핵심) =="
# cmp 로 판정하면 여기서 걸린다. 훅을 한 번 고칠 때마다 전 프로젝트가 우는 경로다.
echo "# UPSTREAM REVISION" >> "$SANDBOX/assets/hooks/$HOOK"
OUT=$(install)
grep -q "UPSTREAM REVISION" "$INSTALLED"; assert "개정본이 하류에 도달했다" "0" "$?"
assert "상류만 바뀐 것은 말하지 않는다" "no" "$(said "$OUT" "덮었습니다")"

echo ""
echo "== 4. 하류가 훅을 고침 → 그 파일만 말한다 (G4) =="
# 목록에 든 파일 수를 센다. 보고 형식은 `· scripts/hooks/<이름>` 한 줄씩이다.
# ⚠️ `[WARN]` 접두사로 세지 않는다 — 실제 출력에는 ANSI 색상 코드가 끼어 있어
#    `^\[WARN\]` 이 절대 매치되지 않는다. 그렇게 세면 항상 0 이 나오는데,
#    0 은 통과처럼 보인다. 이 저장소가 이미 한 번 당한 함정이다.
# ⚠️ 전체 출력에 said 를 쓰면 안 된다. 모든 훅이 배치될 때마다
#    `hook → scripts/hooks/<이름>` 정보 줄이 찍히므로, 고치지 않은 훅도 이름이 나온다.
#    "목록에 없다" 를 검사하려면 **목록만** 떼어내서 봐야 한다.
#    보고 목록의 줄 모양은 `<들여쓰기>· <상대경로>` 다. 그것만 떼어 본다.
listed_names() { echo "$1" | { grep -- " · " || true; }; }
listed() { listed_names "$1" | { grep -c "· scripts/hooks/" || true; }; }

HOOK2="claude-pretooluse-bash-guard.sh"
INSTALLED2="$PROJ/scripts/hooks/$HOOK2"
HOOK3="claude-posttooluse-size-warn.sh"

echo "# DOWNSTREAM FIX" >> "$INSTALLED"
OUT=$(install)
assert "덮었다고 말한다" "yes" "$(said "$OUT" "덮었습니다")"
assert "어느 파일인지 말한다" "yes" "$(said "$(listed_names "$OUT")" "$HOOK")"
assert "되돌릴 방법을 말한다" "yes" "$(said "$OUT" "git diff")"
grep -q "DOWNSTREAM FIX" "$INSTALLED"; assert "막지는 않는다 — 실제로 덮었다" "1" "$?"
assert "고친 파일 하나만 센다" "1" "$(listed "$OUT")"
assert "안 고친 훅은 목록에 없다" "no" "$(said "$(listed_names "$OUT")" "$HOOK3")"

# 계수가 1 에 고정된 게 아니라 실제로 센다는 것을 둘로 확인한다.
# (하나만 보면 "항상 1 을 돌려주는 단언" 과 구분되지 않는다.)
echo "# DOWNSTREAM FIX A" >> "$INSTALLED"
echo "# DOWNSTREAM FIX B" >> "$INSTALLED2"
OUT=$(install)
assert "둘을 고치면 둘을 센다" "2" "$(listed "$OUT")"
assert "둘째 파일도 목록에 나온다" "yes" "$(said "$(listed_names "$OUT")" "$HOOK2")"
assert "여전히 안 고친 훅은 목록에 없다" "no" "$(said "$(listed_names "$OUT")" "$HOOK3")"

echo ""
echo "== 4-bis. .git/hooks/ 부수 파일도 같은 대접을 받는다 =="
# 여기는 pre-commit 보다 더 조용하다 — .git/hooks/ 는 추적되지 않아 git diff 로도
# 안 보인다. check-secrets.py 가 되돌아가면 평소처럼 커밋되고 자격증명만 들어간다.
SIDECARS=(
  check-component-structure.mjs check-secrets.py plan_state.py
  complexity.py coverage_probe.py depcheck.py hermes_secret_values.py
)
_missing=0
for _s in "${SIDECARS[@]}"; do
  [[ -f "$PROJ/.git/hooks/$_s" ]] || { echo "      없음: $_s"; _missing=$((_missing+1)); }
done
assert "부수 파일 7개가 모두 배치됐다" "0" "$_missing"

SECRETS="$PROJ/.git/hooks/check-secrets.py"
echo "# DOWNSTREAM PATTERN TWEAK" >> "$SECRETS"
OUT=$(install)
assert "부수 파일 수정도 덮었다고 말한다" "yes" "$(said "$OUT" "덮었습니다")"
assert "어느 부수 파일인지 말한다" "yes" "$(said "$(listed_names "$OUT")" ".git/hooks/check-secrets.py")"
assert "추적되지 않는다는 사실을 말한다" "yes" "$(said "$OUT" "추적되지 않습니다")"
grep -q "DOWNSTREAM PATTERN TWEAK" "$SECRETS"; assert "막지 않는다 — 실제로 덮었다" "1" "$?"

OUT=$(install)
assert "덮은 뒤에는 목록이 비어 있다" "no" "$(said "$(listed_names "$OUT")" ".git/hooks/check-secrets.py")"
assert "부수 파일도 상류 무변경이면 조용하다" "no" "$(said "$OUT" "덮었습니다")"

echo ""
echo "== 4-ter. 은퇴한 기록은 매니페스트에서 정리된다 =="
printf 'deadbeef  scripts/hooks/gone-forever.sh
' >> "$MANIFEST"
grep -q "gone-forever" "$MANIFEST"; assert "정리 전에는 기록이 있다" "0" "$?"
OUT=$(install)
grep -q "gone-forever" "$MANIFEST"; assert "파일 없는 기록은 버려진다" "1" "$?"
grep -q "  scripts/hooks/$HOOK\$" "$MANIFEST"; assert "살아 있는 기록은 남는다" "0" "$?"

echo ""
echo "== 4-quater. CRLF 매니페스트에서도 판정이 살아 있다 =="
# \r 이 붙어 비교가 빗나가면 "기록 없음" 으로 떨어져 조용히 판정을 포기한다.
# 이 저장소는 CRLF .gitignore 로 이미 한 번 당했다.
sed -i 's/$/\r/' "$MANIFEST"
echo "# EDIT UNDER CRLF" >> "$INSTALLED"
OUT=$(install)
assert "CRLF 기록으로도 하류 수정을 잡는다" "yes" "$(said "$OUT" "덮었습니다")"

echo ""
echo "== 5. 덮은 뒤 다시 전파 → 조용 (G6) =="
OUT=$(install)
assert "덮은 뒤에는 같은 파일을 또 말하지 않는다" "no" "$(said "$OUT" "덮었습니다")"

echo ""
echo "== 6. pre-commit 에 단계를 얹음 → 갈아쳤다고 말한다 (G5) =="
printf '\n# EXTRA STEP — secret scan\n' >> "$PRE_COMMIT"
OUT=$(install)
assert "갈아쳤다고 말한다" "yes" "$(said "$OUT" "갈아쳤습니다")"
assert "다시 얹으라고 말한다" "yes" "$(said "$OUT" "다시 얹으십시오")"
grep -q "EXTRA STEP" "$PRE_COMMIT"; assert "얹은 단계는 실제로 사라졌다" "1" "$?"

echo ""
echo "== 7. pre-commit 무수정 재전파 → 조용 (G6) =="
OUT=$(install)
assert "얹은 것이 없으면 말하지 않는다" "no" "$(said "$OUT" "갈아쳤습니다")"

echo ""
echo "== 8. 첫 도입(기록 없음) → 조용히 기록만 한다 =="
# 의도한 손실이다. "모르면 경고" 를 택하면 첫 전파에서 전 프로젝트가 울어
# 경고가 통째로 죽는다. 손실이 의도라는 것을 여기서 못 박는다.
rm -f "$MANIFEST"
echo "# EDIT WITHOUT RECORD" >> "$INSTALLED"
OUT=$(install)
assert "기록이 없으면 판정하지 않는다" "no" "$(said "$OUT" "덮었습니다")"
grep -q "  scripts/hooks/$HOOK\$" "$MANIFEST"; assert "대신 기록을 남긴다" "0" "$?"

echo ""
echo "== 9. 기록이 생긴 뒤에는 다시 잡는다 =="
echo "# EDIT AFTER RECORD" >> "$INSTALLED"
OUT=$(install)
assert "기록이 있으면 하류 수정을 잡는다" "yes" "$(said "$OUT" "덮었습니다")"

echo ""
echo "== 결과 =="
echo "  통과: $PASS / 실패: $FAIL"
[[ $FAIL -eq 0 ]]
