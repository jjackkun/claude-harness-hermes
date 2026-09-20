#!/usr/bin/env bash
# lib/tool_installers.sh 실측 (계획 agent-memory-roundtrip 목표 8). 네트워크 0 — 픽스처 tar.gz 를 HARNESS_TOOL_SOURCE_DIR 로 준다.
#   1. 이미 있으면 무동작(present)
#   2. 없으면 픽스처를 받아 sha256 대조 뒤 HARNESS_TOOL_BIN_DIR 에 age·age-keygen 을 놓는다(installed)
#   3. sha256 이 어긋나면 설치하지 않는다(failed, 파일 0)
#   4. REQUIRED_BINS 가 비면 아무 줄도 내지 않는다
# 실행: bash tests/tool-installers-test.sh
set -uo pipefail
export HARNESS_TOOL_INSTALL=1   # run-all.sh 가 전역으로 0 을 내보낸다 — 이 테스트는 바로 그 기능을 검증하므로 스스로 켠다(픽스처(HARNESS_TOOL_SOURCE_DIR)만 쓰므로 네트워크 0). 2026-09-20: 이것 없이 CI 에서 통째로 빨갰다
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/fakehome"; mkdir -p "$HOME"
PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  ✓ $desc"; PASS=$((PASS+1))
  else echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1)); fi
}

# 픽스처 배포 파일 — 진짜와 같은 이름·같은 내부 경로(age/age, age/age-keygen)
SRC="$TMP/src"; mkdir -p "$SRC/age"
printf '#!/usr/bin/env bash\necho "age fixture v1.3.2"\n' > "$SRC/age/age"
printf '#!/usr/bin/env bash\necho "age-keygen fixture"\n' > "$SRC/age/age-keygen"
chmod +x "$SRC/age/age" "$SRC/age/age-keygen"
source "$REPO_ROOT/lib/tool_installers.sh" >/dev/null 2>&1 || true   # _tool_platform 만 빌린다
PLAT="$(_tool_platform)"
[[ -n "$PLAT" ]] || { echo "지원 밖 플랫폼 — 건너뜀"; exit 0; }
FILE="age-v1.3.2-$PLAT.tar.gz"
tar -czf "$SRC/$FILE" -C "$SRC" age/age age/age-keygen
GOOD_SHA="$(sha256sum "$SRC/$FILE" | cut -d' ' -f1)"

# 시스템 도구는 그대로 쓰되 **age · age-keygen 만 뺀** PATH 를 만든다. /usr/bin 을 그대로 넣으면 age 가 깔린 기계(CI 러너 — 2026-09-20 부터 apt 로 설치)에서
# "없으면 설치한다" 시나리오가 성립하지 않는다(실측: [2]·[3] 이 통째로 빨갰다).
SYSBIN="$TMP/sysbin"; mkdir -p "$SYSBIN"
find /usr/bin /bin -maxdepth 1 \( -type f -o -type l \) ! -name age ! -name age-keygen -exec ln -sf -t "$SYSBIN" {} + 2>/dev/null

run() { # run <expected_sha> <bin_dir> [PATH 앞머리] → 로그를 $OUT 에, 배열은 전역
  local sha="$1" bin="$2" pre="${3:-}"
  OUT="$(
    export PATH="${pre:+$pre:}$SYSBIN"
    export HARNESS_TOOL_SOURCE_DIR="$SRC" HARNESS_TOOL_EXPECTED_SHA256="$sha" HARNESS_TOOL_BIN_DIR="$bin"
    source "$REPO_ROOT/lib/logging.sh"; source "$REPO_ROOT/lib/tool_installers.sh"
    REQUIRED_BINS=(age age-keygen)
    tool_install_required "$TMP/proj" 2>&1; tool_status_line
  )"
}

echo "[1] 이미 있으면 무동작"
PRE="$TMP/prebin"; mkdir -p "$PRE"; cp "$SRC/age/age" "$PRE/age"; cp "$SRC/age/age-keygen" "$PRE/age-keygen"
run "$GOOD_SHA" "$TMP/bin1" "$PRE"
assert "present 에 둘 다" "1" "$(printf '%s' "$OUT" | grep -c 'present=age age-keygen')"
assert "설치 파일 0" "0" "$(ls "$TMP/bin1" 2>/dev/null | wc -l)"

echo "[2] 없으면 픽스처로 설치 (sha256 대조 통과)"
run "$GOOD_SHA" "$TMP/bin2"
assert "installed=age" "1" "$(printf '%s' "$OUT" | grep -c 'installed=age')"
assert "age 실행 가능" "age fixture v1.3.2" "$("$TMP/bin2/age" 2>/dev/null)"
assert "age-keygen 도 함께" "1" "$([[ -x "$TMP/bin2/age-keygen" ]] && echo 1 || echo 0)"
assert "PATH 경고(bin2 는 PATH 밖)" "1" "$(printf '%s' "$OUT" | grep -c 'PATH 에 없습니다')"

echo "[3] sha256 불일치면 설치하지 않는다"
run "deadbeef" "$TMP/bin3"
assert "failed=age age-keygen" "1" "$(printf '%s' "$OUT" | grep -c 'failed=age age-keygen')"
assert "sha256 불일치 로그" "1" "$(printf '%s' "$OUT" | grep -c 'sha256 불일치')"
assert "설치 파일 0" "0" "$(ls "$TMP/bin3" 2>/dev/null | wc -l)"

echo "[4] REQUIRED_BINS 비면 조용하다"
OUT4="$(source "$REPO_ROOT/lib/logging.sh"; source "$REPO_ROOT/lib/tool_installers.sh"; REQUIRED_BINS=(); tool_install_required "$TMP/proj" 2>&1; tool_status_line)"
assert "출력 없음" "" "$OUT4"

echo
echo "tool-installers: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
