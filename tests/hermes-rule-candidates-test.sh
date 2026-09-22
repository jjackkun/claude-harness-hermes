#!/usr/bin/env bash
# 승격 후보 모으기 — 완료 계획서 회고의 "다음 룰 후보" → 반복·상태.
# 근거: docs/exec-plans/completed/2026-09-22-rule-candidates-dashboard-plan.md 목표 1
#
# 실행: bash tests/hermes-rule-candidates-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

C="$TMP/completed"; mkdir -p "$C"
cat > "$C/2026-09-20-a.md" <<'EOF'
## 8. 회고
- 잘된 것: 없음
- 다음 룰 후보: 설치기 판정 함수를 바꿀 때는 옛 공장판 대조 사례를 포함한다 — 1건.
EOF
cat > "$C/2026-09-21-b.md" <<'EOF'
## 8. 회고
- 다음 룰 후보:
  - "부재를 단언하는 시험은 우연히 0 이 되는 길이 없는지 본다" — 사례 2건. 한 번 더 나오면 승격.
  - "구독 CLI 첫 실측에서 소요 시간을 잰다" — 사례 1건, 승격 보류.
- 남은 일: 없음
EOF
cat > "$C/2026-09-22-c.md" <<'EOF'
## 8. 회고
- 다음 룰 후보:
  - "부재를 단언하는 시험은 우연히 0 이 되는 길이 없는지 본다" — 3번째 사례. 승격 조건 충족.
EOF
cat > "$C/2026-09-18-d.md" <<'EOF'
## 8. 회고
- 다음 룰 후보: 없음. 기준선 0.
EOF
cat > "$C/2026-09-10-e.md" <<'EOF'
## 8. 회고
- 다음 룰 후보: 파일 400줄 한도 — R-size 로 승격됨.
EOF
cat > "$C/2026-09-11-f.md" <<'EOF'
## 8. 회고
- 다음 룰 후보: 매 세션 대시보드 알림 — 폐기(소음).
EOF

out=$(python3 - "$REPO_ROOT" "$C" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rc", sys.argv[1] + "/scripts/hermes_rule_candidates.py")
rc = importlib.util.module_from_spec(spec); spec.loader.exec_module(rc)
items = rc.collect(sys.argv[2])
print("n:", len(items))
top = items[0]
print("top:", top["status"], top["count"], len(top["sources"]), top["latest"])
by = {i["text"][:6]: i for i in items}
print("cli:", by["구독 CLI"]["status"], by["구독 CLI"]["count"])
print("installer:", by["설치기 판정"]["status"], by["설치기 판정"]["count"])
print("size:", by["파일 400"]["status"])
print("noise:", by["매 세션 대"]["status"])
print("none_excluded:", all("없음" not in i["text"][:3] for i in items))
print("order:", ",".join(i["status"] for i in items))
print("missing_dir:", rc.collect(sys.argv[2] + "/nope"))
PY
)
echo "$out" | sed 's/^/    /'
assert "후보 5개 (없음 제외 · 같은 교훈은 하나로)"       "n: 5"                         "$(echo "$out" | sed -n 1p)"
assert "두 번 나온 교훈 → 검토 필요 · 반복 3 · 출처 2" "top: review 3 2 2026-09-22"     "$(echo "$out" | sed -n 2p)"
assert "보류라고 적은 1건 → 보류"                        "cli: pending 1"               "$(echo "$out" | sed -n 3p)"
assert "한 줄 칸도 읽는다"                               "installer: pending 1"         "$(echo "$out" | sed -n 4p)"
assert "'로 승격됨' → 승격됨"                            "size: promoted"               "$(echo "$out" | sed -n 5p)"
assert "'폐기' → 폐기"                                   "noise: dropped"               "$(echo "$out" | sed -n 6p)"
assert "'없음' 칸은 후보가 아니다"                       "none_excluded: True"          "$(echo "$out" | sed -n 7p)"
assert "검토 필요가 맨 앞, 승격됨·폐기는 맨 뒤"          "order: review,pending,pending,promoted,dropped" "$(echo "$out" | sed -n 8p)"
assert "완료 폴더가 없으면 빈 목록"                      "missing_dir: []"              "$(echo "$out" | sed -n 9p)"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
