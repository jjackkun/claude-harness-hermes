#!/usr/bin/env bash
# 게이트 선언·계장 일치 검사 — 선언만 있고 기록을 남기지 않는 게이트를 막는다.
#
# 이웃 시험과의 분담:
#   gate-instrumentation-test.sh          — 런타임 훅이 이벤트를 남기는가 (동작)
#   gate-precommit-instrumentation-test.sh — pre-commit 게이트가 이벤트를 남기는가 (동작)
#   이 파일                                 — 선언 집합과 gate_add 집합이 일치하는가 (정적)
#
# 앞의 둘은 "붙인 계장이 작동하는가" 를 보고, 이 파일은 "계장을 붙이는 것을 잊지
# 않았는가" 를 본다. 잊은 것은 동작 시험으로 잡을 수 없다 — 없는 것은 실행되지 않는다.
#
# 근거: docs/exec-plans/active/2026-09-08-instrument-remaining-gates.md
#       docs/audits/2026-09-08-plan-gate-firing.md
#
# 왜 이 시험이 있는가: 2026-09-08 감사에서 게이트 16종 중 **8종이 발화 기록을 남기지
# 않고 있었다.** 화면에는 경고·차단을 찍으면서 gate_report.py 에는 행조차 나오지 않았다.
# 발화율로 룰의 승격·강등을 판단하겠다는 전제가 그 8종에 대해 성립하지 않았다.
#
# **핵심은 8종이 빠졌다는 사실이 아니라 빠진 것을 아무도 몰랐다는 것이다.**
# 사람이 기억해서 지키는 규율은 반드시 다시 깨진다. 그래서 검사로 만든다.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PC="$REPO_ROOT/assets/hooks/pre-commit.sh"
PASS=0
FAIL=0

