#!/usr/bin/env bash
# 그물망 승격 게이트 회귀 테스트
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
nope() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

# --- stage1 탈락 필터 ---
run_stage1() {
PYTHONPATH="$SCRIPTS" python3 - <<'PY'
import hermes_mesh_gate as g

def expect(name, text, want_reject):
    rej, reason = g.stage1_reject(text)
    if rej == want_reject:
        print(f"OK::{name} (reason={reason})")
    else:
        print(f"FAIL::{name} (got reject={rej} reason={reason}, want={want_reject})")

# 탈락해야 함 (신원/맥락 마커)
expect("title-차장", "장정훈 차장이 백엔드 배포를 담당한다", True)
expect("title-대리", "김 대리에게 물어보면 된다", True)
expect("emp-id", "담당자 사번: EMP12345 확인", True)
expect("abs-path-home", "/home/jjackkun/PROJECT/zeroday 에서 빌드한다", True)
expect("abs-path-win", "C:\\Users\\hong\\project 경로를 연다", True)
expect("email", "문의는 hong@example.com 으로", True)
expect("phone", "연락처 010-1234-5678", True)
expect("empty", "", True)
expect("none", None, True)

# 통과해야 함 (일반 지식 — 신원/맥락 마커 없음)
expect("general-1", "GraphQL relay 커서 규약으로 페이지네이션을 구현한다", False)
expect("general-2", "SQLite 는 busy_timeout 과 WAL 을 켜 동시성을 완화한다", False)
expect("general-token-only", "예시 토큰 ghp_" + "a"*36 + " 는 스크럽 단계에서 가린다", False)
PY
}
OUT="$(run_stage1)"
while IFS= read -r line; do
  case "$line" in
    OK::*)   ok "${line#OK::}" ;;
    FAIL::*) nope "${line#FAIL::}" ;;
  esac
done <<<"$OUT"

echo ""
echo "  결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
