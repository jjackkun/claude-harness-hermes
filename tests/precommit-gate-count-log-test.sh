#!/usr/bin/env bash
# 설치기 로그의 게이트 수가 R-doc 과 같은 산출기(doc_counts.py gates)에서 나오는지 본다.
#
# 왜: lib/harness_installers.sh 가 "게이트 13종 — 차단 9 / 경고 4" 를 글자로 박아 두어,
# 실제 23종이 된 2026-11-02 까지 낡은 수를 찍었다. 또 꼬리 주석이 붙은 `# GATE:` 한 줄을
# 산출기가 조용히 빼서 문서도 22종이라 했다. 두 결함을 각각 깨뜨리는 단언을 둔다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COUNTS="$ROOT/assets/hooks/doc_counts.py"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 없음"; exit 0; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "── 산출기: 선언 줄 수와 같다 ──"
declared=$(grep -c '^# GATE:' "$ROOT/assets/hooks/pre-commit.sh")
read -r total block warn < <(python3 "$COUNTS" gates)
[[ "$total" == "$declared" ]] && ok "gates 전체($total) = '# GATE:' 줄 수($declared)" \
  || nope "gates 전체($total) ≠ '# GATE:' 줄 수($declared)"
[[ $((block + warn)) -eq $total ]] && ok "차단 $block + 경고 $warn = $total" || nope "차단+경고 ≠ 전체"

echo "── 산출기: 형식이 어긋난 선언은 조용히 빠지지 않는다 ──"
printf '# GATE: R-a block\n# GATE: R-b warn   # 꼬리 주석\n' > "$WORK/bad-hook"
python3 "$COUNTS" gates "$WORK/bad-hook" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "꼬리 주석 선언 → 종료코드 2" || nope "꼬리 주석 선언인데 종료코드 $rc"
python3 "$COUNTS" gates "$WORK/none" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "없는 파일 → 종료코드 2" || nope "없는 파일인데 종료코드 $rc"

echo "── 산출기: 파일 위치가 아니라 현재 git 최상위를 잰다 (worktree 는 .git/hooks 공유) ──"
mkdir -p "$WORK/shared/hooks"; cp "$COUNTS" "$WORK/shared/hooks/doc_counts.py"
moved=$(cd "$ROOT" && python3 "$WORK/shared/hooks/doc_counts.py" gates 2>&1)
[[ "$moved" == "$total $block $warn" ]] && ok "다른 위치의 사본도 이 저장소를 잰다($moved)" \
  || nope "다른 위치의 사본이 엉뚱한 곳을 잰다: $moved"

echo "── 설치기: 설치된 훅에서 센 수를 찍는다 ──"
log_info() { echo "INFO $*"; }
log_warn() { echo "WARN $*"; }
# shellcheck source=lib/harness_installers.sh
source "$ROOT/lib/harness_installers.sh"
_install_git_hook() { install -m 755 "$2" "$1/.git/hooks/$3"; }   # 공존 판정은 이 시험의 관심 밖
ASSETS_DIR="$ROOT/assets"
mkdir -p "$WORK/proj/.git/hooks"

out=$(HARNESS_PRE_COMMIT=1 install_harness_pre_commit "$WORK/proj" 2>&1)
want="게이트 ${total}종 — 차단 ${block} / 경고 ${warn}"
grep -qF "$want" <<<"$out" && ok "로그에 '$want'" || nope "로그에 '$want' 없음: $(grep 'pre-commit (' <<<"$out")"

# 설치된 훅에서 선언 하나를 지우면 로그 수도 줄어야 한다 — 원본이 아니라 설치본을 센다는 증거.
_install_git_hook() { install -m 755 "$2" "$1/.git/hooks/$3"; [[ "$3" == pre-commit ]] && sed -i '0,/^# GATE: R-[a-z-]* warn$/{//d}' "$1/.git/hooks/$3"; return 0; }
out=$(HARNESS_PRE_COMMIT=1 install_harness_pre_commit "$WORK/proj" 2>&1)
want="게이트 $((total - 1))종 — 차단 ${block} / 경고 $((warn - 1))"
grep -qF "$want" <<<"$out" && ok "설치본 선언 1개 삭제 → '$want'" || nope "설치본 변경이 로그에 안 보임: $(grep 'pre-commit (' <<<"$out")"

echo; echo "precommit-gate-count-log: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
