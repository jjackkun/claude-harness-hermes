#!/usr/bin/env bash
# R-declare 회귀 테스트 — 새 코드 파일은 계획서 §4 에 먼저 선언돼 있어야 한다
#
# 왜 이 테스트가 있는가 (2026-08-25):
#   템플릿 §4 는 "신규 파일 목록 (파일별 책임 1줄 필수) ← 비워두지 말 것" 을 요구하고
#   "위 목록을 먼저 못 쓰면 아직 설계가 덜 됐다는 뜻. 구현 들어가지 말 것" 이라고까지 적는다.
#   그런데 이를 확인하는 장치가 하나도 없었다 — 템플릿의 부탁으로만 남아 있었다.
#
#   강제 지점은 커밋이 아니라 **파일을 만들려는 순간**이다. 커밋 시점에는 이미
#   파일이 존재하므로 "구조를 먼저 잡는다" 가 성립하지 않는다. R-iface 와 같은 자리다.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/assets/hooks/claude-pretooluse-plan-declare.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

[[ -f "$HOOK" ]] || { echo "  ✗ 전제: 훅 없음 — $HOOK"; echo "PASS=0 FAIL=1"; exit 1; }
ok "전제: 훅 존재"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
mkdir -p docs/exec-plans/active .git/hooks
cp "$ROOT/assets/hooks/plan_state.py" .git/hooks/ 2>/dev/null || true
mkdir -p scripts/hooks && cp "$ROOT/assets/hooks/plan_state.py" scripts/hooks/

cat > docs/exec-plans/active/2026-08-25-probe.md <<'EOF'
# 계획

## 4. 영향 영역

- 코드: (수정 목록)
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `src/parser/tokenize.py` — 토큰 분해만 담당한다
EOF

# ask <file_path> → 훅 출력(없으면 빈 문자열)
ask() {
  # content 안의 개행은 반드시 JSON 이스케이프(\\n)여야 한다.
  # printf 가 실제 개행으로 펼치면 JSON 이 깨져 훅이 조용히 통과하고,
  # 그러면 이 테스트가 훅을 검사하는 게 아니라 파서 실패를 검사하게 된다.
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/%s","content":"x = 1"}}' "$WORK" "$1" \
    | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK" 2>/dev/null
}

echo "── 선언된 파일은 조용히 통과 ──"
[[ -z "$(ask src/parser/tokenize.py)" ]] && ok "§4 에 선언된 경로는 침묵" || nope "§4 에 선언된 경로는 침묵"

echo "── 선언되지 않은 새 코드 파일은 알린다 ──"
OUT="$(ask src/parser/emit.py)"
echo "$OUT" | grep -q 'R-declare' && ok "미선언 파일에 R-declare 발화" || nope "미선언 파일에 R-declare 발화"
echo "$OUT" | grep -q 'emit.py' && ok "메시지에 해당 경로" || nope "메시지에 해당 경로"
echo "$OUT" | grep -q 'core-beliefs.md#r-declare' && ok "메시지에 근거 앵커" || nope "메시지에 근거 앵커"

echo "── 차단하지 않는다 ──"
# 새 파일 생성은 정당한 경우가 많다(스크래치·픽스처·긴급 수정).
# 차단하면 우회가 상시화된다 — 알리되 막지 않는다.
DECISION=$(echo "$OUT" | python3 -c "
import sys, json
raw = sys.stdin.read().strip()
print(json.loads(raw).get('hookSpecificOutput', {}).get('permissionDecision', 'none') if raw else 'none')
" 2>/dev/null)
[[ "$DECISION" != "deny" ]] && ok "deny 하지 않는다 (경고 등급)" || nope "차단하고 있다"

echo "── 계획이 없으면 침묵한다 ──"
# 계획 부재는 R-plan-missing 이 이미 다룬다. 여기서 또 말하면 경고가 겹친다.
mv docs/exec-plans/active/2026-08-25-probe.md "$WORK/parked.md"
[[ -z "$(ask src/parser/emit.py)" ]] && ok "active/ 가 비면 침묵" || nope "active/ 가 비면 침묵"
mv "$WORK/parked.md" docs/exec-plans/active/2026-08-25-probe.md

echo "── 코드가 아닌 파일은 대상이 아니다 ──"
for f in docs/note.md README.md .cxbaseline data/fixture.json; do
  [[ -z "$(ask "$f")" ]] || nope "$f 는 대상이 아니어야 한다"
done
ok "문서·설정·픽스처는 침묵"

echo "── 이미 있는 파일의 수정은 대상이 아니다 ──"
# 이 훅이 묻는 것은 "이 파일을 만들기 전에 책임을 적었는가" 다.
mkdir -p src/parser && echo "x = 1" > src/parser/emit.py
[[ -z "$(ask src/parser/emit.py)" ]] && ok "기존 파일 덮어쓰기는 침묵" || nope "기존 파일 덮어쓰기는 침묵"
rm -f src/parser/emit.py

echo "── 하네스 생성물은 대상이 아니다 ──"
[[ -z "$(ask scripts/hooks/whatever.py)" ]] && ok "scripts/hooks/ 는 침묵" || nope "scripts/hooks/ 는 침묵"

echo "── 견고성 ──"
printf 'not json' | CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK" >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "깨진 입력에도 exit 0" || nope "깨진 입력에도 exit 0"

echo "── 배선 ──"
grep -q 'claude-pretooluse-plan-declare.sh' "$ROOT/presets/workflow/harness.conf" \
  && ok "harness.conf 에 등록" || nope "harness.conf 에 등록"
grep -q 'claude-pretooluse-plan-declare.sh' <(grep -A 30 'HARNESS_HOOK_SOURCES' "$ROOT/presets/workflow/harness.conf") \
  && ok "HARNESS_HOOK_SOURCES 에 등록" || nope "HARNESS_HOOK_SOURCES 에 등록"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
