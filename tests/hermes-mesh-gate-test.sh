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


# --- stage2 일반성 분류 (mock claude) ---
MOCKDIR="$(mktemp -d)"
trap 'rm -rf "$MOCKDIR"' EXIT
make_mock() {  # $1 = 출력할 판정(GENERAL/SPECIFIC)
  cat > "$MOCKDIR/claude" <<EOF
#!/usr/bin/env bash
echo "$1"
EOF
  chmod +x "$MOCKDIR/claude"
}

run_stage2() {  # $1 = PATH, $2 = HERMES_DISABLED 값(빈 문자열이면 unset)
  local extra_path="$1" disabled="$2"
  if [[ -n "$disabled" ]]; then
    HERMES_DISABLED="$disabled" PATH="$extra_path:$PATH" PYTHONPATH="$SCRIPTS" python3 - <<'PY'
import hermes_mesh_gate as g
print("TRUE" if g.stage2_is_general("일반 지식 본문") else "FALSE")
PY
  else
    env -u HERMES_DISABLED PATH="$extra_path:$PATH" PYTHONPATH="$SCRIPTS" python3 - <<'PY'
import hermes_mesh_gate as g
print("TRUE" if g.stage2_is_general("일반 지식 본문") else "FALSE")
PY
  fi
}

make_mock "GENERAL"
[[ "$(run_stage2 "$MOCKDIR" "")" == "TRUE" ]] \
  && ok "stage2: claude GENERAL → 통과" || nope "stage2: GENERAL 인데 탈락"

make_mock "SPECIFIC"
[[ "$(run_stage2 "$MOCKDIR" "")" == "FALSE" ]] \
  && ok "stage2: claude SPECIFIC → 탈락" || nope "stage2: SPECIFIC 인데 통과"

make_mock "GENERAL"
[[ "$(run_stage2 "$MOCKDIR" "1")" == "FALSE" ]] \
  && ok "stage2: HERMES_DISABLED=1 → claude 안 부르고 탈락" || nope "stage2: DISABLED 인데 통과"

# claude 부재 → 탈락. PATH 를 좁히면 python3 자체를 못 찾으므로,
# shutil.which("claude") 만 None 을 돌려주도록 monkeypatch 한다(python3 는 정상 실행).
NO_CLAUDE="$(env -u HERMES_DISABLED PYTHONPATH="$SCRIPTS" python3 - <<'PY'
import shutil
_orig = shutil.which
shutil.which = lambda name, *a, **k: None if name == "claude" else _orig(name, *a, **k)
import hermes_mesh_gate as g
print("TRUE" if g.stage2_is_general("일반 지식 본문") else "FALSE")
PY
)"
[[ "$NO_CLAUDE" == "FALSE" ]] \
  && ok "stage2: claude 부재 → 탈락" || nope "stage2: claude 없는데 통과"


# --- mesh_gate 오케스트레이션 (mock claude GENERAL 사용) ---
make_mock "GENERAL"
run_gate() {  # stdin=본문, 결과 "passed|reason|scrubbed_contains_redacted"
  PATH="$MOCKDIR:$PATH" PYTHONPATH="$SCRIPTS" python3 - "$1" <<'PY'
import sys, hermes_mesh_gate as g
passed, reason, scrubbed = g.mesh_gate(sys.argv[1])
has_red = "[REDACTED" in (scrubbed or "")
print(f"{passed}|{reason}|{has_red}|{scrubbed if scrubbed else ''}")
PY
}

# 일반 지식 + mock GENERAL → 통과, scrubbed 반환
R="$(run_gate "GraphQL relay 커서 페이지네이션 규약을 따른다")"
[[ "$R" == True\|general\|* ]] \
  && ok "mesh_gate: 일반+GENERAL → 통과" || nope "mesh_gate: 통과 실패 ($R)"

# stage1 신원 마커 → claude 판정과 무관하게 탈락
R="$(run_gate "장정훈 차장이 이 모듈을 담당한다")"
[[ "$R" == False\|korean-title\|* ]] \
  && ok "mesh_gate: 신원 마커 → 탈락(stage2 이전)" || nope "mesh_gate: 신원 탈락 실패 ($R)"

# 통과 본문에 낀 토큰은 최종 스크럽에서 마스킹된다
R="$(run_gate "일반 설정법: export TOKEN=ghp_$(printf 'a%.0s' {1..36})")"
FIRST="${R%%|*}"
[[ "$FIRST" == "True" && "$R" == *"|True|"* ]] \
  && ok "mesh_gate: 통과분 토큰이 스크럽에서 마스킹됨" || nope "mesh_gate: 스크럽 미적용 ($R)"

# stage2 SPECIFIC → 탈락(not-general)
make_mock "SPECIFIC"
R="$(run_gate "GraphQL relay 커서 페이지네이션 규약을 따른다")"
[[ "$R" == False\|not-general\|* ]] \
  && ok "mesh_gate: SPECIFIC → not-general 탈락" || nope "mesh_gate: not-general 실패 ($R)"

echo ""
echo "  결과: $PASS 통과 / $FAIL 실패"
[[ $FAIL -eq 0 ]]
