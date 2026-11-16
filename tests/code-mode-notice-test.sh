#!/usr/bin/env bash
# lib/code_mode_notice.sh (계획 2026-11-16-code-mode-notice G1~G4) — 가짜 claude·임시 설정, 실제 ~/.claude 는 건드리지 않는다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
N="$REPO_ROOT/lib/code_mode_notice.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

fake_claude() { printf '#!/usr/bin/env bash\necho "%s (Claude Code)"\n' "$1" > "$TMP/claude"; chmod +x "$TMP/claude"; }
run() {  # run [설정 json] → 출력
  mkdir -p "$TMP/cfg"; rm -f "$TMP/cfg/settings.json"
  [[ -n "${1:-}" ]] && printf '%s' "$1" > "$TMP/cfg/settings.json"
  env -u CLAUDE_CODE_EXPERIMENTAL_CODE_MODE CLAUDE_CONFIG_DIR="$TMP/cfg" CODE_MODE_NOTICE_CLAUDE="$TMP/claude" bash "$N" 2>&1
}

echo "[G1] 켤 수 있는데 설정이 없으면 켜는 법을 알린다"
fake_claude 2.1.325
out=$(run '{"env":{"OTHER":"x"}}')
assert "한 줄" 1 "$(printf '%s\n' "$out" | grep -c .)"
assert "켜는 설정을 그대로 보인다" 1 "$(grep -c '"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE": "1"' <<< "$out")"
assert "컴퓨터마다라는 것을 말한다" 1 "$(grep -c '컴퓨터마다' <<< "$out")"
assert "설정 파일이 없어도 알린다" 1 "$(run '' | grep -c 'CODE_MODE')"
assert "2.1.323 딱 그 판도 켤 수 있다" 1 "$(fake_claude 2.1.323; run '{}' | grep -c '"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE": "1"')"
assert "2.2.0 같은 더 큰 판도 켤 수 있다" 1 "$(fake_claude 2.2.0; run '{}' | grep -c '"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE": "1"')"

echo "[G2] 이미 켰거나 일부러 껐으면 침묵"
fake_claude 2.1.325
assert "사용자 설정에 1" "" "$(run '{"env":{"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"1"}}')"
assert "사용자 설정에 0" "" "$(run '{"env":{"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"0"}}')"
got=$(CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1 CLAUDE_CONFIG_DIR="$TMP/cfg" CODE_MODE_NOTICE_CLAUDE="$TMP/claude" bash "$N" 2>&1)
assert "셸 환경변수로 켬" "" "$got"

echo "[G3] 판이 낮거나 클로드 코드가 없을 때"
fake_claude 2.1.314
out=$(run '{}')
assert "낮은 판 → 올리라는 한 줄" 1 "$(grep -c 'claude update' <<< "$out")"
assert "낮은 판이면 켜는 설정은 아직 보이지 않는다" 0 "$(grep -c '"1"' <<< "$out")"
got=$(env -u CLAUDE_CODE_EXPERIMENTAL_CODE_MODE CLAUDE_CONFIG_DIR="$TMP/cfg" CODE_MODE_NOTICE_CLAUDE="$TMP/none" PATH="/nonexistent" HOME="$TMP/nohome" /bin/bash "$N" 2>&1)
assert "클로드 코드가 없으면 침묵" "" "$got"
fake_claude 2.1.325; printf '{ 깨진' > "$TMP/cfg/settings.json"
got=$(env -u CLAUDE_CODE_EXPERIMENTAL_CODE_MODE CLAUDE_CONFIG_DIR="$TMP/cfg" CODE_MODE_NOTICE_CLAUDE="$TMP/claude" bash "$N" 2>&1); code=$?
assert "깨진 설정 파일이어도 설치를 멈추지 않는다(0)" 0 "$code"
assert "깨진 설정 파일이면 읽지 못했다고 알린다" 1 "$(grep -c '읽지 못' <<< "$got")"

echo "[G4] 사용자 설정 파일은 읽기만 한다"
fake_claude 2.1.325; printf '{"env":{"OTHER":"x"}}' > "$TMP/cfg/settings.json"
before=$(sha256sum "$TMP/cfg/settings.json" | cut -d' ' -f1)
env -u CLAUDE_CODE_EXPERIMENTAL_CODE_MODE CLAUDE_CONFIG_DIR="$TMP/cfg" CODE_MODE_NOTICE_CLAUDE="$TMP/claude" bash "$N" > /dev/null 2>&1
assert "앞뒤 해시가 같다" "$before" "$(sha256sum "$TMP/cfg/settings.json" | cut -d' ' -f1)"

echo "[연결] 두 설치 스크립트가 끝에서 부른다"
assert "setup.sh" 1 "$(grep -c 'lib/code_mode_notice.sh' "$REPO_ROOT/setup.sh")"
assert "setup.sh 는 안내 뒤에도 설치의 종료 코드를 그대로 돌려준다" 1 "$(grep -c '^exit "\$SETUP_RC"' "$REPO_ROOT/setup.sh")"
assert "update-all.sh" 1 "$(grep -c 'lib/code_mode_notice.sh' "$REPO_ROOT/update-all.sh")"

echo; echo "code-mode-notice: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