ok()  { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

[[ -f "$PC" ]] || { echo "FAIL: pre-commit.sh 없음: $PC"; exit 1; }

declared() { grep -oE '^# GATE: (R-[a-z-]+)' "$1" | awk '{print $3}' | sort -u; }
called()   { grep -oE 'gate_add (R-[a-z-]+)' "$1" | awk '{print $2}' | sort -u; }

# ── 1. 선언은 있는데 기록을 안 남기는 게이트가 없는가 (핵심) ──────────────
MISSING=$(comm -23 <(declared "$PC") <(called "$PC") | tr '\n' ' ')
if [[ -z "${MISSING// /}" ]]; then
  ok "모든 선언 게이트가 gate_add 를 부른다 ($(declared "$PC" | wc -l)종)"
else
  bad "미계장 게이트: $MISSING — gate_report.py 에 행이 나오지 않는다"
fi

# ── 1b. 각 게이트가 "발화" 와 "통과" 를 모두 기록하는가 ──────────────────
# 1번은 룰 **이름** 집합만 본다. 그래서 한 룰의 여러 분기 중 하나(특히 pass)가
# 사라져도 잡지 못한다 — 2026-09-08 에 이 시험을 만들면서 실제로 확인한 구멍이다.
#
# 통과를 기록하지 않으면 분모가 없어 "안 걸렸다" 와 "판정하지 않았다" 가 구분되지
# 않는다. 2026-09-08 감사가 정확히 그 이유로 답을 못 냈다. 그래서 선언된 판정
# 종류(block|warn)와 pass 가 **둘 다** 있어야 한다.
#
# 한계(명시): 이것도 정적 문자열 검사다. 분기가 실제로 도달 가능한지는 보지 못한다.
# 제어 흐름 검증은 bash 로 감당할 수 없어 여기서는 다루지 않는다.
while read -r g kind; do
  [[ -n "$g" ]] || continue
  have_kind=$(grep -cE "gate_add $g $kind " "$PC")
  have_pass=$(grep -cE "gate_add $g pass " "$PC")
  if [[ "$have_kind" -gt 0 && "$have_pass" -gt 0 ]]; then
    ok "$g 이 $kind 와 pass 를 모두 기록한다"
  elif [[ "$have_kind" -eq 0 ]]; then
    bad "$g 이 선언된 판정($kind)을 기록하지 않는다"
  else
    bad "$g 이 pass 를 기록하지 않는다 — 분모가 없어 발화율을 낼 수 없다"
  fi
done < <(grep -oE '^# GATE: R-[a-z-]+ (block|warn)' "$PC" | awk '{print $3, $4}' | sort -u)

# ── 1c. 사용자에게 메시지를 찍는 **모든 지점**에 계장이 있는가 ───────────
# 1·1b 는 룰 **이름**으로 본다. 그래서 한 룰이 서로 다른 코드 경로 둘에서 발화할 때
# 한쪽만 계장돼 있어도 통과한다. 2026-09-08 검토가 R-acc 에서 그 구멍을 찾았다 —
# §7-bis(§2 검증 명령)는 계장했는데 §9-bis(완료 시 미완 목표)는 빠져 있었고,
# 이름 기준 검사는 R-acc 가 이미 warn+pass 를 가졌으므로 아무 말도 하지 않았다.
#
# 그래서 `WARNINGS+=` / `VIOLATIONS+=` 가 나오는 자리마다 그 블록의 룰 태그를 찾아,
# 근처에 같은 룰의 gate_add 가 있는지 본다. **발화 지점 단위**로 세는 검사다.
if command -v python3 >/dev/null 2>&1; then
  UNINSTR=$(python3 - "$PC" <<'PYEOF'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
bad = []
for i, l in enumerate(lines):
    if "WARNINGS+=(" not in l and "VIOLATIONS+=(" not in l:
        continue
    tag = None
    for j in range(i, min(i + 14, len(lines))):
        m = re.search(r"\[(R-[a-z0-9-]+)\]", lines[j])
        if m:
            tag = m.group(1)
            break
    if tag is None:          # 룰 태그가 없는 안내 메시지는 게이트 발화가 아니다
        continue
    lo, hi = max(0, i - 30), min(len(lines), i + 30)
    if not any(f"gate_add {tag} " in lines[k] for k in range(lo, hi)):
        bad.append(f"{i+1}행:{tag}")
print(" ".join(bad))
PYEOF
)
  if [[ -z "${UNINSTR// /}" ]]; then
    ok "메시지를 찍는 모든 지점에 같은 룰의 gate_add 가 있다"
  else
    bad "계장 없는 발화 지점: $UNINSTR"
  fi
else
  echo "  - python3 없음 — 발화 지점 검사 건너뜀"
fi

# ── 2. 선언 없이 기록만 남기는 게이트가 없는가 (반대 방향) ────────────────
# 선언이 없으면 차단/경고 분류가 없어 gate_report 가 성질을 말하지 못한다.
EXTRA=$(comm -13 <(declared "$PC") <(called "$PC") | tr '\n' ' ')
if [[ -z "${EXTRA// /}" ]]; then
  ok "선언 없이 기록만 남기는 게이트가 없다"
else
  bad "선언 누락: $EXTRA — '# GATE: <룰> block|warn' 을 추가하십시오"
fi

# ── 3. 도구 부재를 통과로 세지 않는가 ────────────────────────────────────
# 도구가 없어서 안 걸린 것을 pass 로 세면 발화율이 거짓으로 낮아진다.
# 외부 도구에 의존하는 게이트는 skipped 분기를 가져야 한다.
for g in R-fmt R-lint R-test R-struct R-cov R-doc R-cx R-dep R-secret; do
  if grep -qE "gate_add $g skipped" "$PC"; then
    ok "$g 에 skipped 분기가 있다 (도구 부재를 통과로 세지 않음)"
  else
    bad "$g 에 skipped 분기가 없다 — 도구가 없으면 조용히 통과할 위험"
  fi
done

# ── 4. 계장이 실제로 작동하는가 (선언 파싱만 보는 시험이 되지 않도록) ─────
# 위 1~3 은 소스 문자열만 본다. 실제로 이벤트가 쓰이는지는 별개다.
GE="$REPO_ROOT/assets/hooks/gate_event.py"
if [[ -f "$GE" ]] && command -v python3 >/dev/null 2>&1; then
  T=$(mktemp -d)
  ( cd "$REPO_ROOT" && CLAUDE_PROJECT_DIR="$T" bash -c "
      source assets/hooks/gate_emit.sh
      gate_emit R-instrumentation-selftest pass precommit '' '자체 검사'" ) >/dev/null 2>&1
  if grep -q 'R-instrumentation-selftest' "$T/.harness/gate-events.jsonl" 2>/dev/null; then
    ok "gate_emit 이 실제로 이벤트를 기록한다"
  else
    bad "gate_emit 이 이벤트를 남기지 않는다 — 계장이 배선만 있고 죽어 있다"
  fi
  rm -rf "$T"
else
  echo "  - gate_event.py 또는 python3 없음 — 기록 확인 건너뜀"
fi

# ── 5. 배포 사본이 원본과 같은가 ─────────────────────────────────────────
COPY="$REPO_ROOT/scripts/hooks/pre-commit.sh"
if [[ -f "$COPY" ]]; then
  cmp -s "$COPY" "$PC" && ok "scripts/hooks 사본이 원본과 같다" \
                       || bad "assets/hooks 와 scripts/hooks 의 pre-commit.sh 가 다르다"
fi

echo ""
echo "  결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
