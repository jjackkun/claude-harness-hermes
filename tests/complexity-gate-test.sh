#!/usr/bin/env bash
# R-cx 회귀 테스트 — 순환 복잡도 게이트 (라쳇 방식)
#
# 스펙: docs/superpowers/specs/2026-08-24-complexity-gate-design.md
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CX="$ROOT/assets/hooks/complexity.py"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

[[ -f "$CX" ]] || { echo "  ✗ 전제: 계산기 없음 — $CX"; echo "PASS=0 FAIL=1"; exit 1; }
ok "전제: 계산기 존재"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# 복잡도 N 짜리 함수 하나를 담은 파일을 만든다. if 를 N-1 개 쌓으면 복잡도는 N 이다.
gen() {  # $1=목표 복잡도
  echo "def f(x):"
  local i
  for ((i=1; i<$1; i++)); do echo "    if x == $i: return $i"; done
  echo "    return 0"
}

run() {  # $@ = 파일들. 위반이면 BLOCK.
  if python3 "$CX" "$@" >/dev/null 2>&1; then echo OK; else echo BLOCK; fi
}

echo "── 임계 12 ──"
gen 12 > a.py; [[ "$(run a.py)" == BLOCK ]] && ok "복잡도 12 → 차단" || nope "복잡도 12 → 차단"
gen 11 > b.py; [[ "$(run b.py)" == OK    ]] && ok "복잡도 11 → 통과" || nope "복잡도 11 → 통과"

echo "── 계산 정확도 (실측 재현) ──"
# 스펙 표의 값을 그대로 재현한다. 계산기가 바뀌면 스펙의 임계 근거도 무효가 된다.
VAL="$(python3 "$CX" --report "$ROOT/scripts/hermes-search.py" 2>/dev/null | awk '{print $1}' | sort -rn | head -1)"
[[ "$VAL" == "48" ]] && ok "hermes-search.py 최대 48 재현" || nope "hermes-search.py 최대 48 재현 (실제 $VAL)"
# plan_state.py 를 같은 방식으로 박아 뒀다가 R-acc 리팩터링으로 13 → 8 이 되면서 깨졌다.
# 살아 있는 소스의 측정값을 픽스처로 쓰면 **개선이 회귀로 신고된다.**
# 고정해야 할 것은 특정 파일의 숫자가 아니라 기준선과 실측의 관계다:
# .cxbaseline 값이 실측보다 낮으면 손대지도 않은 파일이 다음 커밋에서 막힌다.
STALE=$(python3 - "$ROOT" <<'PYEOF'
import subprocess, sys, os
root = sys.argv[1]
cx = os.path.join(root, "assets/hooks/complexity.py")
bad = []
for line in open(os.path.join(root, ".cxbaseline"), encoding="utf-8"):
    line = line.split("#", 1)[0].strip()
    if not line:
        continue
    path, _, value = line.rpartition(" ")
    target = os.path.join(root, path)
    if not os.path.isfile(target):
        continue
    out = subprocess.run([sys.executable, cx, "--report", target],
                         capture_output=True, text=True).stdout
    peak = max([int(l.split()[0]) for l in out.splitlines() if l.split()] or [0])
    if peak > int(value):
        bad.append("%s: 기준선 %s < 실측 %d" % (path, value, peak))
print("\n".join(bad))
PYEOF
)
[[ -z "$STALE" ]] && ok ".cxbaseline 이 실측보다 낮은 항목 없음" || nope ".cxbaseline 어긋남: $STALE"

echo "── 라쳇 (.cxbaseline) ──"
gen 20 > c.py
echo "c.py 20" > .cxbaseline
[[ "$(run c.py)" == OK ]] && ok "기준선 20 인 파일의 20 은 통과" || nope "기준선 20 인 파일의 20 은 통과"
gen 21 > c.py
[[ "$(run c.py)" == BLOCK ]] && ok "기준선을 넘으면 차단(후퇴 방지)" || nope "기준선을 넘으면 차단(후퇴 방지)"
gen 15 > c.py
[[ "$(run c.py)" == OK ]] && ok "기준선 아래로 개선하면 통과" || nope "기준선 아래로 개선하면 통과"
OUT="$(python3 "$CX" c.py 2>&1)"
printf '%s' "$OUT" | grep -q "15" && ok "개선 시 새 기준선을 안내" || nope "개선 시 새 기준선을 안내"
gen 12 > d.py
[[ "$(run d.py)" == BLOCK ]] && ok "기준선에 없는 파일은 임계 12" || nope "기준선에 없는 파일은 임계 12"

echo "── 기준선 자동 수정 금지 ──"
BEFORE="$(cat .cxbaseline)"
python3 "$CX" c.py >/dev/null 2>&1 || true
[[ "$(cat .cxbaseline)" == "$BEFORE" ]] && ok "훅은 기준선을 고쳐 쓰지 않는다" || nope "훅은 기준선을 고쳐 쓰지 않는다"

echo "── 기준선 부재 ──"
rm -f .cxbaseline
gen 12 > e.py; [[ "$(run e.py)" == BLOCK ]] && ok "기준선 없으면 전부 임계 12" || nope "기준선 없으면 전부 임계 12"

echo "── override ──"
gen 19 > f.py
if MAX_COMPLEXITY=20 python3 "$CX" f.py >/dev/null 2>&1; then ok "MAX_COMPLEXITY override"; else nope "MAX_COMPLEXITY override"; fi

echo "── 견고성 ──"
printf 'def broken(:\n  nope\n' > g.py
[[ "$(run g.py)" == OK ]] && ok "문법 오류는 통과(다른 게이트 관할)" || nope "문법 오류는 통과(다른 게이트 관할)"
[[ "$(run missing.py)" == OK ]] && ok "없는 파일은 통과" || nope "없는 파일은 통과"

echo "── 메시지 ──"
gen 14 > h.py
MSG="$(python3 "$CX" h.py 2>&1 || true)"
printf '%s' "$MSG" | grep -q "R-cx" && ok "메시지에 룰 ID" || nope "메시지에 룰 ID"
printf '%s' "$MSG" | grep -q "core-beliefs.md#r-cx" && ok "메시지에 근거 링크" || nope "메시지에 근거 링크"
printf '%s' "$MSG" | grep -q "f" && ok "메시지에 함수명" || nope "메시지에 함수명"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
