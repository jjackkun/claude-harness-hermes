#!/usr/bin/env bash
# 네이티브 메모리 심링크 설치 라운드트립 — HOME 오버라이드로 실 ~/.claude/projects 격리.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/fakehome"           # 실 ~/.claude/projects 절대 격리
mkdir -p "$HOME"
PROJ="$T/proj"; mkdir -p "$PROJ/.claude"

PASS=0; FAIL=0
assert() { local d="$1" e="$2" a="$3"
  if [[ "$e" == "$a" ]]; then echo "  ✓ $d"; PASS=$((PASS+1))
  else echo "  ✗ $d (expected='$e' actual='$a')"; FAIL=$((FAIL+1)); fi }
exists() { [[ -e "$1" ]] && echo 1 || echo 0; }
islink() { [[ -L "$1" ]] && echo 1 || echo 0; }

# 함수 로드 (lib 직접 source — common.sh 부수효과 회피)
source "$REPO_ROOT/lib/windows.sh"
source "$REPO_ROOT/lib/harness_installers.sh"

KEY="$(printf '%s' "$PROJ" | sed 's/[^a-zA-Z0-9]/-/g')"
NATIVE="$HOME/.claude/projects/$KEY/memory"
REPO_MEM="$PROJ/.claude/memory"

echo "== 1. 기존 네이티브 메모리가 있는 상태에서 설치 → 비파괴 이관 + 심링크 =="
mkdir -p "$NATIVE"
printf -- '---\nname: fact-a\n---\n사실 A\n' > "$NATIVE/fact-a.md"
printf '# Memory Index\n- [fact-a](fact-a.md)\n'      > "$NATIVE/MEMORY.md"

install_memory_symlink "$PROJ"

assert "네이티브가 심링크로 전환됨"        1 "$(islink "$NATIVE")"
assert "심링크 대상이 repo .claude/memory" "$REPO_MEM" "$(readlink "$NATIVE")"
assert "기존 fact-a.md 가 repo 로 이관됨"   1 "$(exists "$REPO_MEM/fact-a.md")"
assert "기존 MEMORY.md 가 repo 로 이관됨"   1 "$(exists "$REPO_MEM/MEMORY.md")"
assert "심링크 통해 기존 파일 읽힘"          1 "$(exists "$NATIVE/fact-a.md")"

echo "== 2. 심링크 통해 새 파일 쓰면 repo 실디렉터리에 반영 =="
printf 'B\n' > "$NATIVE/fact-b.md"
assert "링크로 쓴 fact-b.md 가 repo 원본에 존재" 1 "$(exists "$REPO_MEM/fact-b.md")"

echo "== 3. 멱등 재실행 — 이미 올바른 링크면 무동작(파일 보존) =="
install_memory_symlink "$PROJ"
assert "재실행 후에도 심링크 유지"    1 "$(islink "$NATIVE")"
assert "재실행 후 fact-b.md 보존"     1 "$(exists "$REPO_MEM/fact-b.md")"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
