#!/usr/bin/env bash
# lib/tool_installers.sh 실측 (계획 agent-memory-roundtrip 목표 8). 네트워크 0 — 픽스처 tar.gz 를 HARNESS_TOOL_SOURCE_DIR 로 준다.
#   1. 이미 있으면 무동작(present)
#   2. 없으면 픽스처를 받아 sha256 대조 뒤 HARNESS_TOOL_BIN_DIR 에 age·age-keygen 을 놓는다(installed)
#   3. sha256 이 어긋나면 설치하지 않는다(failed, 파일 0)
#   4. REQUIRED_BINS 가 비면 아무 줄도 내지 않는다
#   5~9. pytest — 프로젝트 가상환경에만: 시험 없으면 skipped · 돌면 present · 깨졌으면 그 가상환경에 재설치 · 없으면 .venv 생성 · 실패는 안내. 전역(sudo·apt) 호출 0
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
find /usr/bin /bin -maxdepth 1 \( -type f -o -type l \) ! -name age ! -name age-keygen ! -name pytest ! -name pytest-3 ! -name sudo ! -name apt-get ! -name python3 -exec ln -sf -t "$SYSBIN" {} + 2>/dev/null

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

# ── pytest — 프로젝트 가상환경에만. 가짜 python3(-m venv) · 가짜 가상환경 python(-m pip) · 가짜 sudo/apt(불리면 기록) ──
FAKE="$TMP/fake"; mkdir -p "$FAKE/cmd"
cat > "$FAKE/venvpy" <<'SH'
#!/usr/bin/env bash
# 가상환경 안의 python — `-m pip install ...` 이면 기록하고 같은 bin 에 실행되는 pytest 를 놓는다
d="$(cd "$(dirname "$0")" && pwd)"
[[ "$1 $2" == "-m pip" ]] || exit 1
echo "$d $*" >> "$FAKE_PIP_LOG"
printf '#!/usr/bin/env bash\necho "pytest 9.1.1"\n' > "$d/pytest"; chmod +x "$d/pytest"
SH
cat > "$FAKE/cmd/python3" <<SH
#!/usr/bin/env bash
# 시스템 python3 — \`-m venv DIR\` 만 흉내 낸다
[[ "\$1 \$2" == "-m venv" ]] || exit 1
[[ "\${FAKE_VENV_FAIL:-0}" == 1 ]] && { echo "ensurepip is not available" >&2; exit 1; }
mkdir -p "\$3/bin" && cp "$FAKE/venvpy" "\$3/bin/python" && chmod +x "\$3/bin/python"
SH
for c in sudo apt-get; do printf '#!/usr/bin/env bash\necho "%s $*" >> "$FAKE_GLOBAL_LOG"\n' "$c" > "$FAKE/cmd/$c"; done
chmod +x "$FAKE/venvpy" "$FAKE/cmd/"*

mkproj() { # mkproj <이름> [tests] → 경로. tests 면 tests/test_a.py 를 둔다
  local d="$TMP/$1"; mkdir -p "$d"; [[ "${2:-}" == tests ]] && { mkdir -p "$d/tests"; : > "$d/tests/test_a.py"; }; echo "$d"
}
mkvenv() { # mkvenv <venv 폴더> <ok|broken|none>
  mkdir -p "$1/bin"; cp "$FAKE/venvpy" "$1/bin/python"
  case "$2" in
    ok) printf '#!/usr/bin/env bash\necho "pytest 9.1.1"\n' > "$1/bin/pytest"; chmod +x "$1/bin/pytest" ;;
    broken) printf '#!/usr/bin/env bash\necho "No module named pytest" >&2; exit 1\n' > "$1/bin/pytest"; chmod +x "$1/bin/pytest" ;;
  esac
}
run_py() { # run_py <프로젝트> [FAKE_VENV_FAIL] → $OUT, pip 기록 $FAKE/pip.log, 전역 호출 기록 $FAKE/global.log
  rm -f "$FAKE/pip.log" "$FAKE/global.log"
  OUT="$(
    export PATH="$FAKE/cmd:$SYSBIN" FAKE_PIP_LOG="$FAKE/pip.log" FAKE_GLOBAL_LOG="$FAKE/global.log" FAKE_VENV_FAIL="${2:-0}"
    source "$REPO_ROOT/lib/logging.sh"; source "$REPO_ROOT/lib/tool_installers.sh"
    REQUIRED_BINS=(pytest)
    tool_install_required "$1" 2>&1 </dev/null; tool_status_line
  )"
}
no_global() { assert "전역(sudo·apt) 호출 0" "0" "$([[ -f "$FAKE/global.log" ]] && echo 1 || echo 0)"; }

