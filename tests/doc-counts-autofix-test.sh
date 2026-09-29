#!/usr/bin/env bash
# 문서 수치 자동 갱신 시험 (계획 docs/exec-plans/completed/2026-09-29-doc-counts-autofix.md 목표 1~3).
#
#   1 수치가 낡음 → sync-doc-counts.sh --stage 가 마커 블록만 다시 쓰고 스테이징한다
#   2 대상 파일에 스테이징 안 된 변경 → 그 파일은 건드리지 않는다(차단 유지)
#   3 쓰기 실패(마커 중복) → 비영 종료(차단 유지)
#
# 저장소를 임시 위치에 복제해 돌린다 — 실제 작업 트리·색인은 건드리지 않는다. 모델 호출 0.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BEGIN='<!--===DS:COUNTS:BEGIN===-->'; END='<!--===DS:COUNTS:END===-->'

# fresh <이름> → 낡은 수치를 가진 복제본 경로. 시험 파일 하나를 추가해 테스트 개수를 어긋나게 한다.
fresh() {
  local d="$T/$1"
  git clone -q --local "$REPO_ROOT" "$d" 2>/dev/null
  cp "$REPO_ROOT/scripts/sync-doc-counts.sh" "$d/scripts/sync-doc-counts.sh"    # 작업 트리의 수정본으로 시험한다
  cp "$REPO_ROOT/assets/hooks/doc_counts.py" "$d/assets/hooks/doc_counts.py"
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/tests/zz-autofix-dummy-test.sh"
  echo "$d"
}
stale() { (cd "$1" && python3 assets/hooks/doc_counts.py check README.md presets/workflow/harness.conf >/dev/null 2>&1) && echo no || echo yes; }
outside() { python3 -c "import re,sys; print(re.sub(r'<!--===DS:COUNTS:BEGIN===-->.*?<!--===DS:COUNTS:END===-->','',sys.stdin.read(),flags=re.S))"; }
staged() { git -C "$1" diff --cached --name-only; }

echo "== 1. 낡은 수치 → 갱신하고 스테이징"
D="$(fresh a)"
assert "전제: 수치가 낡았다" yes "$(stale "$D")"
(cd "$D" && bash scripts/sync-doc-counts.sh --stage >/dev/null 2>&1); RC=$?
assert "종료 0" 0 "$RC"
assert "갱신 후 수치가 맞다" no "$(stale "$D")"
assert "README.md 가 스테이징됨" 1 "$(staged "$D" | grep -c '^README.md$')"
assert "harness.conf 가 스테이징됨" 1 "$(staged "$D" | grep -c '^presets/workflow/harness.conf$')"
assert "마커 밖 내용은 그대로" "$(git -C "$D" show HEAD:README.md | outside | md5sum)" "$(git -C "$D" show :README.md | outside | md5sum)"

echo "== 2. 스테이징 안 된 변경이 있으면 건드리지 않는다"
D="$(fresh b)"
echo "사용자가 쓰던 줄" >> "$D/README.md"
(cd "$D" && bash scripts/sync-doc-counts.sh --stage >/dev/null 2>&1); RC=$?
assert "비영 종료(README 가 아직 낡음)" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
assert "README.md 는 스테이징 안 됨" 0 "$(staged "$D" | grep -c '^README.md$')"
assert "사용자 줄이 남아 있다" 1 "$(grep -c '사용자가 쓰던 줄' "$D/README.md")"
assert "다른 깨끗한 파일(harness.conf)은 갱신·스테이징됨" 1 "$(staged "$D" | grep -c '^presets/workflow/harness.conf$')"

echo "== 3. 쓰기 실패(마커 중복) → 차단 유지"
D="$(fresh c)"
python3 - "$D/README.md" "$BEGIN" "$END" <<'PY'
import sys
p, b, e = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s + "\n" + b + "\n중복\n" + e + "\n")
PY
git -C "$D" add README.md; git -C "$D" commit -q -m "중복 마커" 2>/dev/null
(cd "$D" && bash scripts/sync-doc-counts.sh --stage >/dev/null 2>&1); RC=$?
assert "비영 종료" 1 "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
assert "README.md 는 스테이징 안 됨" 0 "$(staged "$D" | grep -c '^README.md$')"

echo "== 4. 훅 분기: 자동 갱신 시도 · 실패하면 차단 유지"
PC="$REPO_ROOT/assets/hooks/pre-commit.sh"
SNIP="$(awk '/^  DOC_OUT=/{p=1} p{print} /^  esac$/{if(p) exit}' "$PC")"
assert "훅이 --stage 를 부른다(한 곳)" 1 "$(grep -c 'sync-doc-counts.sh --stage' "$PC")"
run4() {   # run4 <스크립트> <재검사 rc> <색인> → 출력 전체
  local w="$T/w$RANDOM"; mkdir -p "$w/scripts"
  [[ "$1" == "yes" ]] && printf '#!/usr/bin/env bash\nexit 0\n' > "$w/scripts/sync-doc-counts.sh"
  (cd "$w" && env GIT_INDEX_FILE="$3" bash -c "set -euo pipefail
FAIL=0; gate_add(){ :; }; CHECK_DOC=/x; DOC_TARGETS=(README.md); DOC_RC=1; C=$w/count
python3(){ echo x >> \"\$C\"; if [[ \$(wc -l < \"\$C\") -eq 1 ]]; then echo '수치가 다릅니다'; return 1; fi; return $2; }
$SNIP
echo \"FAIL=\$FAIL\"" 2>&1)
}
O="$(run4 no 0 "")";                    assert "갱신 스크립트 없음 → 차단" 1 "$(grep -c 'FAIL=1' <<<"$O")"
O="$(run4 yes 1 "")";                   assert "갱신 뒤 재검사 실패 → 차단" 1 "$(grep -c 'FAIL=1' <<<"$O")"
O="$(run4 yes 0 "")";                   assert "갱신 뒤 재검사 통과 → 통과" 1 "$(grep -c 'FAIL=0' <<<"$O")"
assert "통과 시 자동 갱신 안내가 나온다" 1 "$(grep -c '자동 갱신하고 스테이징' <<<"$O")"
O="$(run4 yes 0 "/r/.git/next-index-123.lock")"; assert "부분 커밋(임시 색인) → 자동 갱신 안 하고 차단" 1 "$(grep -c 'FAIL=1' <<<"$O")"
O="$(run4 yes 0 "/r/.git/index")";      assert "일반 색인 경로 → 자동 갱신" 1 "$(grep -c 'FAIL=0' <<<"$O")"

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
