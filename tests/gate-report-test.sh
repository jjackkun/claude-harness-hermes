#!/usr/bin/env bash
# gate_report.py 단위 테스트 — 발화율 집계 규칙의 유일한 검증 수단.
#
# 실행: bash tests/gate-report-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$REPO_ROOT/assets/hooks/gate_report.py"
TMP=$(mktemp -d)
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

P="$TMP/proj"; mkdir -p "$P/.harness"
EV="$P/.harness/gate-events.jsonl"

# 시나리오: R-iface 는 기회 10 중 warn 1 + block 1 = 발화율 20%, waived 1 은 분모에 포함.
#           R-cx 는 pass 2 + skipped 3 — 분모는 2 이고 skipped 는 빠진다.
python3 - "$EV" <<'PY'
import json, sys, time
now = int(time.time())
recs = []
def add(rule, verdict, n, ts=None):
    for _ in range(n):
        recs.append({"ts": ts or now, "rule": rule, "verdict": verdict,
                     "stage": "pretooluse", "path": None, "detail": None})
add("R-iface", "pass", 7); add("R-iface", "waived", 1)
add("R-iface", "warn", 1); add("R-iface", "block", 1)
add("R-cx", "pass", 2); add("R-cx", "skipped", 3)
add("R-old", "block", 5, ts=now - 40 * 86400)
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for r in recs:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY

OUT=$(cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$MOD" 2>&1)

echo "== 발화율 계산 =="
assert "R-iface 기회 10 (waived 포함)" "1" "$(grep -cE '^R-iface +10 ' <<< "$OUT")"
assert "R-iface 발화율 20.0%" "1" "$(grep -c 'R-iface.*20\.0%' <<< "$OUT")"
assert "R-cx 기회 2 (skipped 제외)" "1" "$(grep -cE '^R-cx +2 ' <<< "$OUT")"
assert "R-cx 발화율 0.0%" "1" "$(grep -c 'R-cx.*0\.0%' <<< "$OUT")"

echo "== 죽은 게이트 경고 =="
assert "skipped 가 있으면 경고를 낸다" "1" "$(grep -c '건너뛴 게이트: R-cx' <<< "$OUT")"

echo "== 기간 필터 =="
OUT7=$(cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$MOD" --days 7 2>&1)
assert "40일 전 레코드는 --days 7 에서 빠진다" "0" "$(grep -c '^R-old' <<< "$OUT7")"
assert "최근 레코드는 남는다" "1" "$(grep -cE '^R-iface ' <<< "$OUT7")"

echo "== 룰 필터 =="
OUTR=$(cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$MOD" --rule R-cx 2>&1)
assert "--rule 로 한 룰만" "0" "$(grep -cE '^R-iface ' <<< "$OUTR")"

echo "== 스키마 주인 =="
# 필드명을 하드코딩하면 gate_event.py 가 바뀔 때 조용히 0 을 세게 된다.
assert "gate_event 의 FIELDS/VERDICTS 를 import 해서 쓴다" "1" \
  "$(grep -c '_load_event_module\|ev.VERDICTS' "$MOD" | head -1 >/dev/null; grep -qc 'ev.VERDICTS' "$MOD" && echo 1 || echo 0)"

echo "== 깨진 줄 =="
printf 'not json\n' >> "$EV"
OUTB=$(cd "$P" && CLAUDE_PROJECT_DIR="$P" python3 "$MOD" 2>&1)
assert "깨진 줄을 조용히 버리지 않고 보고한다" "1" "$(grep -c '파싱 실패한 줄 1개' <<< "$OUTB")"

echo "== 이벤트 없음 =="
Q="$TMP/empty"; mkdir -p "$Q"
rc=0; (cd "$Q" && CLAUDE_PROJECT_DIR="$Q" python3 "$MOD" >/dev/null 2>&1) || rc=$?
assert "이벤트 파일이 없으면 exit 2 (통과로 위장하지 않음)" "2" "$rc"

echo
echo "통과 $PASS / 실패 $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
