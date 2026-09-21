#!/usr/bin/env bash
# 세션 고정 비용 표 (계획 2026-09-21-context-budget).
#
#   (a) 두 표 — 항상 로드 / 필요할 때. 항목·바이트·추정 토큰
#   (b) 설명과 본문을 가른다 — 에이전트 본문 5,000 B·설명 100 B 면 고정 비용엔 설명만
#   (c) --json 으로 기계가 읽는다
#   (d) 실 저장소(공장)에서 돈다
#
# 실행: bash tests/context-budget-test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUDGET="$ROOT/assets/hooks/context_budget.py"
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

P="$T/proj"; mkdir -p "$P/.claude/agents" "$P/.claude/skills/demo" "$P/.claude/rules"
printf '# 프로젝트\n\n한 줄.\n' > "$P/CLAUDE.md"                                  # 34 B 남짓
printf '# 룰\n\n지킬 것.\n' > "$P/.claude/rules/basic.md"
# 에이전트: 설명 100 B 안팎 + 본문 5,000 B
python3 - "$P/.claude/agents/big.md" <<'PY'
import sys
desc = "description: " + ("가" * 30)          # 설명(짧다)
body = "본문 " + ("길다 " * 1000)             # 본문(길다)
open(sys.argv[1], "w", encoding="utf-8").write("---\nname: big\n%s\n---\n\n%s\n" % (desc, body))
PY
python3 - "$P/.claude/skills/demo/SKILL.md" <<'PY'
import sys
open(sys.argv[1], "w", encoding="utf-8").write("---\nname: demo\ndescription: 짧은 설명\n---\n\n" + ("본문 " * 500))
PY

echo "[a] 두 표"
OUT=$(HOME="$T" python3 "$BUDGET" --root "$P" 2>&1)
assert "항상 로드 표" "1" "$(grep -c '항상 로드' <<<"$OUT")"
assert "필요할 때 표" "1" "$(grep -c '필요할 때' <<<"$OUT")"
assert "추정 토큰 칸" "yes" "$([[ "$(grep -c '토큰' <<<"$OUT")" -ge 1 ]] && echo yes || echo no)"

echo "[b] 설명과 본문을 가른다"
FIXED=$(HOME="$T" python3 "$BUDGET" --root "$P" --json 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin)['always_total'])")
AGENT_BODY=$(wc -c < "$P/.claude/agents/big.md")
# 전역 룰을 뺀 이 프로젝트만의 고정 비용은 에이전트 본문보다 작아야 한다(설명만 세므로)
assert "고정 비용이 에이전트 본문보다 작다" "yes" "$([[ "$FIXED" -lt "$AGENT_BODY" ]] && echo yes || echo "no(고정 $FIXED ≥ 본문 $AGENT_BODY)")"
assert "본문은 '필요할 때' 쪽에 잡힌다" "yes" "$(HOME="$T" python3 "$BUDGET" --root "$P" --json 2>/dev/null | python3 -c "
import json,sys; d=json.load(sys.stdin); print('yes' if d['on_demand_total'] >= $AGENT_BODY else 'no')")"

echo "[c] --json"
assert "JSON 키" "always,always_total,on_demand,on_demand_total,root" "$(HOME="$T" python3 "$BUDGET" --root "$P" --json 2>/dev/null | python3 -c "import json,sys;print(','.join(sorted(json.load(sys.stdin))))")"
assert "항목마다 bytes·tokens" "yes" "$(HOME="$T" python3 "$BUDGET" --root "$P" --json 2>/dev/null | python3 -c "
import json,sys; d=json.load(sys.stdin)
print('yes' if all({'bytes','tokens'} <= set(v) for v in d['always'].values()) else 'no')")"

echo "[d] 실 저장소"
assert "공장에서 rc 0" "0" "$(python3 "$BUDGET" --root "$ROOT" >/dev/null 2>&1; echo $?)"
assert "고정 비용이 0 이 아니다" "yes" "$(python3 "$BUDGET" --root "$ROOT" --json 2>/dev/null | python3 -c "import json,sys;print('yes' if json.load(sys.stdin)['always_total']>1000 else 'no')")"
assert "모델 호출 없음(claude 문자열 호출 0)" "0" "$(grep -cE 'subprocess|"claude"' "$BUDGET")"

echo; echo "context-budget: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
