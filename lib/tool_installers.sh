#!/usr/bin/env bash
# 프리셋이 선언한 외부 바이너리(REQUIRED_BINS)를 확인하고, 없으면 핀 고정 배포 파일로 설치한다.
# 왜 여기서: 도구가 필요한데 사람이 컴퓨터마다 손으로 깔면 소우주마다 켜짐/꺼짐이 갈린다(2026-09-20 age 사례 —
# 어느 소우주도 운반이 안 켜져 있었다). setup·update-all 이 같은 경로로 깔아야 전파가 곧 설치다.
# 원칙: 버전·sha256 을 이 파일에 고정한다(공급망). 대조가 어긋나면 설치하지 않는다. 있으면 건너뛴다. 실패해도 설치기를 세우지 않는다.
# 공개 함수 2개: tool_install_required <project> · tool_status_line
# 계획: docs/exec-plans/active/2026-09-19-agent-memory-roundtrip.md 목표 8

_TOOL_BIN_DIR="${HARNESS_TOOL_BIN_DIR:-$HOME/.local/bin}"
TOOLS_INSTALLED=(); TOOLS_PRESENT=(); TOOLS_FAILED=()

# age — https://github.com/FiloSottile/age (FiloSottile 배포 tar.gz, 2026-09-20 실측 sha256)
_AGE_VERSION="v1.3.2"
_age_sha256() {           # <os>-<arch> → sha256, 모르면 빈 문자열
  case "$1" in
    linux-amd64)  echo cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10 ;;
    linux-arm64)  echo 6b8dc4333c53a5a57c9e5834e3a48f92605d7154014cd07269ff3327db5d37f4 ;;
    darwin-amd64) echo 1d1e4bc66e1427edad7739ae7616157de0e79db8b6d2a1497d7d9925fb06a539 ;;
    darwin-arm64) echo e2020b073c44f692685a24d6abc378817eb81ffaaf49fd0531ef8565f767f2f5 ;;
    *) echo "" ;;
  esac
}

_tool_platform() {        # → linux-amd64 같은 키. 지원 밖이면 빈 문자열
  local os arch
  case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) echo ""; return ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) echo ""; return ;; esac
  echo "$os-$arch"
}

_tool_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# 배포 파일을 tmp 로 가져온다. HARNESS_TOOL_SOURCE_DIR 이 있으면 거기서 복사(테스트·오프라인), 없으면 HTTPS.
_tool_fetch() {           # <파일명> <url> <목적지>
  if [[ -n "${HARNESS_TOOL_SOURCE_DIR:-}" ]]; then
    [[ -f "$HARNESS_TOOL_SOURCE_DIR/$1" ]] && cp "$HARNESS_TOOL_SOURCE_DIR/$1" "$3" && return 0
    return 1
  fi
  command -v curl >/dev/null 2>&1 && curl -fsSL --retry 2 -o "$3" "$2" && return 0
  command -v wget >/dev/null 2>&1 && wget -q -O "$3" "$2" && return 0
  return 1
}

_install_age() {          # age + age-keygen 을 함께 놓는다. 0=설치됨, 1=실패(이유는 로그)
  local plat expected file url tmp got
  plat="$(_tool_platform)"
  expected="$(_age_sha256 "$plat")"
  if [[ -z "$plat" || -z "$expected" ]]; then
    log_warn "age: 이 플랫폼($(uname -s)/$(uname -m))용 핀이 없습니다 — 손으로 설치: https://github.com/FiloSottile/age/releases/tag/$_AGE_VERSION"
    return 1
  fi
  file="age-$_AGE_VERSION-$plat.tar.gz"
  url="https://github.com/FiloSottile/age/releases/download/$_AGE_VERSION/$file"
  tmp="$(mktemp -d)"
  if ! _tool_fetch "$file" "$url" "$tmp/$file"; then
    log_warn "age: 배포 파일을 받지 못했습니다 ($url)"; rm -rf "$tmp"; return 1
  fi
  got="$(_tool_sha256 "$tmp/$file")"
  if [[ "$got" != "${HARNESS_TOOL_EXPECTED_SHA256:-$expected}" ]]; then
    log_error "age: sha256 불일치 — 설치하지 않습니다 (기대 ${expected:0:12}… 실제 ${got:0:12}…). 핀은 lib/tool_installers.sh"
    rm -rf "$tmp"; return 1
  fi
  mkdir -p "$_TOOL_BIN_DIR"
  if ! tar -xzf "$tmp/$file" -C "$tmp" age/age age/age-keygen 2>/dev/null; then
    log_warn "age: 압축 해제 실패"; rm -rf "$tmp"; return 1
  fi
  install -m 0755 "$tmp/age/age" "$_TOOL_BIN_DIR/age" && install -m 0755 "$tmp/age/age-keygen" "$_TOOL_BIN_DIR/age-keygen"
  rm -rf "$tmp"
  log_info "  tool → age $_AGE_VERSION ($plat, sha256 대조 통과) → $_TOOL_BIN_DIR/{age,age-keygen}"
  case ":$PATH:" in *":$_TOOL_BIN_DIR:"*) ;; *) log_warn "  $_TOOL_BIN_DIR 이 PATH 에 없습니다 — 훅이 age 를 못 찾습니다. 셸 설정에 추가하십시오" ;; esac
  return 0
}

# tool_install_required <project>
# REQUIRED_BINS 의 각 이름을 확인하고 없으면 그 도구의 설치기를 부른다. 항상 0 을 돌려준다(설치기를 세우지 않는다).
tool_install_required() {
  local bin
  [[ ${#REQUIRED_BINS[@]} -gt 0 ]] || return 0
  if [[ "${HARNESS_TOOL_INSTALL:-1}" == "0" ]]; then log_info "Required tools: 설치 생략(HARNESS_TOOL_INSTALL=0) — ${REQUIRED_BINS[*]}"; return 0; fi
  log_info "Checking required tools… (${REQUIRED_BINS[*]})"
  for bin in "${REQUIRED_BINS[@]}"; do
    if command -v "$bin" >/dev/null 2>&1 || [[ -x "$_TOOL_BIN_DIR/$bin" ]]; then
      TOOLS_PRESENT+=("$bin"); continue
    fi
    case "$bin" in
      age|age-keygen)
        # 둘은 한 배포 파일에서 나온다 — 하나가 실패했으면 다시 받지 않는다
        if [[ " ${TOOLS_FAILED[*]:-} " == *" age "* || " ${TOOLS_FAILED[*]:-} " == *" age-keygen "* ]]; then TOOLS_FAILED+=("$bin"); continue; fi
        if _install_age; then TOOLS_INSTALLED+=("$bin"); else TOOLS_FAILED+=("$bin"); fi ;;
      *)
        log_warn "  $bin: 설치기에 핀이 없는 도구입니다 — lib/tool_installers.sh 에 추가하거나 손으로 설치"; TOOLS_FAILED+=("$bin") ;;
    esac
  done
  return 0
}

# 요약 한 줄 (설치 로그 끝에)
tool_status_line() {
  [[ ${#REQUIRED_BINS[@]} -gt 0 ]] || return 0
  echo "Tools (${#REQUIRED_BINS[@]}): present=${TOOLS_PRESENT[*]:-<none>} installed=${TOOLS_INSTALLED[*]:-<none>} failed=${TOOLS_FAILED[*]:-<none>}"
}
