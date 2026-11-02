#!/usr/bin/env bash
# 계획 2026-11-02-new-pc-restore G2 — 같은 프리셋 집합은 넘긴 순서와 상관없이 같은 결과를 낸다.
#
# 2026-11-02 jj-agent-room: 같은 13개를 다른 순서로 넘기자 CLAUDE.md · settings.json · .gitignore 가
# 474줄 바뀌었다(내용은 같고 순서만). 정렬 기준은 setup.sh 단계 순서(resolve_preset 의 분류 순) →
# 같은 분류 안에서는 이름순(LC_ALL=C).
#
# 격리: 저장소를 임시 사본에 복사하고 HOME 을 바꿔 실행한다(preset-lock-tracked-test 와 같은 방식).
set -uo pipefail
export HARNESS_TOOL_INSTALL=0 HARNESS_SYNC_AUTOENABLE=0 HERMES_NO_REGISTER=1
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); export HOME="$TMP/fakehome"; mkdir -p "$HOME"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

SANDBOX="$TMP/harness"; mkdir -p "$SANDBOX"
tar -c --exclude=.git -C "$REPO_ROOT" . | tar -x -C "$SANDBOX"
rm -f "$SANDBOX/.installed-projects" "$SANDBOX/.installed-projects.codex"

# 결과 파일에 프로젝트 경로가 들어갈 수 있으므로 매번 같은 경로에 새로 만든다
P="$TMP/proj"
FILES=(CLAUDE.md .claude/settings.json .gitignore .claude/presets.lock)
run_order() { # run_order <이름> <프리셋...> → $TMP/out/<이름>/ 에 관리 파일 사본
  local name="$1"; shift
  rm -rf "$P"; mkdir -p "$P"; git -C "$P" init -q
  bash "$SANDBOX/project-claude.sh" "$P" "$@" >"$TMP/$name.log" 2>&1
  assert "[$name] 설치 rc 0" 0 "$?"
  mkdir -p "$TMP/out/$name"
  local f; for f in "${FILES[@]}"; do cp "$P/$f" "$TMP/out/$name/$(echo "$f" | tr / _)" 2>/dev/null; done
}

echo "== 서로 다른 순서 3가지 =="
run_order a python fastapi postgres harness hermes korean pm2
run_order b pm2 korean hermes harness postgres fastapi python
run_order c hermes postgres pm2 python korean fastapi harness

for f in "${FILES[@]}"; do
  k="$(echo "$f" | tr / _)"
  assert "$f 가 a·b 같음" 0 "$(cmp -s "$TMP/out/a/$k" "$TMP/out/b/$k"; echo $?)"
  assert "$f 가 a·c 같음" 0 "$(cmp -s "$TMP/out/a/$k" "$TMP/out/c/$k"; echo $?)"
done

echo "== lock 은 분류 순 → 이름순 =="
want=$'python\nfastapi\npostgres\nharness\nhermes\nkorean\npm2'
assert "lock 내용" "$want" "$(cat "$TMP/out/b/.claude_presets.lock")"

echo "== sort_presets: 분류 순 · 중복 하나로 · 모르는 이름 맨 뒤 · 이름순은 바이트 순(LC_ALL=C) =="
# 가짜 프리셋 폴더로 함수만 부른다(설치 없음). 대문자는 C 에서 소문자보다 앞, en_US 에서는 뒤 —
# 그 locale 이 있는 PC 에서만 LC_ALL=C 를 지운 변형을 잡는다(없으면 C 로 되돌아가 같은 결과).
FAKE_DS="$TMP/fake-ds"; mkdir -p "$FAKE_DS/presets/lang" "$FAKE_DS/presets/workflow"
: > "$FAKE_DS/presets/lang/x.conf"; : > "$FAKE_DS/presets/workflow/alpha.conf"; : > "$FAKE_DS/presets/workflow/Zeta.conf"
got="$(DEV_SETTING_DIR="$FAKE_DS" LC_ALL=en_US.UTF-8 bash -c 'source "$1/lib/preset.sh"; sort_presets alpha nope Zeta x alpha' _ "$REPO_ROOT" 2>/dev/null)"
assert "정렬 결과" $'x\nZeta\nalpha\nnope' "$got"
locale -a 2>/dev/null | grep -qi '^en_US\.utf-\?8$' || echo "  (참고: en_US.UTF-8 locale 이 없어 LC_ALL=C 제거 변형은 이 PC 에서 못 잡습니다)"

echo; echo "preset-order-stable: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]