echo "[5] 파이썬 시험이 없으면 아무것도 만들지 않는다"
P5="$(mkproj p5)"; run_py "$P5"
assert "skipped=pytest" "1" "$(printf '%s' "$OUT" | grep -c 'skipped=pytest')"
assert ".venv 안 만듦" "0" "$([[ -e "$P5/.venv" ]] && echo 1 || echo 0)"
assert "pip 호출 0" "0" "$([[ -f "$FAKE/pip.log" ]] && echo 1 || echo 0)"; no_global

echo "[6] 가상환경 pytest 가 실행되면 무동작"
P6="$(mkproj p6 tests)"; mkvenv "$P6/.venv" ok; run_py "$P6"
assert "present=pytest" "1" "$(printf '%s' "$OUT" | grep -c 'present=pytest')"
assert "pip 호출 0" "0" "$([[ -f "$FAKE/pip.log" ]] && echo 1 || echo 0)"; no_global

echo "[7] 가상환경의 pytest 가 깨졌으면 그 가상환경에만 다시 설치"
P7="$(mkproj p7 tests)"; mkvenv "$P7/backend/venv" broken; run_py "$P7"
assert "backend/venv 의 pip 로 핀 설치" "1" "$(grep -c "^$P7/backend/venv/bin -m pip install .*pytest==9.1.1" "$FAKE/pip.log" 2>/dev/null)"
assert "installed=pytest" "1" "$(printf '%s' "$OUT" | grep -c 'installed=pytest')"
assert "루트 .venv 안 만듦" "0" "$([[ -e "$P7/.venv" ]] && echo 1 || echo 0)"; no_global

echo "[8] 가상환경이 없으면 <프로젝트>/.venv 를 만들고 거기에만 설치"
P8="$(mkproj p8 tests)"; run_py "$P8"
assert ".venv/bin/python 생김" "1" "$([[ -x "$P8/.venv/bin/python" ]] && echo 1 || echo 0)"
assert ".venv 의 pip 로 설치" "1" "$(grep -c "^$P8/.venv/bin -m pip install" "$FAKE/pip.log" 2>/dev/null)"
assert "installed=pytest" "1" "$(printf '%s' "$OUT" | grep -c 'installed=pytest')"; no_global

echo "[8b] 설치 스크립트와 같은 set -euo pipefail 에서도 끝까지 간다 (2026-10-21 zeroday-frontend: 가상환경 없음 → 조용히 종료)"
P8B="$(mkproj p8b tests)"
OUT="$(
  set -euo pipefail
  export PATH="$FAKE/cmd:$SYSBIN" FAKE_PIP_LOG="$FAKE/pip.log" FAKE_GLOBAL_LOG="$FAKE/global.log" FAKE_VENV_FAIL=0
  source "$REPO_ROOT/lib/logging.sh"; source "$REPO_ROOT/lib/tool_installers.sh"
  REQUIRED_BINS=(pytest)
  tool_install_required "$P8B" 2>&1 </dev/null; tool_status_line; echo "끝까지 옴"
)"   # `|| true` 를 붙이면 bash 가 안쪽 set -e 를 꺼 버려 결함이 숨는다 — 붙이지 않는다
assert "set -e 아래에서 끝까지 옴" "1" "$(printf '%s' "$OUT" | grep -c '끝까지 옴')"
assert "set -e 아래에서도 installed=pytest" "1" "$(printf '%s' "$OUT" | grep -c 'installed=pytest')"

echo "[9] 가상환경을 못 만들면 세우지 않고 손으로 칠 명령을 남긴다"
P9="$(mkproj p9 tests)"; run_py "$P9" 1
assert "failed=pytest" "1" "$(printf '%s' "$OUT" | grep -c 'failed=pytest')"
assert "손으로 칠 명령 안내" "1" "$(printf '%s' "$OUT" | grep -c 'python3 -m venv .venv')"
assert "pip 호출 0" "0" "$([[ -f "$FAKE/pip.log" ]] && echo 1 || echo 0)"; no_global

echo
echo "tool-installers: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
