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

echo "== 4. 동명 충돌 시 네이티브본 무손실 보존 (.native) =="
PROJ2="$T/proj2"; mkdir -p "$PROJ2/.claude"
KEY2="$(printf '%s' "$PROJ2" | sed 's/[^a-zA-Z0-9]/-/g')"
NATIVE2="$HOME/.claude/projects/$KEY2/memory"
REPO_MEM2="$PROJ2/.claude/memory"

mkdir -p "$REPO_MEM2"
printf 'Y (repo 기존본)\n' > "$REPO_MEM2/MEMORY.md"   # repo 에 이미 커밋된 버전
mkdir -p "$NATIVE2"
printf 'X (네이티브 신규 기록)\n' > "$NATIVE2/MEMORY.md"  # 내용 다른 네이티브본

install_memory_symlink "$PROJ2"

assert "repo MEMORY.md(Y) 그대로 유지"        1 "$(exists "$REPO_MEM2/MEMORY.md")"
assert "repo MEMORY.md 내용은 여전히 Y"       "Y (repo 기존본)" "$(cat "$REPO_MEM2/MEMORY.md")"
assert "네이티브본(X)이 .native 로 보존됨"     1 "$(exists "$REPO_MEM2/MEMORY.md.native")"
assert "보존된 .native 내용이 X"              "X (네이티브 신규 기록)" "$(cat "$REPO_MEM2/MEMORY.md.native" 2>/dev/null)"
assert "충돌 후에도 심링크 정상 전환"          1 "$(islink "$NATIVE2")"

echo "== 5. 네이티브가 엉뚱한 대상을 가리키는 심링크면 repo 로 교정 =="
PROJ3="$T/proj3"; mkdir -p "$PROJ3/.claude"
KEY3="$(printf '%s' "$PROJ3" | sed 's/[^a-zA-Z0-9]/-/g')"
NATIVE3="$HOME/.claude/projects/$KEY3/memory"
REPO_MEM3="$PROJ3/.claude/memory"

OTHER_DIR="$T/other-target"; mkdir -p "$OTHER_DIR"
mkdir -p "$(dirname "$NATIVE3")"
ln -s "$OTHER_DIR" "$NATIVE3"   # 엉뚱한 대상을 가리키는 기존 심링크

install_memory_symlink "$PROJ3"

assert "네이티브가 심링크로 남아있음"       1 "$(islink "$NATIVE3")"
assert "심링크 대상이 repo .claude/memory 로 교정됨" "$REPO_MEM3" "$(readlink "$NATIVE3")"

echo "== 6. 반복 이관 시 .native 백업도 충돌-안전(번호 부여) — 이전 백업 유실 방지 =="
rm -f "$NATIVE2"                          # 심링크 제거 후 실디렉터리로 재구성
mkdir -p "$NATIVE2"
printf 'X2 (두 번째 네이티브 신규 기록)\n' > "$NATIVE2/MEMORY.md"  # X1, Y 와 모두 다른 내용

install_memory_symlink "$PROJ2"

assert "1차 백업(X1)이 그대로 보존됨"          "X (네이티브 신규 기록)" "$(cat "$REPO_MEM2/MEMORY.md.native" 2>/dev/null)"
assert "2차 충돌본(X2)이 번호 부여로 보존됨"    1 "$(exists "$REPO_MEM2/MEMORY.md.native.1")"
assert "보존된 .native.1 내용이 X2"           "X2 (두 번째 네이티브 신규 기록)" "$(cat "$REPO_MEM2/MEMORY.md.native.1" 2>/dev/null)"
assert "repo MEMORY.md(Y) 여전히 유지"        "Y (repo 기존본)" "$(cat "$REPO_MEM2/MEMORY.md")"
assert "재이관 후에도 심링크 정상 전환"        1 "$(islink "$NATIVE2")"

echo "== 7. gitignore: 블랭킷 .claude/ 가 있어도 .claude/memory 는 추적 =="
# install_harness_gitignore 는 log_info 를 사용하나 이 테스트는 logging.sh 를 소스하지 않음 — 무해한 no-op 로 보강
command -v log_info >/dev/null 2>&1 || log_info() { :; }
GP="$T/gitproj"; mkdir -p "$GP/.claude/memory"
( cd "$GP" && git init -q && printf '.claude/\n' > .gitignore )
printf 'x\n' > "$GP/.claude/memory/x.md"
install_harness_gitignore "$GP" "claude"
# git check-ignore: 무시되면 exit 0(파일명 출력), 추적되면 exit 1
if ( cd "$GP" && git check-ignore -q .claude/memory/x.md ); then ig=1; else ig=0; fi
assert ".claude/memory/x.md 는 무시되지 않음(추적)" 0 "$ig"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
