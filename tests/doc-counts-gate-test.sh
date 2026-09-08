#!/usr/bin/env bash
# R-doc 게이트 시험 — 문서 수치가 소스와 어긋나면 *실제로* 차단하는지 본다.
#
# 근거: docs/exec-plans/active/2026-09-08-doc-counts-gate.md
#
# 통과만 확인하는 시험은 게이트가 조용히 꺼진 것을 못 잡는다 — harness-hooks-smoke.sh
# 가 실제로 그 상태였다. 그래서 여기서는 가짜 위반을 만들어 차단을 확인하고,
# 되돌려 통과까지 확인한다.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COUNTS="$REPO_ROOT/assets/hooks/doc_counts.py"
PASS=0
FAIL=0

ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 없음"; exit 0; }
[[ -f "$COUNTS" ]] || { echo "FAIL: doc_counts.py 없음"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BODY=$(cd "$REPO_ROOT" && python3 "$COUNTS" render)
[[ -n "$BODY" ]] && ok "render 가 본문을 낸다" || bad "render 가 비었다"

# render 는 항상 종료코드 0 (관측·산출이 커밋을 죽이면 안 된다)
(cd "$REPO_ROOT" && python3 "$COUNTS" render >/dev/null 2>&1)
[[ $? -eq 0 ]] && ok "render 종료코드 0" || bad "render 종료코드가 0 이 아니다"

# 1) 올바른 블록 → 통과
GOOD="$TMP/good.md"
{ echo "머리말"; echo '<!--===DS:COUNTS:BEGIN===-->'; echo "$BODY"; echo '<!--===DS:COUNTS:END===-->'; echo "꼬리말"; } > "$GOOD"
if (cd "$REPO_ROOT" && python3 "$COUNTS" check "$GOOD" >/dev/null 2>&1); then
  ok "소스와 같은 블록 → 통과"
else
  bad "소스와 같은 블록인데 막혔다"
fi

# 2) 수치를 틀리게 → 차단 (핵심)
BADF="$TMP/bad.md"
sed 's/훅 \*\*[0-9]*종\*\*/훅 **8종**/' "$GOOD" > "$BADF"
if cmp -s "$GOOD" "$BADF"; then
  bad "가짜 위반을 만들지 못했다 — 시험이 아무것도 검증하지 않는다"
else
  OUT=$(cd "$REPO_ROOT" && python3 "$COUNTS" check "$BADF" 2>&1)
  if [[ $? -ne 0 ]]; then
    ok "수치가 틀리면 차단한다"
    echo "$OUT" | grep -q '실측' && ok "출력에 실측값이 들어간다" || bad "무엇이 맞는 값인지 안 알려준다"
  else
    bad "수치가 틀린데 통과했다 — 게이트가 꺼져 있다"
  fi
fi

# 3) 마커가 아예 없으면 그 사실을 말한다 (조용히 통과 금지)
NOM="$TMP/nomarker.md"
echo "마커 없는 문서" > "$NOM"
if (cd "$REPO_ROOT" && python3 "$COUNTS" check "$NOM" >/dev/null 2>&1); then
  bad "마커가 없는데 조용히 통과했다"
else
  ok "마커 부재를 위반으로 본다"
fi

# 4) 닫는 마커 유실 → 위반 (사용자 내용 보호와 같은 부류의 사고)
HALF="$TMP/half.md"
{ echo '<!--===DS:COUNTS:BEGIN===-->'; echo "$BODY"; } > "$HALF"
if (cd "$REPO_ROOT" && python3 "$COUNTS" check "$HALF" >/dev/null 2>&1); then
  bad "닫는 마커가 없는데 통과했다"
else
  ok "닫는 마커 유실을 잡는다"
fi

# 5) 실제 저장소 문서가 지금 최신인가
if (cd "$REPO_ROOT" && python3 "$COUNTS" check README.md presets/workflow/harness.conf >/dev/null 2>&1); then
  ok "저장소 문서가 소스와 일치한다"
else
  bad "저장소 문서가 낡았다 — bash scripts/sync-doc-counts.sh 실행 필요"
fi

# 6) pre-commit 에 R-doc 단계가 살아 있는가 (배선 유실 감지)
PC="$REPO_ROOT/assets/hooks/pre-commit.sh"
grep -q '^# GATE: R-doc block' "$PC" && ok "pre-commit 에 R-doc 선언이 있다" || bad "R-doc 선언이 사라졌다"
grep -q 'doc_counts.py' "$PC" && ok "pre-commit 이 doc_counts.py 를 부른다" || bad "pre-commit 배선이 끊겼다"

# 7) 배포처 오발화 방지 — 마커 없는 저장소에서는 조용해야 한다
grep -q "grep -qF '<!--===DS:COUNTS:BEGIN===-->' \"\$f\"" "$PC" \
  && ok "대상 선정이 마커 기준이다 (배포처 오발화 방지)" \
  || bad "파일 존재만으로 대상을 고르면 배포처 12곳에서 매 커밋 발화한다"

# ── 2026-09-08 코드 검토 지적 회귀 고정 ────────────────────────────────────

# [HIGH] 산출 근거가 없는 곳에서 0 을 사실로 보고하지 않는다 (배포처 .git/hooks 시나리오)
ISO="$TMP/iso/.git/hooks"
mkdir -p "$ISO"
cp "$COUNTS" "$ISO/doc_counts.py"
OUT=$(cd "$TMP/iso" && python3 .git/hooks/doc_counts.py render 2>&1)
RC=$?
if [[ $RC -eq 2 ]]; then
  ok "근거 없는 위치에서 종료코드 2 (판정 불가)"
else
  bad "근거가 없는데 종료코드 $RC — 조용한 0 보고 위험"
fi
echo "$OUT" | grep -q '0종' && bad "0 을 사실처럼 출력한다" || ok "0 을 사실로 보고하지 않는다"

# [MEDIUM] 한 줄 배열이 뒤 라인을 삼키지 않는다
PYOUT=$(cd "$REPO_ROOT" && python3 - <<'PYEOF' 2>&1
import sys; sys.path.insert(0, "assets/hooks")
import doc_counts as d
try:
    r = d._bash_array("SKILLS+=(one two three)\nfoo\nbar\n)\nbaz", "SKILLS")
    print("RESULT", r)
except d.DocCountsUnavailable as e:
    print("RAISED")
PYEOF
)
if echo "$PYOUT" | grep -q "RESULT \['one', 'two', 'three'\]"; then
  ok "한 줄 배열을 올바로 읽는다"
elif echo "$PYOUT" | grep -q "RAISED"; then
  ok "한 줄 배열을 명시적 실패로 처리한다"
else
  bad "한 줄 배열이 뒤 라인을 삼킨다: $PYOUT"
fi

# [MEDIUM] 배열이 비면 0 을 사실로 보고하지 않는다
PYOUT=$(cd "$REPO_ROOT" && python3 - <<'PYEOF' 2>&1
import sys; sys.path.insert(0, "assets/hooks")
import doc_counts as d
try:
    d._bash_array("SKILLS+=(\n)\n", "SKILLS"); print("SILENT")
except d.DocCountsUnavailable: print("RAISED")
PYEOF
)
echo "$PYOUT" | grep -q RAISED && ok "빈 배열을 실패로 본다" || bad "빈 배열을 조용히 0 으로 센다"

# [LOW] 마커가 중복된 문서는 갱신을 거부한다
DUP="$TMP/dup.md"
{ echo '<!--===DS:COUNTS:BEGIN===-->'; echo "$BODY"; echo '<!--===DS:COUNTS:END===-->';
  echo '<!--===DS:COUNTS:BEGIN===-->'; echo "$BODY"; echo '<!--===DS:COUNTS:END===-->'; } > "$DUP"
if (cd "$REPO_ROOT" && bash scripts/sync-doc-counts.sh "$DUP" >/dev/null 2>&1); then
  bad "마커가 2쌍인데 갱신을 강행했다 (나머지가 조용히 낡는다)"
else
  ok "마커 중복 시 갱신을 거부한다"
fi

# [HIGH] pre-commit 이 판정 불가(2)와 불일치(1)를 구분한다
grep -q 'DOC_RC' "$PC" && ok "pre-commit 이 종료코드를 구분한다" \
  || bad "판정 불가와 문서 오류를 같은 분기로 처리한다"

echo ""
echo "  결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
